import Cocoa

/// The window for writing the notes grammar cleanup draws on.
///
/// Says plainly what happens to them: they sit in this Mac's preferences as plain
/// text, and they go to xAI with each cleanup request. Their content is never
/// written to the log — only how long they are.
enum NotesPrompt {

    /// Returns true if the notes were saved.
    @discardableResult
    static func show(cleanupIsOn: Bool, snapshotTo png: String? = nil) -> Bool {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Vocabulary & notes"
        alert.informativeText = """
            Names, products and terms Quill tends to mishear — one per line — or a line about what you \
            work on. When “Clean up grammar” is on, Quill uses this to spell them your way, so \
            “cooper nettys” can become “Kubernetes”.

            Kept on this Mac as plain text and sent to xAI with each cleanup request, together with \
            what you said. Nothing from your screen or other apps is read or shared.\(cleanupIsOn ? "" : "\n\nClean up grammar is currently off.")
            """
        alert.alertStyle = .informational

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 380, height: 150))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let textView = NSTextView(frame: scroll.contentView.bounds)
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.font = .systemFont(ofSize: 13)
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.string = ContextNotes.text
        scroll.documentView = textView
        alert.accessoryView = scroll

        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        if !ContextNotes.isEmpty { alert.addButton(withTitle: "Clear") }

        alert.window.initialFirstResponder = textView

        // Test hook: write the dialog's own pixels to a file, then dismiss it.
        // A run-loop timer, because queued blocks do not run while a modal is up.
        if let png {
            let timer = Timer(timeInterval: 0.8, repeats: false) { _ in
                if let view = alert.window.contentView?.superview ?? alert.window.contentView,
                   let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: png))
                }
                NSApp.abortModal()
            }
            RunLoop.main.add(timer, forMode: .common)
        }

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            ContextNotes.text = textView.string
            Log.write("notes saved — \(ContextNotes.text.count) chars")
            return true
        case .alertThirdButtonReturn:
            ContextNotes.text = ""
            Log.write("notes cleared")
            return true
        default:
            return false
        }
    }
}
