import UIKit
@testable import Bite

/// Drives a real editor the way a person does: each character is its own keystroke through
/// `UIKeyInput`, so every test goes down the same delegate path as typing on the phone.
final class EditorHarness {
    let controller: EditorController
    let window: UIWindow

    var textView: BiteTextView { controller.textView }
    /// The page as Markdown, without the final newline.
    var markdown: String { controller.markdownForTesting }
    var caret: Int { textView.selectedRange.location }

    init(_ markdown: String = "") {
        controller = EditorController(dot: 0, accent: .systemRed)
        let frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            window = UIWindow(windowScene: scene)
        } else {
            window = UIWindow(frame: frame)
        }
        window.frame = frame
        textView.frame = window.bounds
        window.addSubview(textView)
        Self.show(window)
        controller.load(markdown: markdown)
        controller.focus()
    }

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

    /// Types each character as a separate keystroke. `\n` is Return and `\t` is Tab.
    ///
    /// Like the system keyboard, it asks the text view's delegate before every change; calling
    /// `insertText` directly skips that check, and the check is where the editing rules run.
    func type(_ text: String, separateEvents: Bool = false) {
        for character in text {
            let string = String(character)
            if keyboardMayChange(textView.selectedRange, to: string) {
                textView.insertText(string)
            }
            if separateEvents {
                // On a phone every keystroke is its own event, and undo groups close between
                // events. Tests run synchronously, so let the run loop turn once.
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.001))
            }
        }
    }

    func backspace(_ times: Int = 1) {
        for _ in 0..<times {
            let selection = textView.selectedRange
            let deleted = selection.length > 0 ? selection : NSRange(location: max(0, selection.location - 1), length: min(1, selection.location))
            if deleted.length == 0 || keyboardMayChange(deleted, to: "") {
                textView.deleteBackward()
            }
        }
    }

    /// Types through an input method: each step replaces the marked (still composing) text, and
    /// `commit` is what the chosen candidate turns it into, often shorter than what was spelled.
    ///
    /// The keyboard commits by marking the candidate and then unmarking it. Inserting over marked
    /// text instead, as this once did, leaves UIKit's own undo of it broken: undoing crashed even
    /// in a plain `UITextView`, which never happens with a real keyboard.
    func compose(_ steps: [String], commit: String) {
        for step in steps + [commit] where keyboardMayChange(markedRange ?? textView.selectedRange, to: step) {
            textView.setMarkedText(step, selectedRange: NSRange(location: (step as NSString).length, length: 0))
        }
        textView.unmarkText()
    }

    /// An input method's marked text, still being composed.
    func startComposing(_ text: String) {
        if keyboardMayChange(markedRange ?? textView.selectedRange, to: text) {
            textView.setMarkedText(text, selectedRange: NSRange(location: (text as NSString).length, length: 0))
        }
    }

    private var markedRange: NSRange? {
        textView.markedTextRange.map {
            NSRange(location: textView.offset(from: textView.beginningOfDocument, to: $0.start),
                    length: textView.offset(from: $0.start, to: $0.end))
        }
    }

    private func keyboardMayChange(_ range: NSRange, to text: String) -> Bool {
        textView.delegate?.textView?(textView, shouldChangeTextIn: range, replacementText: text) ?? true
    }

    /// Moves the caret like a tap: to `column` (UTF-16) of `line`, or to the end of the line.
    /// Lines are counted in the text view, where block markers aren't characters.
    func moveCaret(line: Int, column: Int? = nil) {
        textView.selectedRange = NSRange(location: location(line: line, column: column), length: 0)
        // UIKit resets its typing attributes whenever the caret moves, and they can come from
        // the line above. Typed text has to come out right regardless.
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

    /// Replaces text the way autocorrect does, through `UITextInput`.
    func replace(line: Int, columns: Range<Int>, with text: String) {
        let start = location(line: line, column: columns.lowerBound)
        guard let from = textView.position(from: textView.beginningOfDocument, offset: start),
              let to = textView.position(from: from, offset: columns.count),
              let range = textView.textRange(from: from, to: to),
              keyboardMayChange(NSRange(location: start, length: columns.count), to: text) else { return }
        textView.replace(range, withText: text)
    }

    func undo() {
        textView.undoManager?.undo()
    }

    func redo() {
        textView.undoManager?.redo()
    }

    /// The nesting level the editor holds for `line`, whatever the Markdown makes of it.
    func indent(line: Int) -> Int {
        textView.textStorage.attribute(.biteIndent, at: location(line: line, column: 0), effectiveRange: nil) as? Int ?? 0
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
