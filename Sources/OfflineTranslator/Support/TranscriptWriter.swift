import Foundation

/// Ein Abschnitt des Transkripts mit Zeitstempeln (Sekunden).
struct TranscriptSegment: Sendable, Equatable {
    var start: Double
    var end: Double
    var text: String
}

struct Transcript: Sendable {
    var segments: [TranscriptSegment]
    var plainText: String
    var detectedLanguage: String?
    var audioDuration: Double
    var processingTime: Double
}

enum OutputFormat: String, CaseIterable, Identifiable {
    case txt, srt, vtt, md

    var id: String { rawValue }

    var title: String {
        switch self {
        case .txt: return "Text (.txt)"
        case .srt: return "Untertitel (.srt)"
        case .vtt: return "WebVTT (.vtt)"
        case .md: return "Text mit Zeitmarken (.md)"
        }
    }
}

enum TranscriptWriter {
    static func render(_ transcript: Transcript, as format: OutputFormat) -> String {
        switch format {
        case .txt:
            return paragraphs(transcript) + "\n"
        case .srt:
            return transcript.segments.enumerated().map { index, seg in
                "\(index + 1)\n\(timestamp(seg.start, separator: ",")) --> \(timestamp(seg.end, separator: ","))\n\(seg.text)\n"
            }.joined(separator: "\n")
        case .vtt:
            let body = transcript.segments.map { seg in
                "\(timestamp(seg.start, separator: ".")) --> \(timestamp(seg.end, separator: "."))\n\(seg.text)\n"
            }.joined(separator: "\n")
            return "WEBVTT\n\n" + body
        case .md:
            return transcript.segments.map { seg in
                "**[\(shortTimestamp(seg.start))]** \(seg.text)"
            }.joined(separator: "\n\n") + "\n"
        }
    }

    /// Fließtext; neuer Absatz bei längeren Sprechpausen.
    static func paragraphs(_ transcript: Transcript, pause: Double = 1.6) -> String {
        guard !transcript.segments.isEmpty else { return transcript.plainText }
        var result = ""
        var previousEnd: Double?
        for seg in transcript.segments {
            let text = seg.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            if let prev = previousEnd {
                result += (seg.start - prev > pause) ? "\n\n" : " "
            }
            result += text
            previousEnd = seg.end
        }
        return result
    }

    static func timestamp(_ seconds: Double, separator: String) -> String {
        let totalMs = Int((max(0, seconds) * 1000).rounded())
        let h = totalMs / 3_600_000
        let m = (totalMs % 3_600_000) / 60_000
        let s = (totalMs % 60_000) / 1000
        let ms = totalMs % 1000
        return String(format: "%02d:%02d:%02d\(separator)%03d", h, m, s, ms)
    }

    static func shortTimestamp(_ seconds: Double) -> String {
        let total = Int(max(0, seconds))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }

    /// Teilt lange Segmente (z. B. > 7 s) nicht weiter – nur Bereinigung.
    static func cleaned(_ segments: [TranscriptSegment]) -> [TranscriptSegment] {
        segments.compactMap { seg in
            let text = seg.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : TranscriptSegment(start: seg.start, end: max(seg.end, seg.start), text: text)
        }
    }
}
