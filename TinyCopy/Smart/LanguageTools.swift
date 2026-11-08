import Foundation
import NaturalLanguage

enum LanguageTools {
    /// The first preferred macOS language, reduced to what translation targets are named by
    /// ("zh-Hans", "zh-Hant", "en", "ja", …).
    static func recommendedTarget(preferred: [String] = Locale.preferredLanguages) -> String {
        guard let first = preferred.first else { return "en" }
        return normalized(first)
    }

    static func normalized(_ identifier: String) -> String {
        let language = Locale.Language(identifier: identifier)
        guard let code = language.languageCode?.identifier else { return identifier }
        if code == "zh" {
            let script = Locale.Language(identifier: language.maximalIdentifier).script?.identifier ?? "Hans"
            return "zh-\(script)"
        }
        return code
    }

    /// Same language and script, ignoring region ("en-GB" and "en" match; "zh-Hans" and "zh-Hant" do not).
    static func sameLanguage(_ a: String, _ b: String) -> Bool {
        let la = Locale.Language(identifier: a), lb = Locale.Language(identifier: b)
        guard la.languageCode == lb.languageCode else { return false }
        let sa = Locale.Language(identifier: la.maximalIdentifier).script
        let sb = Locale.Language(identifier: lb.maximalIdentifier).script
        return sa == sb
    }

    static func displayName(_ identifier: String) -> String {
        Locale.current.localizedString(forIdentifier: identifier) ?? identifier
    }

    /// The language of `text` when it reads clearly as prose in one language, else nil.
    /// Code, data and short fragments return nil, so they are never offered for translation.
    static func proseLanguage(of text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2, trimmed.utf16.count <= 20_000 else { return nil }
        let sample = String(trimmed.prefix(1500))
        var letters = 0, symbols = 0, total = 0
        for scalar in sample.unicodeScalars where !CharacterSet.whitespacesAndNewlines.contains(scalar) {
            total += 1
            if CharacterSet.letters.contains(scalar) { letters += 1 }
            if "{}[];=<>()$\\|&#".unicodeScalars.contains(scalar) { symbols += 1 }
        }
        guard total > 0, Double(letters) / Double(total) >= 0.6, Double(symbols) / Double(total) < 0.05 else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(sample)
        guard let (language, probability) = recognizer.languageHypotheses(withMaximum: 1).first,
              language != .undetermined else { return nil }
        // Short text gets a lower bar: one or two words rarely reach a high probability.
        let bar = sample.count < 20 ? 0.5 : 0.7
        return probability >= bar ? language.rawValue : nil
    }
}
