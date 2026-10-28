import AppKit
import OpenOTPCore

/// What a pill row shows and does: "Fill code 123456 / From GitHub", or
/// "Open sign-in link / github.com · from GitHub".
struct Suggestion {
    /// Identity for `isShowing` — the source message.
    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    /// Distinct, non-accent treatment (see the detectors' adversarial contract).
    let unverified: Bool
    let accessibilityLabel: String
    let action: () -> Void
}

/// A one-row AutoFill suggestion styled after macOS's own "Fill code … From
/// Messages" popup: a menu-material card hugging the focused field (or the
/// screen corner), holding a single selected row. Click the row to act. When it
/// shows and hides is up to its owner (`CodeSuggester`, `LinkPrompt`); this
/// class only draws and places it.
@MainActor
final class FillPill {

    private var panel: NSPanel?
    private var current: Suggestion?
    private var anchor: CGRect?

    private let inset: CGFloat = 5
    private let rowHeight: CGFloat = 42
    private let cornerRadius: CGFloat = 9

    func present(_ suggestion: Suggestion, near anchor: CGRect?) {
        dismiss()
        current = suggestion

        let content = buildContent(suggestion)
        let size = content.frame.size
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        // Screen-capture privacy: exclude the pill (which shows the raw code)
        // from all screen recording/sharing/screenshots. It stays fully visible
        // to the person at the Mac, but is a blank hole to any capture.
        panel.sharingType = Prefs.hideFromCapture ? .none : .readWrite

        panel.contentView = content
        position(panel, size: size, near: anchor)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.invalidateShadow()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 1
        }
        self.panel = panel
        self.anchor = anchor
    }

    /// Whether the suggestion with this id is the one on screen right now.
    func isShowing(_ id: String) -> Bool {
        current?.id == id
    }

    /// Follow the field when it moves (scrolling, window drags).
    func move(near anchor: CGRect) {
        guard let panel, anchor != self.anchor else { return }
        position(panel, size: panel.frame.size, near: anchor)
        self.anchor = anchor
    }

    func dismiss() {
        panel?.orderOut(nil)
        panel = nil
        current = nil
        anchor = nil
    }

    private func buildContent(_ suggestion: Suggestion) -> NSView {
        let unverified = suggestion.unverified
        let title = suggestion.title
        let subtitle = suggestion.subtitle

        let titleFont = NSFont.systemFont(ofSize: 13, weight: .medium)
        let subtitleFont = NSFont.systemFont(ofSize: 11)
        let textWidth = min(340, ceil(max(
            (title as NSString).size(withAttributes: [.font: titleFont]).width,
            (subtitle as NSString).size(withAttributes: [.font: subtitleFont]).width
        )))
        let iconSide: CGFloat = 26
        let rowWidth = 8 + iconSide + 8 + textWidth + 12
        let size = NSSize(width: rowWidth + inset * 2, height: rowHeight + inset * 2)

        let container = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        container.material = .menu
        container.blendingMode = .behindWindow
        container.state = .active
        container.maskImage = Self.roundedMask(radius: cornerRadius)

        let row = SuggestionRow(frame: NSRect(x: inset, y: inset, width: rowWidth, height: rowHeight))
        row.tint = unverified ? .systemOrange : .selectedContentBackgroundColor
        row.onClick = suggestion.action
        row.setAccessibilityLabel(suggestion.accessibilityLabel)
        container.addSubview(row)

        let symbol = unverified ? "exclamationmark.triangle.fill" : suggestion.symbol
        let config = NSImage.SymbolConfiguration(pointSize: 17, weight: .regular)
        if let glyph = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) {
            let iv = NSImageView(image: glyph)
            iv.contentTintColor = .white
            iv.frame = NSRect(x: 8, y: (rowHeight - iconSide) / 2, width: iconSide, height: iconSide)
            row.addSubview(iv)
        }

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = titleFont
        titleLabel.textColor = .white
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.frame = NSRect(x: 8 + iconSide + 8, y: rowHeight / 2 - 1, width: textWidth, height: 17)
        row.addSubview(titleLabel)

        let subtitleLabel = NSTextField(labelWithString: subtitle)
        subtitleLabel.font = subtitleFont
        subtitleLabel.textColor = NSColor.white.withAlphaComponent(0.85)
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.frame = NSRect(x: 8 + iconSide + 8, y: rowHeight / 2 - 16, width: textWidth, height: 14)
        row.addSubview(subtitleLabel)

        return container
    }

    /// Stretchable rounded-rect mask, so the window shadow follows the corners.
    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }

    /// Sit just under the field, left-aligned with it, like the system
    /// suggestion; flip above it when there's no room below.
    private func position(_ panel: NSPanel, size: NSSize, near anchor: CGRect?) {
        let gap: CGFloat = 4
        let origin: NSPoint
        if let a = anchor, a.width > 0,
           let screen = NSScreen.screens.first(where: { $0.frame.intersects(a) }) ?? NSScreen.main {
            let f = screen.visibleFrame
            var y = a.minY - size.height - gap
            if y < f.minY { y = a.maxY + gap }
            let x = min(max(a.minX, f.minX + 8), f.maxX - size.width - 8)
            origin = NSPoint(x: x, y: min(y, f.maxY - size.height))
        } else if let screen = NSScreen.main {
            let f = screen.visibleFrame
            origin = NSPoint(x: f.maxX - size.width - 20, y: f.maxY - size.height - 20)
        } else {
            origin = NSPoint(x: 200, y: 200)
        }
        panel.setFrameOrigin(origin)
    }

}

/// The single highlighted suggestion row. Clicks land without activating
/// OpenOTP, so focus stays in the field being filled.
private final class SuggestionRow: NSView {
    var onClick: (() -> Void)?
    var tint: NSColor = .selectedContentBackgroundColor
    private var pressed = false { didSet { needsDisplay = true } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let color = pressed ? (tint.shadow(withLevel: 0.15) ?? tint) : tint
        color.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 5, yRadius: 5).fill()
    }

    override func mouseDown(with event: NSEvent) { pressed = true }

    override func mouseUp(with event: NSEvent) {
        pressed = false
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
    }

    override func accessibilityPerformPress() -> Bool {
        onClick?()
        return true
    }
}

/// Display name from a "Name <addr>" sender, falling back to the raw sender.
func displayName(ofSender sender: String) -> String {
    if let lt = sender.firstIndex(of: "<") {
        let name = sender[..<lt].trimmingCharacters(in: CharacterSet(charactersIn: " \""))
        if !name.isEmpty { return name }
    }
    return sender.trimmingCharacters(in: .whitespaces)
}

extension DetectedCode {
    var senderName: String { displayName(ofSender: sender) }
}

extension DetectedLink {
    var senderName: String { displayName(ofSender: sender) }
}
