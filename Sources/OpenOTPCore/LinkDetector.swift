import Foundation

// Verification-link detection — the companion to the OTP detector, with the
// same precision-first stance. Every link in the email is a candidate; chrome
// (unsubscribe, footers, social, "not you?") is thrown out before scoring; the
// rest must earn its place from what the email says about it (anchor text, the
// text around it, the subject) AND from the URL itself. When in doubt it stays
// silent: a missed link costs a trip to the inbox, a wrong one costs trust.

public enum LinkDetector {

    public static let threshold = 0.60
    public static let ambiguousThreshold = 0.75
    static let ambiguityMargin = 0.10
    static let contextBefore = 160
    static let contextAfter = 80

    public struct Result {
        public let url: URL
        public let confidence: Double
        public let trace: [String]
    }

    struct Candidate {
        let url: URL
        let anchorText: String
        let context: String
        let prominent: Bool
    }

    // MARK: - Lexicon

    /// What the link itself says it does.
    static let actionPhrases = [
        "verify", "confirm", "activate", "sign in", "sign-in", "signin",
        "log in", "log-in", "login", "magic link", "reset password",
        "reset your password", "set password", "set your password",
        "create password", "authenticate", "approve", "validate",
        "complete sign", "finish sign", "continue sign",
    ]
    /// What the email says around the link.
    static let contextPhrases = [
        "click the link", "click the button", "click below", "click here",
        "tap the link", "tap the button", "tap below", "link below",
        "button below", "following link", "this link", "magic link",
        "verify your", "confirm your", "sign in to", "log in to",
        "to continue", "to complete", "reset your password", "expires",
        "valid for", "one-time", "single-use",
    ]
    static let subjectPhrases = [
        "verify", "verification", "confirm", "sign in", "sign-in", "log in",
        "login", "magic link", "activate", "reset", "password",
        "authenticate", "access link", "complete your registration",
    ]
    /// Anchor text that marks a link as chrome or a trap, never the action.
    static let rejectAnchor = [
        "unsubscribe", "preferences", "privacy", "terms", "help", "support",
        "contact", "view in browser", "view online", "view this email",
        "not you", "wasn't you", "wasn't me", "didn't request",
        "did not request", "report", "learn more", "download",
        "app store", "google play", "secure your account",
    ]
    static let rejectURL = [
        "unsubscribe", "/preferences", "optout", "opt-out", "/privacy",
        "/terms", "/help", "/support", "list-manage",
    ]
    static let rejectHosts = [
        "facebook.com", "twitter.com", "instagram.com", "linkedin.com",
        "youtube.com", "tiktok.com", "apps.apple.com", "play.google.com",
    ]
    static let urlSignal = #"verif|confirm|activat|magic|log-?in|sign-?in|sign_in|auth|token|reset|passwordless|otp|validate|callback|one-?time|email-link|access"#
    static let opaqueToken = #"[A-Za-z0-9_\-%.=]{24,}"#

    // MARK: - Entry points

    /// App bridge: run the detector on an `EmailMessage`, applying the same age
    /// gate as the code detector. This is what the watcher calls.
    public static func extract(from message: EmailMessage, now: Date = Date()) -> DetectedLink? {
        if now.timeIntervalSince(message.receivedAt) > OTPv2.maxAge { return nil }
        guard let r = detect(subject: message.subject, body: message.body, isHTML: message.isHTML)
        else { return nil }
        return DetectedLink(
            url: r.url, confidence: r.confidence, account: message.account,
            sender: message.sender, subject: message.subject,
            messageID: message.id, receivedAt: message.receivedAt,
            hostMatchesSender: hostMatches(r.url, sender: message.sender),
            evidenceTrace: r.trace
        )
    }

