import AppKit
import ApplicationServices
import CueCore
import Foundation

/// Explicit Accessibility-only selection capture adapted from Pewter's
/// bounded AX traversal. Cue deliberately omits its synthetic Cmd-C and
/// recent-clipboard fallbacks.
@MainActor
enum SelectionCaptureService {
    struct Selection {
        var text: String
        var source: SourceMetadata
        var sourceBundleIdentifierForMapping: String?
        var sourceWindowTitleForMapping: String?
    }

    enum Result {
        case selection(Selection)
        case permissionMissing
        case secureField
        case denylisted(appName: String)
        case nothingSelected
        case unavailable
    }

    static func isTrusted(prompt: Bool) -> Bool {
        if prompt {
            return AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        }
        return AXIsProcessTrusted()
    }

    static func read(settings: AppSettings) -> Result {
        guard isTrusted(prompt: false) else { return .permissionMissing }
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier else {
            return .unavailable
        }

        let bundleIdentifier = app.bundleIdentifier ?? ""
        if settings.denylistedBundleIdentifiers.contains(where: {
            $0.caseInsensitiveCompare(bundleIdentifier) == .orderedSame
        }) {
            return .denylisted(appName: app.localizedName ?? "This app")
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, 0.25)

        let focused = element(of: kAXFocusedUIElementAttribute, on: appElement)
        if let focused, isSecure(focused) { return .secureField }

        let window = element(of: kAXFocusedWindowAttribute, on: appElement)
        let windowTitle = window.flatMap { string(of: kAXTitleAttribute, on: $0) }

        if let focused {
            if let text = selection(on: focused) {
                return .selection(makeSelection(text: text, app: app, title: windowTitle, settings: settings))
            }

            // A focused element that supports AXSelectedText but currently
            // has none is authoritative. Walking other panes risks capturing
            // stale text retained by a background view.
            var probe: CFTypeRef?
            if AXUIElementCopyAttributeValue(focused, kAXSelectedTextAttribute as CFString, &probe) == .success {
                return .nothingSelected
            }
        }

        guard let window else { return .nothingSelected }
        var queue = [window]
        var visited = 0
        let deadline = ContinuousClock.now + .milliseconds(450)
        while !queue.isEmpty, visited < 80, ContinuousClock.now < deadline {
            let current = queue.removeFirst()
            visited += 1
            AXUIElementSetMessagingTimeout(current, 0.1)

            if isSecure(current) { continue }
            if let text = selection(on: current) {
                return .selection(makeSelection(text: text, app: app, title: windowTitle, settings: settings))
            }

            var childrenRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(current, kAXChildrenAttribute as CFString, &childrenRef) == .success,
               let children = childrenRef as? [AXUIElement] {
                queue.append(contentsOf: children)
            }
        }
        return .nothingSelected
    }

    private static func makeSelection(
        text: String,
        app: NSRunningApplication,
        title: String?,
        settings: AppSettings
    ) -> Selection {
        let source = SourceMetadata(
            appName: settings.captureSourceApp ? app.localizedName : nil,
            bundleIdentifier: settings.captureSourceApp ? app.bundleIdentifier : nil,
            windowTitle: settings.captureWindowTitle ? title : nil,
            url: nil
        )
        return Selection(
            text: capped(text),
            source: source,
            sourceBundleIdentifierForMapping: app.bundleIdentifier,
            sourceWindowTitleForMapping: title
        )
    }

    private static func capped(_ value: String) -> String {
        let maximum = 20_000
        guard value.count > maximum else { return value }
        return String(value.prefix(maximum)) + "…"
    }

    private static func selection(on element: AXUIElement) -> String? {
        if let text = string(of: kAXSelectedTextAttribute, on: element), !text.isEmpty {
            return text
        }

        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeRef
        ) == .success,
        let rangeRef,
        CFGetTypeID(rangeRef) == AXValueGetTypeID(),
        AXValueGetType(unsafeDowncast(rangeRef as AnyObject, to: AXValue.self)) == .cfRange else {
            return nil
        }

        var textRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXStringForRangeParameterizedAttribute as CFString,
            rangeRef,
            &textRef
        ) == .success,
        let text = textRef as? String,
        !text.isEmpty else { return nil }
        return text
    }

    private static func isSecure(_ element: AXUIElement) -> Bool {
        let role = string(of: kAXRoleAttribute, on: element)
        let subrole = string(of: kAXSubroleAttribute, on: element)
        if role == "AXSecureTextField" || subrole == "AXSecureTextField" {
            return true
        }

        var protectedRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, "AXProtectedContent" as CFString, &protectedRef) == .success,
           let protected = protectedRef as? Bool {
            return protected
        }
        return false
    }

    private static func element(of attribute: String, on parent: AXUIElement) -> AXUIElement? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(parent, attribute as CFString, &ref) == .success,
              let ref,
              CFGetTypeID(ref) == AXUIElementGetTypeID() else { return nil }
        let element = unsafeDowncast(ref as AnyObject, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(element, 0.25)
        return element
    }

    private static func string(of attribute: String, on element: AXUIElement) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success else {
            return nil
        }
        return ref as? String
    }
}
