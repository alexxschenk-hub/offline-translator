import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Zentraler Zustand der App (Modelle, Fortschritt, Einstellungen).
@MainActor
final class AppState: ObservableObject {
    let translator = GemmaTranslator()
    let transcriber = TranscriptionService()

    // MARK: Einstellungen (persistiert)
    @AppStorage("translationEngine") var translationEngine: TranslationEngine = .translateGemma
    @AppStorage("gemmaRepo") var gemmaRepo: String = GemmaModel.recommended.repo
    @AppStorage("asrEngine") var asrEngine: ASREngine = .whisperLargeV3
    @AppStorage("computeChoice") var computeChoice: ComputeChoice = .gpu
    @AppStorage("spokenLanguage") var spokenLanguage: SpokenLanguage = .auto
    @AppStorage("outputFormat") var outputFormat: OutputFormat = .txt

    // MARK: Übersetzung
    @Published var sourceText: String = ""
    @Published var translatedText: String = ""
    @Published var direction = TranslationDirection(source: .english)
    @Published var isTranslating = false
    @Published var translationStatus: String = ""
    private var translationTask: Task<Void, Never>?

    // MARK: Transkription
    @Published var inputPath: String = ""
    @Published var outputPath: String = ""
    @Published var isTranscribing = false
    @Published var transcriptionProgress: Double = 0
    @Published var transcriptionStatus: String = ""
    @Published var transcriptPreview: String = ""
    private var transcriptionTask: Task<Void, Never>?

    // MARK: Modell-Downloads
    @Published var downloads: [String: Double] = [:]
    @Published var downloadStatus: [String: String] = [:]
    @Published var errorMessage: String?
    @Published var refreshToken = UUID()

    // MARK: - Übersetzen

    func translate(appleHandler: (() -> Void)? = nil) {
        let text = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        if translationEngine == .apple {
            appleHandler?()
            return
        }

        translationTask?.cancel()
        isTranslating = true
        translatedText = ""
        let repo = gemmaRepo
        let direction = self.direction
        let source = sourceText

        translationTask = Task { [weak self] in
            guard let self else { return }
            do {
                if self.translator.loadedRepo != repo {
                    self.translationStatus = "Lade TranslateGemma …"
                    try await self.translator.load(repo) { fraction, message in
                        Task { @MainActor in
                            self.downloads[repo] = fraction
                            self.translationStatus = "\(message) \(Int(fraction * 100)) %"
                        }
                    }
                    self.downloads[repo] = nil
                    self.refreshToken = UUID()
                }
                self.translationStatus = "Übersetze …"
                let started = Date()
                let result = try await self.translator.translate(
                    source, from: direction.source, to: direction.target
                ) { partial in
                    Task { @MainActor in
                        if self.isTranslating { self.translatedText = partial }
                    }
                }
                self.translatedText = result
                self.translationStatus = String(format: "Fertig in %.1f s", Date().timeIntervalSince(started))
            } catch is CancellationError {
                self.translationStatus = "Abgebrochen"
            } catch {
                self.translationStatus = ""
                self.errorMessage = error.localizedDescription
            }
            self.downloads[repo] = nil
            self.isTranslating = false
        }
    }

    func cancelTranslation() {
        translationTask?.cancel()
        isTranslating = false
        translationStatus = "Abgebrochen"
    }

    func swapDirection() {
        direction.swap()
        if !translatedText.isEmpty {
            let old = sourceText
            sourceText = translatedText
            translatedText = old
        }
    }

    // MARK: - Transkribieren

