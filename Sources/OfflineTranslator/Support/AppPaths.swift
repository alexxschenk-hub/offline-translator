import Foundation

/// Speicherorte aller lokal gespeicherten Modelle.
/// Standard: ~/Library/Application Support/OfflineTranslator
enum AppPaths {
    static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return ensure(base.appendingPathComponent("OfflineTranslator", isDirectory: true))
    }

    static var whisper: URL { ensure(root.appendingPathComponent("whisper", isDirectory: true)) }
    static var parakeet: URL { ensure(root.appendingPathComponent("parakeet", isDirectory: true)) }
    static var llm: URL { ensure(root.appendingPathComponent("llm", isDirectory: true)) }

    static func llmFolder(for repo: String) -> URL {
        llm.appendingPathComponent(repo.replacingOccurrences(of: "/", with: "__"), isDirectory: true)
    }

    static func parakeetFolder(for name: String) -> URL {
        parakeet.appendingPathComponent(name, isDirectory: true)
    }

    @discardableResult
    static func ensure(_ url: URL) -> URL {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func folderSize(_ url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileSizeKey]
        ) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            let values = try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey])
            total += Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
        }
        return total
    }
}

extension Int64 {
    var byteString: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}

enum SystemInfo {
    static var physicalMemoryGB: Double {
        Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
    }
}
