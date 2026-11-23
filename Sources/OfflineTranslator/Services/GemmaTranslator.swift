import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import Tokenizers

/// Übersetzung mit Google TranslateGemma (Gemma-3-basiert, auf Übersetzung spezialisiert),
/// lokal ausgeführt über MLX auf der Apple-Silicon-GPU.
final class GemmaTranslator: @unchecked Sendable {
    private var container: ModelContainer?
    private(set) var loadedRepo: String?

    var isLoaded: Bool { container != nil }

    func isDownloaded(_ repo: String) -> Bool {
        HFDownloader.isComplete(AppPaths.llmFolder(for: repo))
    }

    func download(_ repo: String, progress: @escaping @Sendable (Double, String) -> Void) async throws {
        _ = try await HFDownloader.downloadRepo(repo, to: AppPaths.llmFolder(for: repo), progress: progress)
    }

    func delete(_ repo: String) throws {
        if loadedRepo == repo { unload() }
        let folder = AppPaths.llmFolder(for: repo)
        if FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.removeItem(at: folder)
        }
    }

    func unload() {
        container = nil
        loadedRepo = nil
        MLX.Memory.clearCache()
    }

    /// Lädt (und ggf. lädt herunter) das Modell.
    func load(_ repo: String, progress: @escaping @Sendable (Double, String) -> Void) async throws {
        if loadedRepo == repo, container != nil { return }
        unload()
        if !isDownloaded(repo) {
            try await download(repo, progress: progress)
        }
        progress(1, "Lade Modell in den GPU-Speicher …")
        let folder = AppPaths.llmFolder(for: repo)
        let loaded = try await LLMModelFactory.shared.loadContainer(
            from: folder, using: TransformersTokenizerLoader())
        container = loaded
        loadedRepo = repo
    }

    /// Übersetzt `text`. Lange Texte werden absatzweise übersetzt und gestreamt.
    func translate(
        _ text: String,
        from source: AppLanguage,
        to target: AppLanguage,
        onPartial: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        guard let container else { throw TranslatorError.notLoaded }
        let chunks = Self.chunk(text)
        var output = ""

        for chunk in chunks {
            try Task.checkCancellation()
            if chunk.isSeparator {
                output += chunk.text
                onPartial(output)
                continue
            }
            let prefix = output
            let translated: String = try await container.perform { context in
                let tokens = try Self.promptTokens(
                    tokenizer: context.tokenizer, text: chunk.text, source: source, target: target)
                let input = LMInput(tokens: MLXArray(tokens))
                let parameters = GenerateParameters(
                    maxTokens: max(256, tokens.count * 3),
                    temperature: 0.0,
                    repetitionPenalty: 1.05
                )
                var result = ""
                let stream = try MLXLMCommon.generate(input: input, parameters: parameters, context: context)
                for await item in stream {
                    if Task.isCancelled { break }
                    if case .chunk(let piece) = item {
                        result += piece
                        if let range = result.range(of: "<end_of_turn>") {
                            result = String(result[..<range.lowerBound])
                            break
                        }
                        onPartial(prefix + Self.clean(result))
                    }
                }
                return Self.clean(result)
            }
            output += translated
            onPartial(output)
        }
        return output
    }

    // MARK: - Prompt

    /// Bevorzugt das Chat-Template des Modells (TranslateGemma-Format mit Sprachcodes),
    /// fällt sonst auf das dokumentierte Prompt-Format zurück.
    static func promptTokens(
        tokenizer: any MLXLMCommon.Tokenizer, text: String,
        source: AppLanguage, target: AppLanguage
    ) throws -> [Int] {
        let content: [any Sendable] = [
            [
                "type": "text",
                "source_lang_code": source.rawValue,
                "target_lang_code": target.rawValue,
                "text": text,
            ] as [String: any Sendable]
        ]
        let messages: [[String: any Sendable]] = [["role": "user", "content": content]]

        if var tokens = try? tokenizer.applyChatTemplate(messages: messages, tools: nil, additionalContext: nil),
           !tokens.isEmpty {
            let decoded = tokenizer.decode(tokenIds: tokens, skipSpecialTokens: false)
            // Template muss den Text enthalten, sonst Fallback
            if decoded.contains(String(text.prefix(40))) {
                if !decoded.hasSuffix("<start_of_turn>model\n") {
                    tokens += tokenizer.encode(text: "<start_of_turn>model\n", addSpecialTokens: false)
                }
                return tokens
            }
        }
        return tokenizer.encode(text: manualPrompt(text: text, source: source, target: target), addSpecialTokens: true)
    }

    static func manualPrompt(text: String, source: AppLanguage, target: AppLanguage) -> String {
        let s = source.englishName, sc = source.rawValue
        let t = target.englishName, tc = target.rawValue
        return "<start_of_turn>user\n"
            + "You are a professional \(s) (\(sc)) to \(t) (\(tc)) translator. "
            + "Your goal is to accurately convey the meaning and nuances of the original \(s) text "
            + "while adhering to \(t) grammar, vocabulary, and cultural sensitivities.\n"
            + "Produce only the \(t) translation, without any additional explanations or commentary. "
            + "Please translate the following \(s) text into \(t):\n\n\n"
            + text
            + "<end_of_turn>\n<start_of_turn>model\n"
    }

    static func clean(_ s: String) -> String {
        var r = s.replacingOccurrences(of: "<end_of_turn>", with: "")
            .replacingOccurrences(of: "<eos>", with: "")
        while r.hasPrefix("\n") { r.removeFirst() }
        while r.hasSuffix("\n") || r.hasSuffix(" ") { r.removeLast() }
        return r
    }

    // MARK: - Chunking

    struct Chunk { var text: String; var isSeparator: Bool }

    /// Zerlegt Text in übersetzbare Blöcke (max. ~1500 Zeichen) und exakte Trenner,
    /// damit Zeilenumbrüche und Absätze im Ergebnis erhalten bleiben.
    static func chunk(_ text: String, maxChars: Int = 1500) -> [Chunk] {
        var chunks: [Chunk] = []
        var block: [String] = []
        var blockLength = 0

        func flushBlock() {
            guard !block.isEmpty else { return }
            chunks.append(Chunk(text: block.joined(separator: "\n"), isSeparator: false))
            block = []
            blockLength = 0
        }
        func appendSeparator(_ sep: String) {
            if let last = chunks.last, last.isSeparator {
                chunks[chunks.count - 1].text += sep
            } else {
                chunks.append(Chunk(text: sep, isSeparator: true))
            }
        }

        let lines = text.components(separatedBy: "\n")
        for (i, line) in lines.enumerated() {
            if i > 0 {
                // Zeilenumbruch: innerhalb eines Blocks bleibt er Teil des Blocks,
                // an Blockgrenzen wird er zum Trenner.
                if line.trimmingCharacters(in: .whitespaces).isEmpty || block.isEmpty
                    || blockLength + line.count > maxChars {
                    flushBlock()
                    appendSeparator("\n")
                }
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            if line.count > maxChars {
                // Sehr lange Zeile an Satzgrenzen teilen
                flushBlock()
                var buffer = ""
                line.enumerateSubstrings(in: line.startIndex..., options: .bySentences) { sub, _, _, _ in
                    guard let sub else { return }
                    if buffer.count + sub.count > maxChars, !buffer.isEmpty {
                        chunks.append(Chunk(text: buffer, isSeparator: false))
                        appendSeparator(" ")
                        buffer = ""
                    }
                    buffer += sub
                }
                if !buffer.isEmpty { chunks.append(Chunk(text: buffer, isSeparator: false)) }
                continue
            }
            block.append(line)
            blockLength += line.count + 1
        }
        flushBlock()
        return chunks
    }

    enum TranslatorError: LocalizedError {
        case notLoaded
        var errorDescription: String? { "Das Übersetzungsmodell ist noch nicht geladen." }
    }
}

