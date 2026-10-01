#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif
@testable import Bite

/// Drives a real editor the way a person does: each character is its own keystroke, down the
/// same path as typing. On the phone that's `UIKeyInput`, asking the delegate first as the
/// keyboard does; on a Mac it's AppKit's own key handling, which asks the delegate itself.
final class EditorHarness {
    let controller: EditorController
    #if canImport(UIKit)
    let window: UIWindow
    #else
    let window: NSWindow
    #endif

    var textView: BiteTextView { controller.textView }
    /// The page as Markdown, without the final newline.
    var markdown: String { controller.markdownForTesting }
    var caret: Int { textView.selectedRange.location }

    var storage: NSTextStorage {
        #if canImport(UIKit)
        textView.textStorage
        #else
        textView.textStorage!
        #endif
    }

    /// Copies and pastes go through a pasteboard of the tests' own, never the person's.
    private static let privateClipboard: Void = {
        #if canImport(UIKit)
        Clipboard.board = UIPasteboard.withUniqueName()
        #else
        Clipboard.board = NSPasteboard.withUniqueName()
        #endif
    }()

    init(_ markdown: String = "") {
        Self.privateClipboard
        controller = EditorController(dot: 0, accent: .systemRed)
        let frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        #if canImport(UIKit)
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            window = UIWindow(windowScene: scene)
        } else {
            window = UIWindow(frame: frame)
        }
        window.frame = frame
        textView.frame = window.bounds
        window.addSubview(textView)
        Self.show(window)
        #else
        window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = Self.scrollView(for: textView, in: frame)
        #endif
        controller.load(markdown: markdown)
        controller.focus()
    }

    #if canImport(UIKit)
    /// Puts a test window on screen. A key window takes the system keyboard along with the text
    /// view, and the keyboard's own work after every edit made the tests five times slower; the
    /// text view is first responder either way. `TEST_RUNNER_KEY_WINDOW=1` makes it key, for a
    /// last check that the tests pass with the keyboard there too. Run that one test at a time
    /// (`-parallel-testing-enabled NO`): only one window is key, so a test waiting on the run
    /// loop lost its keyboard to the tests run meanwhile.
    static func show(_ window: UIWindow) {
        if ProcessInfo.processInfo.environment["KEY_WINDOW"] != nil {
            window.makeKeyAndVisible()
        } else {
            window.isHidden = false
        }
    }
    #else
    /// The text view in a scroll view, as in the panel.
    private static func scrollView(for textView: BiteTextView, in frame: CGRect) -> NSScrollView {
        let scrollView = NSScrollView(frame: frame)
        scrollView.hasVerticalScroller = true
        textView.frame = NSRect(origin: .zero, size: scrollView.contentSize)
        textView.minSize = NSSize(width: 0, height: scrollView.contentSize.height)
        scrollView.documentView = textView
        return scrollView
    }
    #endif

    /// Another page in the same window, as the pages share one.
    func addPage(_ page: EditorController) {
        #if canImport(UIKit)
        page.textView.frame = window.bounds
        window.addSubview(page.textView)
        #else
        window.contentView?.addSubview(Self.scrollView(for: page.textView, in: window.contentView?.bounds ?? .zero))
        #endif
    }

    /// Ends editing, as when the keyboard goes away or another window is clicked.
    func endEditing() {
        #if canImport(UIKit)
        textView.resignFirstResponder()
        #else
        window.makeFirstResponder(nil)
        #endif
    }

    /// Types each character as a separate keystroke. `\n` is Return and `\t` is Tab.
    ///
    /// On the phone, it asks the text view's delegate before every change, as the keyboard does;
    /// calling `insertText` directly skips that check, and the check is where the editing rules run.
    func type(_ text: String, separateEvents: Bool = false) {
        for character in text {
            let string = String(character)
            #if canImport(UIKit)
            if keyboardMayChange(textView.selectedRange, to: string) {
                textView.insertText(string)
            }
            #else
            switch string {
            case "\n": textView.doCommand(by: #selector(NSResponder.insertNewline(_:)))
            case "\t": textView.doCommand(by: #selector(NSResponder.insertTab(_:)))
            default: textView.insertText(string, replacementRange: Self.noRange)
            }
            #endif
            if separateEvents {
                // Every keystroke is its own event, and undo groups close between events. Tests
                // run synchronously, so let the run loop turn once.
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.001))
            }
        }
    }

    func backspace(_ times: Int = 1) {
        for _ in 0..<times {
            #if canImport(UIKit)
            let selection = textView.selectedRange
            let deleted = selection.length > 0 ? selection : NSRange(location: max(0, selection.location - 1), length: min(1, selection.location))
            if deleted.length == 0 || keyboardMayChange(deleted, to: "") {
                textView.deleteBackward()
            }
            #else
            textView.doCommand(by: #selector(NSResponder.deleteBackward(_:)))
            #endif
        }
    }

    /// Types through an input method: each step replaces the marked (still composing) text, and
    /// `commit` is what the chosen candidate turns it into, often shorter than what was spelled.
    ///
    /// On the phone, the keyboard commits by marking the candidate and then unmarking it.
    /// Inserting over marked text instead, as this once did, leaves UIKit's own undo of it broken:
    /// undoing crashed even in a plain `UITextView`, which never happens with a real keyboard. A
    /// Mac's input methods commit by inserting the candidate over the marked text.
    func compose(_ steps: [String], commit: String) {
        #if canImport(UIKit)
        for step in steps + [commit] where keyboardMayChange(markedRange ?? textView.selectedRange, to: step) {
            textView.setMarkedText(step, selectedRange: NSRange(location: (step as NSString).length, length: 0))
        }
        textView.unmarkText()
        #else
        for step in steps {
            textView.setMarkedText(step, selectedRange: NSRange(location: (step as NSString).length, length: 0), replacementRange: Self.noRange)
        }
        textView.insertText(commit, replacementRange: Self.noRange)
        #endif
    }

    /// An input method's marked text, still being composed.
    func startComposing(_ text: String) {
        #if canImport(UIKit)
        if keyboardMayChange(markedRange ?? textView.selectedRange, to: text) {
            textView.setMarkedText(text, selectedRange: NSRange(location: (text as NSString).length, length: 0))
        }
        #else
        textView.setMarkedText(text, selectedRange: NSRange(location: (text as NSString).length, length: 0), replacementRange: Self.noRange)
        #endif
    }

    #if canImport(UIKit)
    private var markedRange: NSRange? {
        textView.markedTextRange.map {
            NSRange(location: textView.offset(from: textView.beginningOfDocument, to: $0.start),
                    length: textView.offset(from: $0.start, to: $0.end))
        }
    }

    private func keyboardMayChange(_ range: NSRange, to text: String) -> Bool {
        textView.delegate?.textView?(textView, shouldChangeTextIn: range, replacementText: text) ?? true
    }
    #else
    /// "No range": AppKit's text input then works on the selection.
    private static let noRange = NSRange(location: NSNotFound, length: 0)
    #endif

    /// Moves the caret like a tap: to `column` (UTF-16) of `line`, or to the end of the line.
    /// Lines are counted in the text view, where block markers aren't characters.
    func moveCaret(line: Int, column: Int? = nil) {
        textView.selectedRange = NSRange(location: location(line: line, column: column), length: 0)
        // The text view resets its typing attributes whenever the caret moves, and they can come
        // from the line above. Typed text has to come out right regardless.
        textView.typingAttributes = [:]
    }

    func select(from start: (line: Int, column: Int), to end: (line: Int, column: Int)) {
        let startLocation = location(line: start.line, column: start.column)
        let endLocation = location(line: end.line, column: end.column)
        textView.selectedRange = NSRange(location: startLocation, length: endLocation - startLocation)
    }

    func selectAll() {
        textView.selectedRange = NSRange(location: 0, length: (textView.text as NSString).length)
    }

    /// Replaces text the way autocorrect does: through `UITextInput` on the phone, as an
    /// insertion over a range on a Mac.
    func replace(line: Int, columns: Range<Int>, with text: String) {
        let start = location(line: line, column: columns.lowerBound)
        #if canImport(UIKit)
        guard let from = textView.position(from: textView.beginningOfDocument, offset: start),
              let to = textView.position(from: from, offset: columns.count),
              let range = textView.textRange(from: from, to: to),
              keyboardMayChange(NSRange(location: start, length: columns.count), to: text) else { return }
        textView.replace(range, withText: text)
        #else
        textView.insertText(text, replacementRange: NSRange(location: start, length: columns.count))
        #endif
    }

    func undo() {
        textView.undoManager?.undo()
    }

    func redo() {
        textView.undoManager?.redo()
    }

    /// The nesting level the editor holds for `line`, whatever the Markdown makes of it.
    func indent(line: Int) -> Int {
        storage.attribute(.biteIndent, at: location(line: line, column: 0), effectiveRange: nil) as? Int ?? 0
    }

    private func location(line: Int, column: Int?) -> Int {
        let lines = textView.text.components(separatedBy: "\n")
        var location = 0
        for index in 0..<line {
            location += (lines[index] as NSString).length + 1
        }
        return location + (column ?? (lines[line] as NSString).length)
    }
}

#if !canImport(UIKit)
/// UIKit's names, so the tests read the same on both.
extension BiteTextView {
    var text: String {
        string
    }

    var attributedText: NSAttributedString {
        attributedString()
    }
}
#endif
