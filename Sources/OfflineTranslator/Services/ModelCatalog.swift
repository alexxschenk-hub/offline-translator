import Foundation

// MARK: - Transkription

enum ASREngine: String, CaseIterable, Identifiable, Codable {
    case whisperLargeV3
    case whisperLargeV3Turbo
    case parakeetUltra
    case parakeetV3

    var id: String { rawValue }

    var title: String {
        switch self {
        case .whisperLargeV3: return "Whisper large-v3 (beste Qualität)"
        case .whisperLargeV3Turbo: return "Whisper large-v3 Turbo (schneller)"
        case .parakeetUltra: return "Parakeet TDT Ultra (sehr schnell, sehr genau)"
        case .parakeetV3: return "Parakeet TDT v3 (sehr schnell)"
        }
    }

    var detail: String {
        switch self {
        case .whisperLargeV3:
            return "OpenAI Whisper large-v3 (1,55 Mrd. Parameter) als CoreML-Modell von Argmax. Höchste Robustheit bei Akzenten, Hintergrundgeräuschen und Fachbegriffen. Zeichensetzung & Zeitstempel. ≈ 3 GB."
        case .whisperLargeV3Turbo:
            return "Whisper large-v3 Turbo (v20240930): Decoder auf 4 Schichten reduziert, ~5× schneller bei fast gleicher Genauigkeit. ≈ 1,6 GB."
        case .parakeetUltra:
            return "NVIDIA Parakeet TDT 0.6B – Ultra-Nachtraining (moondream) via FluidAudio. Genauer als v3 auf allen Benchmarks, 25 europäische Sprachen, extrem schnell auf der Neural Engine. ≈ 0,6 GB."
        case .parakeetV3:
            return "NVIDIA Parakeet TDT 0.6B v3 via FluidAudio. 25 europäische Sprachen, extrem schnell. ≈ 0,6 GB."
        }
    }

    var whisperVariant: String? {
        switch self {
        case .whisperLargeV3: return "openai_whisper-large-v3"
        case .whisperLargeV3Turbo: return "openai_whisper-large-v3-v20240930"
        default: return nil
        }
    }

    var isWhisper: Bool { whisperVariant != nil }
}

enum ComputeChoice: String, CaseIterable, Identifiable, Codable {
    case gpu
    case neuralEngine
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gpu: return "GPU (Metal)"
        case .neuralEngine: return "Neural Engine"
        case .all: return "Automatisch (CoreML wählt)"
        }
    }
}

enum SpokenLanguage: String, CaseIterable, Identifiable, Codable {
    case auto, german = "de", english = "en"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: return "Automatisch erkennen"
        case .german: return "🇩🇪 Deutsch"
        case .english: return "🇬🇧 Englisch"
        }
    }

    var code: String? { self == .auto ? nil : rawValue }
}

// MARK: - Übersetzung

enum TranslationEngine: String, CaseIterable, Identifiable, Codable {
    case translateGemma
    case apple

    var id: String { rawValue }

    var title: String {
        switch self {
        case .translateGemma: return "TranslateGemma (beste Qualität, GPU)"
        case .apple: return "Apple Übersetzen (systemeigen)"
        }
    }
}

struct GemmaModel: Identifiable, Hashable {
    let repo: String
    let title: String
    let approxSize: String
    let minRAMGB: Double

    var id: String { repo }

    static let all: [GemmaModel] = [
        GemmaModel(repo: "mlx-community/translategemma-27b-it-4bit",
                   title: "TranslateGemma 27B · 4-bit (höchste Qualität)", approxSize: "≈ 16 GB", minRAMGB: 32),
        GemmaModel(repo: "mlx-community/translategemma-12b-it-8bit",
                   title: "TranslateGemma 12B · 8-bit", approxSize: "≈ 12,5 GB", minRAMGB: 24),
        GemmaModel(repo: "mlx-community/translategemma-12b-it-4bit",
                   title: "TranslateGemma 12B · 4-bit (empfohlen)", approxSize: "≈ 6,7 GB", minRAMGB: 16),
        GemmaModel(repo: "mlx-community/translategemma-4b-it-4bit",
                   title: "TranslateGemma 4B · 4-bit (klein & schnell)", approxSize: "≈ 2,5 GB", minRAMGB: 8),
    ]

    /// Größtes Modell, das bequem in den Arbeitsspeicher passt.
    static var recommended: GemmaModel {
        let ram = SystemInfo.physicalMemoryGB
        if ram >= 48 { return all[0] }
        if ram >= 16 { return all[2] }
        return all[3]
    }
}
