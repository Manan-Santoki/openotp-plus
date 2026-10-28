import AppKit
import ApplicationServices

enum FocusedField {

    struct Info {
        let isEditable: Bool
        let cocoaFrame: CGRect?
        var element: AXUIElement? = nil
        /// True when the field holds no text (or its value can't be read).
        var isEmpty: Bool = true
    }

    private static let editableRoles: Set<String> = [
        kAXTextFieldRole as String,
        kAXTextAreaRole as String,
        kAXComboBoxRole as String,
    ]

    static func current() -> Info {
        let system = AXUIElementCreateSystemWide()
        // This is polled while a code is on offer; never let a hung app stall
        // the main thread for the default 6 s.
        AXUIElementSetMessagingTimeout(system, 0.25)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focusedElement = focused else {
            return Info(isEditable: false, cocoaFrame: nil)
        }
        let element = focusedElement as! AXUIElement

        let role = stringAttr(element, kAXRoleAttribute)
        var editable = role.map { editableRoles.contains($0) } ?? false
        if !editable {
            var settable: DarwinBoolean = false
            AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable)
            editable = settable.boolValue
        }

        var isEmpty = true
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success,
           let text = value as? String {
            isEmpty = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        return Info(isEditable: editable, cocoaFrame: frame(of: element), element: element, isEmpty: isEmpty)
    }

    private static func stringAttr(_ element: AXUIElement, _ attr: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attr as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        var posValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success
        else { return nil }

        var point = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posValue as! AXValue, .cgPoint, &point)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)

        return cocoaFrame(fromAXOrigin: point, size: size)
    }

    private static func cocoaFrame(fromAXOrigin origin: CGPoint, size: CGSize) -> CGRect {
        let primaryHeight = (NSScreen.screens.first { $0.frame.origin == .zero }?.frame.height)
            ?? NSScreen.main?.frame.height ?? 0
        let cocoaY = primaryHeight - origin.y - size.height
        return CGRect(x: origin.x, y: cocoaY, width: size.width, height: size.height)
    }
}