    func chooseInput() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.mp3, .mpeg4Audio, .wav, .aiff, .audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Audiodatei (mp3, m4a, …) auswählen"
        if panel.runModal() == .OK, let url = panel.url {
            setInput(url)
        }
    }

    func setInput(_ url: URL) {
        inputPath = url.path
        // Ausgabepfad automatisch vorschlagen
        if outputPath.isEmpty || outputPathWasSuggested {
            outputPath = url.deletingPathExtension().appendingPathExtension(outputFormat.rawValue).path
            outputPathWasSuggested = true
        }
    }

    private var outputPathWasSuggested = false

    func chooseOutput() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: outputFormat.rawValue) ?? .plainText]
        panel.canCreateDirectories = true
        let input = URL(fileURLWithPath: inputPath)
        panel.nameFieldStringValue = inputPath.isEmpty
            ? "Transkript.\(outputFormat.rawValue)"
            : input.deletingPathExtension().lastPathComponent + ".\(outputFormat.rawValue)"
        if !inputPath.isEmpty { panel.directoryURL = input.deletingLastPathComponent() }
        if panel.runModal() == .OK, let url = panel.url {
            outputPath = url.path
            outputPathWasSuggested = false
        }
    }

    /// Passt die Dateiendung des Ausgabepfads an das gewählte Format an.
    func outputFormatChanged() {
        guard !outputPath.isEmpty else { return }
        let url = URL(fileURLWithPath: (outputPath as NSString).expandingTildeInPath)
        outputPath = url.deletingPathExtension().appendingPathExtension(outputFormat.rawValue).path
    }

    func startTranscription() {
        let inputURL = URL(fileURLWithPath: (inputPath as NSString).expandingTildeInPath)
        guard FileManager.default.fileExists(atPath: inputURL.path) else {
            errorMessage = "Die Audiodatei wurde nicht gefunden:\n\(inputURL.path)"
            return
        }
        var outputURL = URL(fileURLWithPath: (outputPath as NSString).expandingTildeInPath)
        if outputPath.isEmpty {
            outputURL = inputURL.deletingPathExtension().appendingPathExtension(outputFormat.rawValue)
            outputPath = outputURL.path
        }
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: outputURL.path, isDirectory: &isDir), isDir.boolValue {
            outputURL = outputURL.appendingPathComponent(
                inputURL.deletingPathExtension().lastPathComponent + "." + outputFormat.rawValue)
            outputPath = outputURL.path
        }

        transcriptionTask?.cancel()
        isTranscribing = true
        transcriptionProgress = 0
        transcriptPreview = ""
        let engine = asrEngine, language = spokenLanguage, compute = computeChoice, format = outputFormat

        transcriptionTask = Task { [weak self] in
            guard let self else { return }
            do {
                let transcript = try await self.transcriber.transcribe(
                    file: inputURL, engine: engine, language: language, compute: compute
                ) { fraction, message in
                    Task { @MainActor in
                        self.transcriptionProgress = fraction
                        self.transcriptionStatus = message
                    }
                }
                let rendered = TranscriptWriter.render(transcript, as: format)
                try FileManager.default.createDirectory(
                    at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try rendered.write(to: outputURL, atomically: true, encoding: .utf8)

                self.transcriptPreview = TranscriptWriter.paragraphs(transcript)
                self.transcriptionProgress = 1
                let speed = transcript.processingTime > 0 ? transcript.audioDuration / transcript.processingTime : 0
                var status = String(format: "Fertig: %@ Audio in %.0f s (%.0f× Echtzeit) → %@",
                                    TranscriptWriter.shortTimestamp(transcript.audioDuration),
                                    transcript.processingTime, speed, outputURL.lastPathComponent)
                if let lang = transcript.detectedLanguage, language == .auto, engine.isWhisper {
                    status += " · erkannte Sprache: \(lang)"
                }
                self.transcriptionStatus = status
                self.refreshToken = UUID()
            } catch is CancellationError {
                self.transcriptionStatus = "Abgebrochen"
            } catch {
                if Task.isCancelled {
                    self.transcriptionStatus = "Abgebrochen"
                } else {
                    self.transcriptionStatus = "Fehler"
                    self.errorMessage = error.localizedDescription
                }
            }
            self.isTranscribing = false
        }
    }

    func cancelTranscription() {
        transcriptionTask?.cancel()
    }

    func revealOutput() {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: outputPath)])
    }

    /// Übernimmt das Transkript in den Übersetzer.
    func sendTranscriptToTranslator() {
        sourceText = transcriptPreview
        translatedText = ""
        if let code = spokenLanguage.code, let lang = AppLanguage(rawValue: code) {
            direction = TranslationDirection(source: lang)
        }
    }

    // MARK: - Modellverwaltung

    func download(asr engine: ASREngine) {
        let key = engine.rawValue
        downloads[key] = 0
        Task {
            do {
                try await transcriber.download(engine) { fraction, message in
                    Task { @MainActor in
                        self.downloads[key] = fraction
                        self.downloadStatus[key] = message
                    }
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            downloads[key] = nil
            downloadStatus[key] = nil
            refreshToken = UUID()
        }
    }

    func download(gemma repo: String) {
        downloads[repo] = 0
        Task {
            do {
                try await translator.download(repo) { fraction, message in
                    Task { @MainActor in
                        self.downloads[repo] = fraction
                        self.downloadStatus[repo] = message
                    }
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            downloads[repo] = nil
            downloadStatus[repo] = nil
            refreshToken = UUID()
        }
    }

    func delete(asr engine: ASREngine) {
        do { try transcriber.delete(engine) } catch { errorMessage = error.localizedDescription }
        refreshToken = UUID()
    }

    func delete(gemma repo: String) {
        do { try translator.delete(repo) } catch { errorMessage = error.localizedDescription }
        refreshToken = UUID()
    }
}
