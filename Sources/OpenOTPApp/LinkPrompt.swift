import AppKit
import OpenOTPCore

/// Offers a freshly arrived verification / sign-in link in the screen's top
/// right corner: "Open sign-in link / github.com · from GitHub". A link isn't
/// typed into a field, so unlike `CodeSuggester` this doesn't follow focus.
/// Click to open it in your browser; Esc or a minute's wait dismisses it, and
/// the menu bar keeps it either way.
@MainActor
final class LinkPrompt {

    static let showFor: TimeInterval = 60

    var onOpen: ((DetectedLink) -> Void)?

    private let pill = FillPill()
    private var dismissTimer: Timer?
    private var keyMonitor: Any?

    func offer(_ link: DetectedLink) {
        withdraw()
        pill.present(suggestion(for: link), near: nil)
        dismissTimer = Timer.scheduledTimer(withTimeInterval: Self.showFor, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.withdraw() }
        }
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return }
            Task { @MainActor [weak self] in self?.withdraw() }
        }
    }

    func withdraw() {
        dismissTimer?.invalidate(); dismissTimer = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        pill.dismiss()
    }

    private func suggestion(for link: DetectedLink) -> Suggestion {
        Suggestion(
            id: link.messageID,
            title: "Open \(LinkPrompt.kind(of: link)) link",
            subtitle: "\(link.isUnverified ? "Unverified · " : "")\(link.host) · from \(link.senderName)",
            symbol: "link",
            unverified: link.isUnverified,
            accessibilityLabel: "Open \(LinkPrompt.kind(of: link)) link to \(link.host), \(link.isUnverified ? "unverified, " : "")from \(link.senderName)",
            action: { [weak self] in self?.onOpen?(link) }
        )
    }

    /// A short label from the subject, e.g. "sign-in" or "verification".
    static func kind(of link: DetectedLink) -> String {
        let s = link.subject.lowercased()
        if s.contains("reset") || s.contains("password") { return "password reset" }
        if s.contains("sign in") || s.contains("sign-in") || s.contains("log in") || s.contains("login") || s.contains("magic") {
            return "sign-in"
        }
        if s.contains("confirm") { return "confirmation" }
        return "verification"
    }
}