    public static func detect(subject: String, body: String, isHTML: Bool) -> Result? {
        let candidates = isHTML ? htmlCandidates(body) : textCandidates(body)
        let subjectHit = contains(subject.lowercased(), anyOf: subjectPhrases)

        // Score, keeping the best evidence per distinct URL (a button and its
        // "or paste this link" fallback are the same link).
        var best: [String: (score: Double, trace: [String], url: URL)] = [:]
        var order: [String] = []
        for c in candidates {
            guard let scored = score(c, subjectHit: subjectHit) else { continue }
            let key = c.url.absoluteString
            if best[key] == nil { order.append(key) }
            if scored.0 > best[key]?.score ?? -1 { best[key] = (scored.0, scored.1, c.url) }
        }
        let ranked = order.compactMap { k in best[k] }.enumerated()
            .sorted { $0.element.score != $1.element.score ? $0.element.score > $1.element.score : $0.offset < $1.offset }
            .map { $0.element }
        guard var winner = ranked.first else { return nil }

        var bar = threshold
        if ranked.count > 1, winner.score - ranked[1].score < ambiguityMargin {
            bar = ambiguousThreshold
            winner.trace.append("ambiguity(runnerUp=\(ranked[1].url.host ?? "?"))->bar=\(bar)")
        }
        guard winner.score >= bar else { return nil }
        winner.trace.append("C=\(String(format: "%.2f", winner.score))")
        return Result(url: winner.url, confidence: OTPv2.round3(winner.score), trace: winner.trace)
    }

    // MARK: - Scoring

    static func score(_ c: Candidate, subjectHit: Bool) -> (Double, [String])? {
        let anchor = c.anchorText.lowercased()
        let context = c.context.lowercased()
        let target = (c.url.path + "?" + (c.url.query ?? "")).lowercased()
        let host = (c.url.host ?? "").lowercased()

        if contains(anchor, anyOf: rejectAnchor) { return nil }
        if contains(c.url.absoluteString.lowercased(), anyOf: rejectURL) { return nil }
        if rejectHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) { return nil }
        if OTPv2.regexMatches(c.url.path.lowercased(), #"\.(png|jpe?g|gif|svg|webp|ico)$"#) { return nil }

        var score = 0.0
        var trace = ["host=\(host)"]
        // With no anchor (plain text), the lead-in line is what names the action.
        let anchorHit = contains(anchor, anyOf: actionPhrases)
        let leadInHit = anchor.isEmpty && contains(context, anyOf: actionPhrases)
        let urlHit = OTPv2.regexMatches(target, urlSignal)
        let contextHit = contains(context, anyOf: contextPhrases)

        if anchorHit { score += 0.40; trace.append("anchor-action") }
        if leadInHit { score += 0.25; trace.append("lead-in-action") }
        if urlHit { score += 0.20; trace.append("url-signal") }
        if subjectHit { score += 0.15; trace.append("subject") }
        if contextHit { score += 0.15; trace.append("context") }
        if OTPv2.regexMatches(target, opaqueToken) { score += 0.10; trace.append("token") }
        if c.prominent { score += 0.10; trace.append("button") }

        // Gate: the link must name an action (itself or via its URL), and the
        // email must independently back it up.
        guard anchorHit || leadInHit || urlHit else { return nil }
        guard subjectHit || contextHit else { return nil }
        return (min(1.0, score), trace)
    }

    // MARK: - Candidate extraction

