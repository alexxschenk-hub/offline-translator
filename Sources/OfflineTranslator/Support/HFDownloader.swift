import Foundation

/// Minimaler, abhängigkeitsfreier Downloader für Hugging-Face-Repositories.
/// Wird nur beim ersten Herunterladen eines Modells benötigt – danach läuft alles offline.
enum HFDownloader {
    struct RepoFile: Decodable {
        let type: String
        let path: String
        let size: Int64?
        let lfs: LFS?

        struct LFS: Decodable { let size: Int64? }

        var byteSize: Int64 { lfs?.size ?? size ?? 0 }
    }

    enum DownloadError: LocalizedError {
        case badResponse(String)
        case emptyRepo(String)

        var errorDescription: String? {
            switch self {
            case .badResponse(let s): return "Download fehlgeschlagen: \(s)"
            case .emptyRepo(let r): return "Im Repository \(r) wurden keine Modelldateien gefunden."
            }
        }
    }

    static let completeMarker = ".download-complete"

    static func isComplete(_ folder: URL) -> Bool {
        FileManager.default.fileExists(atPath: folder.appendingPathComponent(completeMarker).path)
    }

    /// Lädt alle relevanten Dateien eines Repos nach `destination` herunter.
    /// - Parameter progress: (Anteil 0…1, Statustext)
    static func downloadRepo(
        _ repo: String,
        to destination: URL,
        allowedExtensions: Set<String> = ["json", "safetensors", "jinja", "model", "txt", "tiktoken"],
        progress: @escaping @Sendable (Double, String) -> Void
    ) async throws -> URL {
        if isComplete(destination) { return destination }
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        let listURL = URL(string: "https://huggingface.co/api/models/\(repo)/tree/main?recursive=true")!
        let (data, response) = try await URLSession.shared.data(from: listURL)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw DownloadError.badResponse("Dateiliste von \(repo) (HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1))")
        }
        let files = try JSONDecoder().decode([RepoFile].self, from: data)
            .filter { $0.type == "file" }
            .filter { allowedExtensions.contains(($0.path as NSString).pathExtension.lowercased()) }
        guard !files.isEmpty else { throw DownloadError.emptyRepo(repo) }

        let totalBytes = max(1, files.reduce(Int64(0)) { $0 + $1.byteSize })
        var doneBytes: Int64 = 0

        for file in files {
            try Task.checkCancellation()
            let target = destination.appendingPathComponent(file.path)
            if let attrs = try? FileManager.default.attributesOfItem(atPath: target.path),
               let size = attrs[.size] as? Int64, size == file.byteSize, size > 0 {
                doneBytes += file.byteSize
                continue
            }
            try FileManager.default.createDirectory(
                at: target.deletingLastPathComponent(), withIntermediateDirectories: true)

            let encodedPath = file.path
                .split(separator: "/")
                .map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }
                .joined(separator: "/")
            let url = URL(string: "https://huggingface.co/\(repo)/resolve/main/\(encodedPath)")!
            let base = doneBytes
            let name = file.path
            try await FileDownload.run(from: url, to: target) { written in
                let fraction = Double(base + written) / Double(totalBytes)
                progress(min(1, fraction), "Lade \(name) …")
            }
            doneBytes += file.byteSize
        }

        FileManager.default.createFile(
            atPath: destination.appendingPathComponent(completeMarker).path, contents: Data())
        progress(1, "Fertig")
        return destination
    }
}

/// Einzelner Datei-Download mit Fortschritt (URLSessionDownloadDelegate).
final class FileDownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let target: URL
    private let onProgress: @Sendable (Int64) -> Void
    private var continuation: CheckedContinuation<Void, Error>?
    private var moveError: Error?

    private init(target: URL, onProgress: @escaping @Sendable (Int64) -> Void) {
        self.target = target
        self.onProgress = onProgress
    }

    static func run(from url: URL, to target: URL, onProgress: @escaping @Sendable (Int64) -> Void) async throws {
        let delegate = FileDownload(target: target, onProgress: onProgress)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let task = session.downloadTask(with: url)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                delegate.continuation = cont
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        onProgress(totalBytesWritten)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            moveError = HFDownloader.DownloadError.badResponse("HTTP \(http.statusCode) für \(target.lastPathComponent)")
            return
        }
        do {
            if FileManager.default.fileExists(atPath: target.path) {
                try FileManager.default.removeItem(at: target)
            }
            try FileManager.default.moveItem(at: location, to: target)
        } catch {
            moveError = error
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error ?? moveError {
            continuation?.resume(throwing: error)
        } else {
            continuation?.resume()
        }
        continuation = nil
    }
}
