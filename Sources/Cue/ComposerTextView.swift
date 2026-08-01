import AppKit
import SwiftUI

extension Notification.Name {
    static let cueFocusComposer = Notification.Name("CueFocusComposer")
}

private final class CueComposerNSTextView: NSTextView {
    var onCommit: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let isReturn = event.keyCode == 36 || event.keyCode == 76
        if isReturn, modifiers == .command {
            onCommit?()
            return
        }
        super.keyDown(with: event)
    }
}

/// AppKit-backed composer adapted from Nickel's MIT-licensed responder
/// pattern. Cue commits on Command-Return and keeps plain/Shift-Return for
/// multiline prompt authoring.
struct ComposerTextView: NSViewRepresentable {
    @Binding var text: String
    var onCommit: () -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.borderType = .noBorder

        let textView = CueComposerNSTextView()
        textView.delegate = context.coordinator
        textView.onCommit = onCommit
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: 14)
        textView.textColor = .labelColor
        textView.insertionPointColor = .controlAccentColor
        textView.textContainerInset = NSSize(width: 0, height: 3)
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.string = text
        textView.setAccessibilityLabel("Prompt composer")
        textView.setAccessibilityHelp("Type a prompt. Press Command Return to queue it.")
        scrollView.documentView = textView
        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? CueComposerNSTextView else { return }
        if textView.string != text { textView.string = text }
        textView.onCommit = onCommit
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private let text: Binding<String>
        weak var textView: NSTextView?

        init(text: Binding<String>) {
            self.text = text
            super.init()
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(focusComposer),
                name: .cueFocusComposer,
                object: nil
            )
        }

        deinit { NotificationCenter.default.removeObserver(self) }

        @objc private func focusComposer() {
            guard let textView else { return }
            textView.window?.makeFirstResponder(textView)
            textView.moveToEndOfDocument(nil)
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}