// MARK: - Tokenizer-Brücke swift-transformers → MLXLMCommon

struct TransformersTokenizerLoader: MLXLMCommon.TokenizerLoader {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        let upstream = try await Tokenizers.AutoTokenizer.from(modelFolder: directory)
        return TokenizerBridge(upstream)
    }
}

struct TokenizerBridge: MLXLMCommon.Tokenizer, @unchecked Sendable {
    private let upstream: any Tokenizers.Tokenizer

    init(_ upstream: any Tokenizers.Tokenizer) { self.upstream = upstream }

    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
    }

    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
    }

    func convertTokenToId(_ token: String) -> Int? { upstream.convertTokenToId(token) }
    func convertIdToToken(_ id: Int) -> String? { upstream.convertIdToToken(id) }

    var bosToken: String? { upstream.bosToken }
    var eosToken: String? { upstream.eosToken }
    var unknownToken: String? { upstream.unknownToken }

    func applyChatTemplate(
        messages: [[String: any Sendable]],
        tools: [[String: any Sendable]]?,
        additionalContext: [String: any Sendable]?
    ) throws -> [Int] {
        do {
            return try upstream.applyChatTemplate(
                messages: messages, tools: tools, additionalContext: additionalContext)
        } catch Tokenizers.TokenizerError.missingChatTemplate {
            throw MLXLMCommon.TokenizerError.missingChatTemplate
        }
    }
}
