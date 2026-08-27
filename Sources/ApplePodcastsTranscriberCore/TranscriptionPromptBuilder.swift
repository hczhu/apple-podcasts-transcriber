import Foundation

/// Builds a Whisper initial prompt from episode show notes.
///
/// Whisper has no system prompt. It accepts an *initial prompt*, which is fed to
/// the decoder as if it were previously transcribed text, biasing spelling and
/// vocabulary toward the names and jargon it contains. The decoder reserves
/// `n_text_ctx / 2` (224) tokens for it, so the prompt is budgeted and truncated.
public enum TranscriptionPromptBuilder {
    /// Kept under Whisper's 224-token ceiling so that budget estimation errors
    /// cannot push the prompt into the space reserved for the transcript.
    public static let defaultTokenBudget = 200

    private static let sentenceTerminators: Set<Character> = [".", "!", "?", "。", "！", "？"]

    public static func prompt(from notes: ShowNotes, tokenBudget: Int = defaultTokenBudget) -> String? {
        var pieces: [String] = []

        if let podcastTitle = notes.podcastTitle {
            pieces.append(podcastTitle)
        }

        if let episodeTitle = notes.episodeTitle, episodeTitle != notes.podcastTitle {
            pieces.append(episodeTitle)
        }

        if let itemDescription = notes.itemDescription {
            let cleaned = plainText(itemDescription)
            if !cleaned.isEmpty {
                pieces.append(cleaned)
            }
        }

        let joined = pieces
            .map(terminated)
            .joined(separator: " ")

        let prompt = truncated(joined, tokenBudget: tokenBudget)
        return prompt.isEmpty ? nil : prompt
    }

    /// Strips markup, entities, and links so the prompt reads as clean prose.
    /// Links in particular are pure noise: they cost tokens and bias nothing.
    static func plainText(_ text: String) -> String {
        var result = text.replacingOccurrences(
            of: #"<[^>]+>"#,
            with: " ",
            options: .regularExpression
        )

        result = decodeEntities(result)

        result = result.replacingOccurrences(
            of: #"(?:https?://|www\.)\S+"#,
            with: " ",
            options: [.regularExpression, .caseInsensitive]
        )

        result = result.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let namedEntities: [String: String] = [
        "&amp;": "&",
        "&lt;": "<",
        "&gt;": ">",
        "&quot;": "\"",
        "&apos;": "'",
        "&nbsp;": " ",
        "&mdash;": "—",
        "&ndash;": "–",
        "&hellip;": "…",
        "&rsquo;": "\u{2019}",
        "&lsquo;": "\u{2018}",
        "&rdquo;": "\u{201D}",
        "&ldquo;": "\u{201C}"
    ]

    private static func decodeEntities(_ text: String) -> String {
        var result = text

        for (entity, replacement) in namedEntities {
            result = result.replacingOccurrences(of: entity, with: replacement, options: .caseInsensitive)
        }

        guard let regex = try? NSRegularExpression(pattern: #"&#(x?)([0-9A-Fa-f]+);"#) else {
            return result
        }

        let matches = regex
            .matches(in: result, range: NSRange(result.startIndex..., in: result))
            .reversed()

        for match in matches {
            guard let range = Range(match.range, in: result),
                  let prefixRange = Range(match.range(at: 1), in: result),
                  let digitsRange = Range(match.range(at: 2), in: result) else { continue }

            let radix = result[prefixRange].isEmpty ? 10 : 16
            guard let value = UInt32(result[digitsRange], radix: radix),
                  let scalar = Unicode.Scalar(value) else { continue }

            result.replaceSubrange(range, with: String(Character(scalar)))
        }

        return result
    }

    private static func terminated(_ text: String) -> String {
        guard let last = text.last else { return text }
        return sentenceTerminators.contains(last) ? text : text + "."
    }

    /// Trims to the token budget, preferring a sentence break and falling back to
    /// a word break so the prompt never ends mid-word.
    static func truncated(_ text: String, tokenBudget: Int) -> String {
        guard tokenBudget > 0 else { return "" }

        var cost = 0.0
        var endIndex = text.startIndex

        for index in text.indices {
            cost += tokenCost(text[index])
            if cost > Double(tokenBudget) { break }
            endIndex = text.index(after: index)
        }

        if endIndex == text.endIndex { return text }

        var kept = String(text[text.startIndex..<endIndex])
        let halfway = kept.count / 2

        if let boundary = kept.lastIndex(where: sentenceTerminators.contains),
           kept.distance(from: kept.startIndex, to: boundary) >= halfway {
            kept = String(kept[...boundary])
        } else if let boundary = kept.lastIndex(of: " "),
                  kept.distance(from: kept.startIndex, to: boundary) >= halfway {
            kept = String(kept[..<boundary])
        }

        return kept.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Rough per-character token cost. Latin text averages ~4 characters per BPE
    /// token; CJK, kana, and hangul run well over one token per character.
    private static func tokenCost(_ character: Character) -> Double {
        guard let scalar = character.unicodeScalars.first else { return 0.25 }

        switch scalar.value {
        case 0x3040...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xAC00...0xD7AF, 0xF900...0xFAFF:
            return 1.5
        default:
            return 0.25
        }
    }
}
