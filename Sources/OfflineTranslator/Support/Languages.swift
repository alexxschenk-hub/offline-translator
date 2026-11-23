import Foundation

/// Unterstützte Sprachen der App.
enum AppLanguage: String, CaseIterable, Identifiable, Codable {
    case english = "en"
    case german = "de"

    var id: String { rawValue }

    /// Name auf Englisch (wird im TranslateGemma-Prompt verwendet)
    var englishName: String {
        switch self {
        case .english: return "English"
        case .german: return "German"
        }
    }

    var displayName: String {
        switch self {
        case .english: return "Englisch"
        case .german: return "Deutsch"
        }
    }

    var flag: String {
        switch self {
        case .english: return "🇬🇧"
        case .german: return "🇩🇪"
        }
    }

    var other: AppLanguage { self == .english ? .german : .english }

    var localeLanguage: Locale.Language { Locale.Language(identifier: rawValue) }
}

/// Übersetzungsrichtung
struct TranslationDirection: Equatable {
    var source: AppLanguage
    var target: AppLanguage { source.other }

    mutating func swap() { source = source.other }

    var label: String { "\(source.flag) \(source.displayName) → \(target.flag) \(target.displayName)" }
}