    static func htmlCandidates(_ html: String) -> [Candidate] {
        let ns = html as NSString
        let anchor = OTPv2.regex(
            #"<a\b([^>]*?)\bhref\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))([^>]*)>(.*?)</a\s*>"#,
            caseInsensitive: true, dotAll: true)
        var out: [Candidate] = []
        for m in anchor.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let href = [2, 3, 4].lazy.compactMap { i -> String? in
                let r = m.range(at: i)
                return r.location == NSNotFound ? nil : ns.substring(with: r)
            }.first ?? ""
            guard let url = parseURL(OTPv2.decodeEntities(href)) else { continue }

            let attrs = ns.substring(with: m.range(at: 1)) + " " + ns.substring(with: m.range(at: 5))
            let inner = ns.substring(with: m.range(at: 6))
            var text = plainText(inner)
            if text.isEmpty, let alt = OTPv2.regex(#"\balt\s*=\s*"([^"]*)""#, caseInsensitive: true)
                .firstMatch(in: inner, range: NSRange(location: 0, length: (inner as NSString).length)) {
                text = OTPv2.decodeEntities((inner as NSString).substring(with: alt.range(at: 1)))
            }

            let beforeStart = max(0, m.range.location - 3000)
            let before = plainText(ns.substring(with: NSRange(location: beforeStart, length: m.range.location - beforeStart)))
            let afterEnd = min(ns.length, NSMaxRange(m.range) + 1500)
            let after = plainText(ns.substring(with: NSRange(location: NSMaxRange(m.range), length: afterEnd - NSMaxRange(m.range))))
            let context = String(before.suffix(contextBefore)) + " " + String(after.prefix(contextAfter))

            let prominent = OTPv2.regexMatches(attrs.lowercased(), #"button|btn|cta|background|padding|border-radius"#)
            out.append(Candidate(url: url, anchorText: text, context: context, prominent: prominent))
        }
        return out
    }

    static func textCandidates(_ text: String) -> [Candidate] {
        let lines = text.components(separatedBy: .newlines)
        let urlPattern = OTPv2.regex(#"https?://[^\s<>"'\)\]]+"#, caseInsensitive: true)
        var out: [Candidate] = []
        for (i, line) in lines.enumerated() {
            let ns = line as NSString
            for m in urlPattern.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
                var raw = ns.substring(with: m.range)
                while let last = raw.last, ".,;:!?".contains(last) { raw.removeLast() }
                guard let url = parseURL(raw) else { continue }
                // Lead-in: the rest of this line plus the nearest non-empty line above.
                let rest = ns.replacingCharacters(in: m.range, with: " ")
                let above = lines[..<i].reversed().first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? ""
                let below = i + 1 < lines.count ? lines[i + 1] : ""
                let context = collapse(above + " " + rest + " " + below)
                out.append(Candidate(url: url, anchorText: "", context: context, prominent: false))
            }
        }
        return out
    }

    // MARK: - Helpers

    static func parseURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    static func plainText(_ html: String) -> String {
        var s = OTPv2.regex(#"<(style|script)\b.*?</\1\s*>|<!--.*?-->"#, caseInsensitive: true, dotAll: true)
            .stringByReplacingMatches(in: html, range: NSRange(location: 0, length: (html as NSString).length), withTemplate: " ")
        s = OTPv2.regex(#"<[^>]*>"#).stringByReplacingMatches(
            in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: " ")
        return collapse(OTPv2.decodeEntities(s))
    }

    static func collapse(_ s: String) -> String {
        s.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    static func contains(_ haystack: String, anyOf needles: [String]) -> Bool {
        needles.contains { haystack.contains($0) }
    }

    /// Does the link point at the sender's own site? Compares registrable
    /// domains (last two labels, three for "co.uk"-style suffixes).
    static func hostMatches(_ url: URL, sender: String) -> Bool {
        guard let domain = senderDomain(sender), let host = url.host else { return false }
        return domain == registrable(host)
    }

    /// Registrable domain of the sender's address, e.g. "github.com".
    static func senderDomain(_ sender: String) -> String? {
        let ns = sender as NSString
        guard let m = OTPv2.regex(#"@([A-Za-z0-9.\-]+)"#).firstMatch(in: sender, range: NSRange(location: 0, length: ns.length))
        else { return nil }
        return registrable(ns.substring(with: m.range(at: 1)))
    }

    static func registrable(_ host: String) -> String {
        let labels = host.lowercased().split(separator: ".").map(String.init)
        guard labels.count > 2 else { return labels.joined(separator: ".") }
        let secondLevel: Set<String> = ["co", "com", "org", "net", "ac", "gov", "edu", "ne", "or"]
        let take = secondLevel.contains(labels[labels.count - 2]) && labels.last?.count == 2 ? 3 : 2
        return labels.suffix(take).joined(separator: ".")
    }
}
