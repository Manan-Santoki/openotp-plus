import AppKit
import ApplicationServices
import OpenOTPCore

/// Keeps a freshly arrived code on offer the way macOS AutoFill does: for a few
/// minutes, the pill appears under whichever empty text field you focus, hides
/// while you're elsewhere or typing, and comes back when you return. The offer
/// ends when the code is filled, you press Esc, or the window lapses.
@MainActor
final class CodeSuggester {

    /// How long a new code stays on offer.
    static let offerWindow: TimeInterval = 5 * 60

    var onFill: ((DetectedCode) -> Void)?

    private let pill = FillPill()
    private var pending: DetectedCode?
    private var expiresAt = Date.distantPast
    private var pollTimer: Timer?
    private var keyMonitor: Any?
    /// The field you last typed into; the pill stays away from it until focus
    /// moves on (covers fields whose text Accessibility can't read).
    private var typedIn: AXUIElement?

    func offer(_ code: DetectedCode) {
        pending = code
        expiresAt = Date().addingTimeInterval(Self.offerWindow)
        typedIn = nil
        start()
        refresh()
    }

    func withdraw() {
        pending = nil
        typedIn = nil
        pollTimer?.invalidate(); pollTimer = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        pill.dismiss()
    }

    private func start() {
        if pollTimer == nil {
            // Polling the focused element is cheap and catches every way focus
            // moves (clicks, Tab, app switches) plus fields that scroll.
            pollTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in self?.refresh() }
            }
        }
        if keyMonitor == nil {
            keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                let isEscape = event.keyCode == 53
                Task { @MainActor [weak self] in self?.keyPressed(escape: isEscape) }
            }
        }
    }

    private func keyPressed(escape: Bool) {
        guard pending != nil else { return }
        if escape {
            withdraw()
        } else {
            typedIn = FocusedField.current().element
            pill.dismiss()
        }
    }

    private func refresh() {
        guard let code = pending, Date() < expiresAt,
              Prefs.pillEnabled, Accessibility.isTrusted else {
            withdraw()
            return
        }

        let field = FocusedField.current()
        if let typedIn, !(field.element.map { CFEqual($0, typedIn) } ?? false) {
            self.typedIn = nil
        }
        guard field.isEditable, field.isEmpty, typedIn == nil,
              let anchor = field.cocoaFrame, anchor.width > 0 else {
            pill.dismiss()
            return
        }

        if pill.isShowing(code.messageID) {
            pill.move(near: anchor)
        } else {
            pill.present(suggestion(for: code), near: anchor)
        }
    }

    private func suggestion(for code: DetectedCode) -> Suggestion {
        // Spell the code out so VoiceOver reads "4 8 3 9 2 0", not a number.
        let spelled = code.code.map(String.init).joined(separator: " ")
        return Suggestion(
            id: code.messageID,
            title: "Fill code \(code.code)",
            subtitle: code.isUnverified ? "Unverified · from \(code.senderName)" : "From \(code.senderName)",
            symbol: "envelope.fill",
            unverified: code.isUnverified,
            accessibilityLabel: "Fill verification code \(spelled), \(code.isUnverified ? "unverified, " : "")from \(code.senderName)",
            action: { [weak self] in self?.onFill?(code) }
        )
    }
}
