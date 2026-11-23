import AVFoundation
import CoreML
import FluidAudio
import Foundation
import WhisperKit

/// Transkription von Audiodateien (mp3, m4a, wav, …) – vollständig lokal.
/// Whisper läuft über WhisperKit (CoreML), Parakeet über FluidAudio (CoreML).
final class TranscriptionService: @unchecked Sendable {
    private var whisper: WhisperKit?
    private var whisperKey: String?

    private var parakeet: AsrManager?
    private var parakeetKey: String?

    // MARK: - Status

    private static let whisperFolderKey = "whisperFolder."

    func whisperFolder(for variant: String) -> URL? {
        guard let path = UserDefaults.standard.string(forKey: Self.whisperFolderKey + variant) else { return nil }
        let url = URL(fileURLWithPath: path)
        let encoder = url.appendingPathComponent("AudioEncoder.mlmodelc")
        return FileManager.default.fileExists(atPath: encoder.path) ? url : nil
    }

    func isDownloaded(_ engine: ASREngine) -> Bool {
        if let variant = engine.whisperVariant { return whisperFolder(for: variant) != nil }
        let version = Self.parakeetVersion(engine)
        return AsrModels.modelsExist(at: AppPaths.parakeetFolder(for: engine.rawValue), version: version)
    }

