import Foundation

/// What "Find private info" looks for.
enum VideoPrivacyKind: String, Codable, CaseIterable, Identifiable {
    case face
    case email
    case phone
    case card
    /// A key or token in a known format, or a value after "password:" etc.
    case secret
    /// Long random-looking text: a guess.
    case possibleKey
    case customWord

    var id: String { rawValue }

    var title: String {
        switch self {
        case .face: return L("Face")
        case .email: return L("Email address")
        case .phone: return L("Phone number")
        case .card: return L("Card number")
        case .secret: return L("Key or password")
        case .possibleKey: return L("Possible key")
        case .customWord: return L("Your word")
        }
    }

    var symbol: String {
        switch self {
        case .face: return "face.smiling"
        case .email: return "envelope"
        case .phone: return "phone"
        case .card: return "creditcard"
        case .secret: return "key"
        case .possibleKey: return "questionmark.key.filled"
        case .customWord: return "text.word.spacing"
        }
    }
}

/// Private things in a line of text (as read off the screen), each with
/// the characters it covers. Pure: the tests feed it sample text.
enum VideoPrivacyPatterns {
    struct Match: Equatable {
        var kind: VideoPrivacyKind
        var range: Range<String.Index>
        var text: String
    }

    private static func regex(_ pattern: String, _ options: NSRegularExpression.Options = []) -> NSRegularExpression {
        // Fixed patterns: a typo here is a programming error.
        try! NSRegularExpression(pattern: pattern, options: options)
    }

    private static let email = regex(#"[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}"#, [.caseInsensitive])
    private static let cardLike = regex(#"(?<![\d])(?:\d[ \-]?){12,18}\d(?![\d])"#)
    private static let phoneLike = regex(#"(?<![\w])(?:\+\d{1,3}[\s.\-]?)?(?:\(\d{1,4}\)[\s.\-]?)?\d{2,4}(?:[\s.\-]?\d{2,4}){1,4}(?![\w])"#)
    /// Formats services use for their keys and tokens.
    private static let knownKeys: [NSRegularExpression] = [
        regex(#"\bsk-(?:proj-|ant-)?[A-Za-z0-9_\-]{16,}"#),
        regex(#"\b[sprk]k_(?:live|test)_[A-Za-z0-9]{12,}"#),
        regex(#"\bgh[pousr]_[A-Za-z0-9]{30,}"#),
        regex(#"\bgithub_pat_[A-Za-z0-9_]{20,}"#),
        regex(#"\bglpat-[A-Za-z0-9_\-]{18,}"#),
        regex(#"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b"#),
        regex(#"\bxox[abposr]-[A-Za-z0-9\-]{10,}"#),
        regex(#"\bAIza[0-9A-Za-z_\-]{30,}"#),
        regex(#"\beyJ[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}"#),
        regex(#"-----BEGIN [A-Z ]*PRIVATE KEY-----"#),
    ]
    /// "password: hunter2", "API_KEY=…": the value after the label.
    private static let labeled = regex(#"\b(?:password|passwd|pwd|passcode|secret|token|api[_\- ]?key|apikey|access[_\- ]?key|client[_\- ]?secret|auth)\b\s*[:=]\s*["']?([^\s"']{4,})"#, [.caseInsensitive])
    private static let longToken = regex(#"[A-Za-z0-9_\-+/=]{24,}"#)

    static func matches(in text: String, customWords: [String] = []) -> [Match] {
        let whole = NSRange(text.startIndex..., in: text)
        var found: [Match] = []
        func add(_ kind: VideoPrivacyKind, _ range: NSRange) {
            guard let r = Range(range, in: text) else { return }
            // One thing, one match: the first kind found wins.
            guard !found.contains(where: { $0.range.overlaps(r) }) else { return }
            found.append(Match(kind: kind, range: r, text: String(text[r])))
        }
        for pattern in knownKeys {
            for match in pattern.matches(in: text, range: whole) { add(.secret, match.range) }
        }
        for match in labeled.matches(in: text, range: whole) where match.numberOfRanges > 1 {
            add(.secret, match.range(at: 1))
        }
        for match in email.matches(in: text, range: whole) { add(.email, match.range) }
        for match in cardLike.matches(in: text, range: whole) {
            guard let r = Range(match.range, in: text) else { continue }
            let digits = text[r].filter(\.isNumber)
            if (13...19).contains(digits.count), luhn(String(digits)) { add(.card, match.range) }
        }
        for match in phoneLike.matches(in: text, range: whole) {
            guard let r = Range(match.range, in: text), isPhone(String(text[r])) else { continue }
            add(.phone, match.range)
        }
        for match in longToken.matches(in: text, range: whole) {
            guard let r = Range(match.range, in: text), looksRandom(String(text[r])) else { continue }
            add(.possibleKey, match.range)
        }
        for word in customWords.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }) where !word.isEmpty {
            let pattern = regex("(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: word) + "(?![\\p{L}\\p{N}])", [.caseInsensitive])
            for match in pattern.matches(in: text, range: whole) { add(.customWord, match.range) }
        }
        return found.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    /// The card number checksum: random digits fail it 9 times in 10.
    static func luhn(_ digits: String) -> Bool {
        var sum = 0
        for (index, character) in digits.reversed().enumerated() {
            guard var value = character.wholeNumberValue else { return false }
            if index % 2 == 1 {
                value *= 2
                if value > 9 { value -= 9 }
            }
            sum += value
        }
        return sum % 10 == 0
    }

    /// 8–15 digits written like a phone number: grouped, or with a + or
    /// area code; not a date, a time, an amount or a version.
    static func isPhone(_ candidate: String) -> Bool {
        let digits = candidate.filter(\.isNumber)
        guard (8...15).contains(digits.count) else { return false }
        let grouped = candidate.contains { " -.()".contains($0) } || candidate.hasPrefix("+")
        guard grouped || digits.count >= 10 else { return false }
        // 2026-10-28, 10.28.2026, 12:30
        if candidate.range(of: #"^(19|20)\d{2}[\-./]\d{1,2}[\-./]\d{1,2}$"#, options: .regularExpression) != nil { return false }
        if candidate.range(of: #"^\d{1,2}[\-./]\d{1,2}[\-./](19|20)\d{2}$"#, options: .regularExpression) != nil { return false }
        // One digit repeated, or counting up: placeholders.
        if Set(digits).count <= 2 { return false }
        return true
    }

    /// Long, mixed letters and digits, high in entropy: like a key, not a
    /// word, path or hash-free identifier.
    static func looksRandom(_ token: String) -> Bool {
        guard token.count >= 24 else { return false }
        let hasUpper = token.contains(where: \.isUppercase)
        let hasLower = token.contains(where: \.isLowercase)
        let digits = token.filter(\.isNumber).count
        guard digits >= 3, (hasUpper && hasLower) || (digits >= 6 && (hasUpper || hasLower)) else { return false }
        var counts: [Character: Int] = [:]
        for character in token { counts[character, default: 0] += 1 }
        let n = Double(token.count)
        let entropy = counts.values.reduce(0.0) { total, count in
            let p = Double(count) / n
            return total - p * log2(p)
        }
        return entropy >= 3.6
    }
}
