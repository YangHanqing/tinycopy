import Foundation

/// Pure, local text conversions. Each returns nil when it does not apply, so callers can use a
/// conversion both to decide whether to offer it and to produce its result.
enum Transforms {
    // MARK: JSON

    /// True for a JSON object or array (not a bare string or number).
    static func isJSONContainer(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = t.first, let last = t.last,
              (first == "{" && last == "}") || (first == "[" && last == "]") else { return false }
        return (try? JSONSerialization.jsonObject(with: Data(t.utf8))) != nil
    }

    /// Re-indents JSON with two spaces. Keys keep their order and numbers and strings keep their
    /// exact spelling, because only the whitespace between tokens is rewritten.
    static func formatJSON(_ text: String) -> String? {
        guard isJSONContainer(text) else { return nil }
        return reflow(text, pretty: true)
    }

    static func minifyJSON(_ text: String) -> String? {
        guard isJSONContainer(text) else { return nil }
        return reflow(text, pretty: false)
    }

    private static func reflow(_ text: String, pretty: Bool) -> String {
        let chars = Array(text.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars)
        var out = String.UnicodeScalarView()
        var depth = 0
        var i = 0
        func newline() {
            guard pretty else { return }
            out.append("\n")
            for _ in 0..<(depth * 2) { out.append(" ") }
        }
        while i < chars.count {
            let c = chars[i]
            switch c {
            case "\"":
                // Copy the string literal untouched, escapes included.
                out.append(c); i += 1
                while i < chars.count {
                    let s = chars[i]
                    out.append(s); i += 1
                    if s == "\\", i < chars.count { out.append(chars[i]); i += 1; continue }
                    if s == "\"" { break }
                }
                continue
            case "{", "[":
                // Keep empty containers on one line.
                var j = i + 1
                while j < chars.count, isJSONSpace(chars[j]) { j += 1 }
                if j < chars.count, chars[j] == (c == "{" ? "}" : "]") {
                    out.append(c); out.append(chars[j]); i = j + 1; continue
                }
                out.append(c); depth += 1; newline()
            case "}", "]":
                depth -= 1; newline(); out.append(c)
            case ",":
                out.append(c); newline()
            case ":":
                out.append(c); if pretty { out.append(" ") }
            default:
                if !isJSONSpace(c) { out.append(c) }
            }
            i += 1
        }
        return String(out)
    }

    private static func isJSONSpace(_ c: Unicode.Scalar) -> Bool {
        c == " " || c == "\n" || c == "\r" || c == "\t"
    }

    // MARK: JWT

    struct DecodedJWT {
        var header: String
        var payload: String
        /// The `exp` claim, when present.
        var expires: Date?
    }

    static func decodeJWT(_ text: String) -> DecodedJWT? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.utf8.count < 64_000, !t.contains(where: \.isWhitespace) else { return nil }
        let parts = t.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, !parts[0].isEmpty, !parts[1].isEmpty,
              let headerData = base64URLDecode(String(parts[0])),
              let payloadData = base64URLDecode(String(parts[1])),
              let header = try? JSONSerialization.jsonObject(with: headerData) as? [String: Any],
              header["alg"] != nil || header["typ"] != nil,
              let payloadObject = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
              let headerText = String(data: headerData, encoding: .utf8),
              let payloadText = String(data: payloadData, encoding: .utf8) else { return nil }
        let exp = (payloadObject["exp"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
        return DecodedJWT(header: formatJSON(headerText) ?? headerText,
                          payload: formatJSON(payloadText) ?? payloadText,
                          expires: exp)
    }

    private static func base64URLDecode(_ s: String) -> Data? {
        var b = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b.count % 4 != 0 { b += "=" }
        return Data(base64Encoded: b)
    }

    // MARK: Base64

    /// Decodes Base64 (standard or URL-safe, line breaks allowed) only when the result is readable
    /// UTF-8 text. Short or binary-looking input returns nil to avoid misreading ordinary words.
    static func decodeBase64(_ text: String) -> String? {
        let compact = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: "\r", with: "")
        guard compact.count >= 16, compact.utf8.count < 2_000_000 else { return nil }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=-_")
        guard compact.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        // Plain words and identifiers are valid Base64 alphabets too; demand some sign of encoding.
        let hasDigitOrSymbol = compact.contains { $0.isNumber || "+/=".contains($0) }
        let hasUpper = compact.contains { $0.isUppercase }, hasLower = compact.contains { $0.isLowercase }
        guard hasDigitOrSymbol || (hasUpper && hasLower) else { return nil }
        guard let data = base64URLDecode(compact.replacingOccurrences(of: "=", with: "")),
              let decoded = String(data: data, encoding: .utf8), !decoded.isEmpty else { return nil }
        let scalars = decoded.unicodeScalars
        let readable = scalars.filter { s in
            if s == "\n" || s == "\r" || s == "\t" { return true }
            return !CharacterSet.controlCharacters.contains(s) && s != "\u{FFFD}"
        }.count
        guard Double(readable) / Double(scalars.count) >= 0.98 else { return nil }
        return decoded
    }

    static func encodeBase64(_ text: String) -> String {
        Data(text.utf8).base64EncodedString()
    }

    // MARK: URL

    static func isWebURL(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.utf8.count < 8192, !t.contains(where: \.isWhitespace),
              let url = URL(string: t), let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme), let host = url.host, !host.isEmpty else { return false }
        return true
    }

    /// Percent-decoding, only when the text holds `%XX` escapes and decoding changes it.
    static func urlDecode(_ text: String) -> String? {
        guard text.range(of: "%[0-9A-Fa-f]{2}", options: .regularExpression) != nil,
              let decoded = text.removingPercentEncoding, decoded != text else { return nil }
        return decoded
    }

    /// Encodes everything except the unreserved characters of RFC 3986, as a query value needs.
    static func urlEncode(_ text: String) -> String? {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        guard let encoded = text.addingPercentEncoding(withAllowedCharacters: allowed), encoded != text else { return nil }
        return encoded
    }

    // MARK: Unix time

    /// A 10-digit (seconds) or 13-digit (milliseconds) Unix time between 2001 and 2100.
    static func unixDate(_ text: String) -> Date? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count == 10 || t.count == 13, t.allSatisfy(\.isASCII), let n = Double(t), t.allSatisfy(\.isNumber) else { return nil }
        let seconds = t.count == 13 ? n / 1000 : n
        guard seconds >= 978_307_200, seconds < 4_102_444_800 else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    static func localTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: date)
    }

    static func iso8601(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.timeZone = .current
        return f.string(from: date)
    }

    // MARK: Plain text

    static func trimmed(_ text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return t != text && !t.isEmpty ? t : nil
    }
}

enum ContentDetector {
    /// The most specific reading of `text`. Uncertain cases stay `.plain`.
    static func detect(_ text: String) -> (type: ContentType, derived: String?) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, t.utf8.count <= 2_000_000 else { return (.plain, nil) }
        if let jwt = Transforms.decodeJWT(t) { return (.jwt, jwt.payload) }
        if Transforms.isJSONContainer(t) { return (.json, nil) }
        if Transforms.isWebURL(t) { return (.url, Transforms.urlDecode(t)) }
        if Transforms.unixDate(t) != nil { return (.timestamp, nil) }
        if let decoded = Transforms.decodeBase64(t) { return (.base64, decoded) }
        return (.plain, Transforms.urlDecode(t))
    }
}