    func folder(for engine: ASREngine) -> URL? {
        if let variant = engine.whisperVariant { return whisperFolder(for: variant) }
        let url = AppPaths.parakeetFolder(for: engine.rawValue)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func delete(_ engine: ASREngine) throws {
        if let variant = engine.whisperVariant {
            if whisperKey?.hasPrefix(variant) == true { whisper = nil; whisperKey = nil }
            if let folder = whisperFolder(for: variant) { try FileManager.default.removeItem(at: folder) }
            UserDefaults.standard.removeObject(forKey: Self.whisperFolderKey + variant)
        } else {
            if parakeetKey?.hasPrefix(engine.rawValue) == true { parakeet = nil; parakeetKey = nil }
            let folder = AppPaths.parakeetFolder(for: engine.rawValue)
            if FileManager.default.fileExists(atPath: folder.path) { try FileManager.default.removeItem(at: folder) }
        }
    }

    static func parakeetVersion(_ engine: ASREngine) -> AsrModelVersion {
        engine == .parakeetUltra ? .ultra : .v3
    }

    // MARK: - Download

    func download(_ engine: ASREngine, progress: @escaping @Sendable (Double, String) -> Void) async throws {
        if let variant = engine.whisperVariant {
            _ = try await downloadWhisper(variant, progress: progress)
        } else {
            progress(0, "Lade Parakeet-Modell …")
            _ = try await AsrModels.downloadAndLoad(
                to: AppPaths.parakeetFolder(for: engine.rawValue),
                version: Self.parakeetVersion(engine))
            progress(1, "Fertig")
        }
    }

    private func downloadWhisper(_ variant: String, progress: @escaping @Sendable (Double, String) -> Void) async throws -> URL {
        if let folder = whisperFolder(for: variant) { return folder }
        let folder = try await WhisperKit.download(
            variant: variant,
            downloadBase: AppPaths.whisper,
            progressCallback: { p in
                progress(p.fractionCompleted, "Lade Whisper-Modell …")
            })
        UserDefaults.standard.set(folder.path, forKey: Self.whisperFolderKey + variant)
        return folder
    }

    // MARK: - Laden

    private static func units(_ choice: ComputeChoice) -> MLComputeUnits {
        switch choice {
        case .gpu: return .cpuAndGPU
        case .neuralEngine: return .cpuAndNeuralEngine
        case .all: return .all
        }
    }

    private func loadWhisper(_ variant: String, compute: ComputeChoice,
                             progress: @escaping @Sendable (Double, String) -> Void) async throws -> WhisperKit {
        let key = "\(variant)|\(compute.rawValue)"
        if let whisper, whisperKey == key { return whisper }
        whisper = nil
        let folder = try await downloadWhisper(variant, progress: progress)
        progress(1, "Lade & kompiliere Whisper (beim ersten Mal einige Minuten) …")
        let units = Self.units(compute)
        let config = WhisperKitConfig(
            model: variant,
            downloadBase: AppPaths.whisper,
            modelFolder: folder.path,
            tokenizerFolder: AppPaths.whisper,
            computeOptions: ModelComputeOptions(
                melCompute: .cpuAndGPU,
                audioEncoderCompute: units,
                textDecoderCompute: units),
            verbose: false,
            logLevel: .error,
            prewarm: true,
            load: true,
            download: false)
        let kit = try await WhisperKit(config)
        whisper = kit
        whisperKey = key
        return kit
    }

    private func loadParakeet(_ engine: ASREngine, compute: ComputeChoice,
                              progress: @escaping @Sendable (Double, String) -> Void) async throws -> AsrManager {
        let key = "\(engine.rawValue)|\(compute.rawValue)"
        if let parakeet, parakeetKey == key { return parakeet }
        parakeet = nil
        progress(0, isDownloaded(engine) ? "Lade Parakeet-Modell …" : "Lade Parakeet-Modell herunter …")
        let configuration = MLModelConfiguration()
        configuration.computeUnits = Self.units(compute)
        let models: AsrModels
        do {
            models = try await AsrModels.downloadAndLoad(
                to: AppPaths.parakeetFolder(for: engine.rawValue),
                configuration: configuration,
                version: Self.parakeetVersion(engine))
        } catch {
            // Falls die gewählte Recheneinheit nicht unterstützt wird: Standard verwenden
            models = try await AsrModels.downloadAndLoad(
                to: AppPaths.parakeetFolder(for: engine.rawValue),
                version: Self.parakeetVersion(engine))
        }
        let manager = AsrManager(config: .default)
        try await manager.loadModels(models)
        parakeet = manager
        parakeetKey = key
        return manager
    }

    // MARK: - Transkription

    func transcribe(
        file: URL,
        engine: ASREngine,
        language: SpokenLanguage,
        compute: ComputeChoice,
        progress: @escaping @Sendable (Double, String) -> Void
    ) async throws -> Transcript {
        let duration = Self.audioDuration(file)
        let started = Date()

        if let variant = engine.whisperVariant {
            let kit = try await loadWhisper(variant, compute: compute, progress: progress)
            progress(0, "Transkribiere mit Whisper …")

            let options = DecodingOptions(
                verbose: false,
                task: .transcribe,
                language: language.code,
                temperature: 0.0,
                temperatureFallbackCount: 5,
                usePrefillPrompt: true,
                detectLanguage: language == .auto,
                skipSpecialTokens: true,
                withoutTimestamps: false,
                wordTimestamps: false,
                concurrentWorkerCount: 4,
                chunkingStrategy: .vad)

            // Fortschritt beobachten
            let poller = Task {
                while !Task.isCancelled {
                    let fraction = kit.progress.fractionCompleted
                    progress(min(0.99, fraction), "Transkribiere mit Whisper … \(Int(fraction * 100)) %")
                    try? await Task.sleep(nanoseconds: 400_000_000)
                }
            }
            defer { poller.cancel() }

            let results = try await kit.transcribe(
                audioPath: file.path,
                decodeOptions: options,
                callback: { _ in Task.isCancelled ? false : nil })
            try Task.checkCancellation()

            let segments = TranscriptWriter.cleaned(
                results.flatMap { $0.segments }
                    .sorted { $0.start < $1.start }
                    .map { TranscriptSegment(start: Double($0.start), end: Double($0.end),
                                             text: Self.stripWhisperTokens($0.text)) })
            let text = segments.map(\.text).joined(separator: " ")
            return Transcript(
                segments: segments, plainText: text,
                detectedLanguage: results.first?.language,
                audioDuration: duration,
                processingTime: Date().timeIntervalSince(started))
        } else {
            let manager = try await loadParakeet(engine, compute: compute, progress: progress)
            progress(0, "Transkribiere mit Parakeet …")
            var state = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
            let hint: Language? = {
                switch language {
                case .german: return .german
                case .english: return .english
                case .auto: return nil
                }
            }()
            let result = try await manager.transcribe(file, decoderState: &state, language: hint)
            try Task.checkCancellation()
            let segments = Self.segments(from: result.tokenTimings ?? [])
            return Transcript(
                segments: segments.isEmpty
                    ? [TranscriptSegment(start: 0, end: duration, text: result.text)] : segments,
                plainText: result.text,
                detectedLanguage: language.code,
                audioDuration: duration,
                processingTime: Date().timeIntervalSince(started))
        }
    }

    // MARK: - Hilfsfunktionen

    static func audioDuration(_ url: URL) -> Double {
        guard let file = try? AVAudioFile(forReading: url) else { return 0 }
        return Double(file.length) / file.processingFormat.sampleRate
    }

    /// Entfernt eventuell verbliebene Whisper-Steuertokens wie <|0.00|> oder <|de|>.
    static func stripWhisperTokens(_ text: String) -> String {
        text.replacingOccurrences(of: "<\\|[^|]*\\|>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Baut aus Parakeet-Token-Zeitstempeln satzweise Untertitel-Segmente.
    static func segments(from timings: [TokenTiming], maxDuration: Double = 7.0) -> [TranscriptSegment] {
        var segments: [TranscriptSegment] = []
        var text = ""
        var start: Double?
        var end: Double = 0

        func flush() {
            let t = text.trimmingCharacters(in: .whitespaces)
            if let s = start, !t.isEmpty { segments.append(TranscriptSegment(start: s, end: end, text: t)) }
            text = ""; start = nil
        }

        for token in timings {
            let piece = token.token.replacingOccurrences(of: "▁", with: " ")
            if piece.isEmpty || piece.hasPrefix("<") { continue }
            let startsWord = piece.hasPrefix(" ")
            if let s = start, startsWord, token.endTime - s > maxDuration { flush() }
            if start == nil { start = token.startTime }
            text += piece
            end = token.endTime
            let trimmed = piece.trimmingCharacters(in: .whitespaces)
            if let last = trimmed.last, ".?!".contains(last), let s = start, end - s > 1.2 { flush() }
        }
        flush()
        return segments
    }
}
