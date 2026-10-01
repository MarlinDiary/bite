import Foundation
import Testing
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif
import BiteKit
@testable import Bite

/// Random edits, the way people make them, on random pages. After every one the page must be in
/// a state it could have been loaded in:
/// - each line's attributes are the same all along it;
/// - list levels, numbers and places in runs of code or quote lines are as worked out afresh;
/// - it's styled as a fresh load would style it;
/// - what it shows is what it saves, so opening the saved page again shows the same.
///
/// At the end of each run, undoing everything must give back the page as it started, and
/// redoing everything the page as it ended (with all of its edits redone).
///
/// `TEST_RUNNER_FUZZ_SEEDS`, `TEST_RUNNER_FUZZ_STEPS` and `TEST_RUNNER_FUZZ_FIRST_SEED` given to
/// `xcodebuild test` run it longer, or on other pages and edits.
struct EditorFuzzTests {
    private struct Random {
        var state: UInt64

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }

        mutating func int(_ range: ClosedRange<Int>) -> Int {
            range.lowerBound + Int(next() % UInt64(range.count))
        }

        mutating func chance(_ oneIn: Int) -> Bool {
            int(1...oneIn) == 1
        }

        mutating func pick<T>(_ items: [T]) -> T {
            items[int(0...(items.count - 1))]
        }
    }

    /// A long page with a bit of everything, so an edit's effects can reach past what's on
    /// either side of it, or stop short of the end.
    private static let longPage = """
        # Plan
        Some **bold**, some *italic*, some `code` and ~~struck~~ text.

        1. first
        2. second
            a. nested
            b. nested
                - deep
        3. third
        - [ ] todo
        - [x] done
        > quote one
        > quote two
        plain
        > another quote
        ```swift
        let x = 1

        let y = 2
        ```
        ---
        a. letter
        b. letter
        I. roman
        II. roman
        ## Section
        - bullet
            - child
        - bullet
        1. again
        2. again
        text at the end
        """

    private static let pages = [
        "1. a\n2. b\n3. c\n4. d",
        "- a\n    - b\n        - c\n- d",
        "a. x\nb. y\n\nI. p\nII. q",
        "> q1\n> q2\ntext\n> q3",
        "```\nx\ny\n```\nz",
        "- [ ] t\n- [x] u\n## h\n---\np",
        "",
        "plain\n\n1. one\n    a. two\n2. three",
        longPage,
        longPage,
    ]

    private static let typed = ["a", "b", " ", "- ", "1. ", "a. ", "i. ", "> ", "\" ", "[] ", "# ", "```", "---",
                                "**x**", "*y*", "`z`", "~~s~~", "\n", "\n", "\n", "\t", "x", "\u{4E2D}",
                                "`**c**`", "\\*e*", "\u{1D49C}_u_", "_v_", "*\u{2003}w*", "999999999. ", "\u{20BB7}"]

    private static let pasted = ["x", "- a\n- b", "1. one\n2. two", "```\ncode\n```", "> q", "a\nb", "a. p\nb. q",
                                 "**b** and *i*", "---", "# h", "- [x]\titem", "`**c**` and \\*e*", "999999998. a\nb\nc"]

    private static let actions: [FormatAction] = [.todo, .bullet, .ordered, .heading, .quote, .code, .bold, .italic,
                                                  .strikethrough, .outdent, .indent]

    // MARK: Checks

    /// What's wrong with the page, if anything.
    static func problems(in editor: EditorHarness) -> [String] {
        let storage = editor.storage
        let string = storage.string as NSString
        var problems: [String] = []
        guard storage.length > 0, string.character(at: storage.length - 1) == 0x0A else { return ["no final newline"] }
        let selection = editor.textView.selectedRange
        if NSMaxRange(selection) > storage.length - 1 { problems.append("selection \(selection) past the final newline") }

        var lines: [NSRange] = []
        var location = 0
        while location < storage.length {
            let line = string.paragraphRange(for: NSRange(location: location, length: 0))
            lines.append(line)
            location = NSMaxRange(line)
        }
        let blocks = lines.map { BlockAttributes(storage.attributes(at: $0.location, effectiveRange: nil)) }

        // The caret never rests on a divider, but for one at the very end.
        if selection.length == 0, let caretLine = lines.firstIndex(where: { NSLocationInRange(selection.location, $0) }),
           blocks[caretLine].kind == .divider, caretLine < lines.count - 1 {
            problems.append("caret on the divider on line \(caretLine)")
        }

        // Each line's own and derived attributes run the whole length of the line.
        let keys: [NSAttributedString.Key] = [.biteBlock, .biteIndent, .biteChecked, .biteNumber, .biteNumberStyle,
                                              .biteLanguage, .biteOrdinal, .biteShownStyle, .biteRunPosition]
        for (index, line) in lines.enumerated() {
            for key in keys {
                var range = NSRange()
                _ = storage.attribute(key, at: line.location, longestEffectiveRange: &range, in: line)
                if range != line { problems.append("line \(index): \(key.rawValue) changes along the line") }
            }
            let block = blocks[index]
            if !block.kind.isList, block.indent != 0 { problems.append("line \(index): indent on a \(block.kind)") }
            if block.kind != .ordered, block.number != nil || block.numberStyle != nil { problems.append("line \(index): number on a \(block.kind)") }
            if block.kind == .divider, line.length > 1 { problems.append("line \(index): a divider with text") }
            if (storage.attribute(.biteInline, at: NSMaxRange(line) - 1, effectiveRange: nil) as? Int ?? 0) != 0 {
                problems.append("line \(index): a styled line break")
            }
        }

        // Levels normalized; numbers and runs as worked out from scratch.
        let levels = ListNesting.levels(for: blocks.map { ($0.kind, $0.indent) })
        for index in lines.indices where levels[index] != blocks[index].indent {
            problems.append("line \(index): level \(blocks[index].indent), should be \(levels[index])")
        }
        let numbers = ListNumbering.numbers(for: blocks.map { ($0.kind, $0.indent, $0.number, $0.numberStyle) })
        for (index, line) in lines.enumerated() {
            let ordinal = storage.attribute(.biteOrdinal, at: line.location, effectiveRange: nil) as? Int ?? -1
            if ordinal != numbers[index]?.ordinal ?? 0 { problems.append("line \(index): number \(ordinal), should be \(numbers[index]?.ordinal ?? 0)") }
            let style = storage.attribute(.biteShownStyle, at: line.location, effectiveRange: nil) as? String ?? "?"
            if style != numbers[index]?.style?.rawValue ?? "" { problems.append("line \(index): shown style \(style)") }
            let kind = blocks[index].kind
            var position = RunPosition.single
            if kind == .code || kind == .quote {
                let previous = index > 0 && blocks[index - 1].kind == kind
                let next = index + 1 < blocks.count && blocks[index + 1].kind == kind
                position = switch (previous, next) {
                case (false, false): .single
                case (false, true): .first
                case (true, true): .middle
                case (true, false): .last
                }
            }
            if storage.attribute(.biteRunPosition, at: line.location, effectiveRange: nil) as? Int != position.rawValue {
                problems.append("line \(index): run position")
            }
        }

        // Styled as the same page would be when loaded.
        let fresh = editor.controller.styledText(for: AttributedDocument.document(from: storage))
        if fresh.string != storage.string {
            problems.append("text reads back differently")
        } else {
            var index = 0
            while index < storage.length {
                var rangeA = NSRange(), rangeB = NSRange()
                let a = storage.attributes(at: index, effectiveRange: &rangeA)
                let b = fresh.attributes(at: index, effectiveRange: &rangeB)
                let fontA = a[.font] as? PlatformFont, fontB = b[.font] as? PlatformFont
                if fontA?.fontName != fontB?.fontName || fontA?.pointSize != fontB?.pointSize {
                    problems.append("font at \(index): \(fontA?.fontName ?? "-") \(fontA?.pointSize ?? 0), fresh \(fontB?.fontName ?? "-") \(fontB?.pointSize ?? 0)")
                }
                let styleA = a[.paragraphStyle] as? NSParagraphStyle, styleB = b[.paragraphStyle] as? NSParagraphStyle
                if styleA?.headIndent != styleB?.headIndent || styleA?.paragraphSpacing != styleB?.paragraphSpacing
                    || styleA?.paragraphSpacingBefore != styleB?.paragraphSpacingBefore {
                    problems.append("paragraph style at \(index)")
                }
                if (a[.strikethroughStyle] as? Int ?? 0) != (b[.strikethroughStyle] as? Int ?? 0) { problems.append("strikethrough at \(index)") }
                if (a[.backgroundColor] == nil) != (b[.backgroundColor] == nil) { problems.append("inline code background at \(index)") }
                if (a[.foregroundColor] as? PlatformColor) != (b[.foregroundColor] as? PlatformColor) { problems.append("text color at \(index)") }
                index = min(NSMaxRange(rangeA), NSMaxRange(rangeB))
            }
        }
        problems += savingProblems(in: editor)
        return problems
    }

    /// What would come out differently if the page were saved and opened again.
    static func savingProblems(in editor: EditorHarness) -> [String] {
        let storage = editor.storage
        let shown = AttributedDocument.document(from: storage).blocks
        let markdown = MarkdownSerializer.markdown(from: BiteDocument(blocks: shown))
        let saved = MarkdownParser.parse(markdown).blocks
        guard saved.count == shown.count else { return ["saves \(saved.count) lines, shows \(shown.count): \(markdown.debugDescription)"] }
        let numbers = ListNumbering.numbers(for: saved.map { ($0.kind, $0.indent, $0.number, $0.numberStyle) })
        let string = storage.string as NSString
        var problems: [String] = []
        var location = 0
        for (index, (a, b)) in zip(shown, saved).enumerated() {
            let line = string.paragraphRange(for: NSRange(location: location, length: 0))
            location = NSMaxRange(line)
            let label = "saved line \(index) (\(markdown.components(separatedBy: "\n")[safe: index] ?? "?"))"
            guard a.kind == b.kind else {
                problems.append("\(label): \(b.kind), shows \(a.kind)")
                continue
            }
            if a.indent != b.indent { problems.append("\(label): level \(b.indent), shows \(a.indent)") }
            if a.kind == .todo, a.isChecked != b.isChecked { problems.append("\(label): checked \(b.isChecked)") }
            if a.text != b.text { problems.append("\(label): text \(b.text.debugDescription), shows \(a.text.debugDescription)") }
            // Bold and italic changing mid-word are the one thing Markdown can lose (see
            // `MarkdownSerializer.inline`).
            if !MarkdownSerializer.emphasisChangesMidWord(a.runs), MarkdownSerializer.words(a.runs) != MarkdownSerializer.words(b.runs) {
                problems.append("\(label): styles differ")
            }
            if a.kind == .ordered {
                let ordinal = storage.attribute(.biteOrdinal, at: line.location, effectiveRange: nil) as? Int
                let style = storage.attribute(.biteShownStyle, at: line.location, effectiveRange: nil) as? String ?? ""
                let label = ListNumbering.label(for: ordinal ?? 0, indent: a.indent, style: NumberStyle(rawValue: style))
                let savedLabel = numbers[index].map { ListNumbering.label(for: $0.ordinal, indent: b.indent, style: $0.style) }
                if label != savedLabel { problems.append("saved line \(index): numbered \(savedLabel ?? "-"), shows \(label)") }
            }
        }
        return problems
    }

    /// A selection or caret as the text view makes one: never inside a character, as between
    /// the two halves of a letter beyond the Basic Multilingual Plane, which UIKit won't do.
    private static func whole(_ range: NSRange, in editor: EditorHarness) -> NSRange {
        let text = editor.textView.text as NSString
        guard range.location < text.length else { return range }
        guard range.length > 0 else {
            return NSRange(location: text.rangeOfComposedCharacterSequence(at: range.location).location, length: 0)
        }
        return text.rangeOfComposedCharacterSequences(for: range)
    }

    // MARK: Running

    /// `trace` sees the page after every edit, for tracking a failure down.
    static func run(seed: UInt64, steps: Int, trace: ((String, EditorHarness) -> Void)? = nil) -> (log: [String], problems: [String])? {
        var random = Random(state: seed)
        let page = random.pick(pages)
        let editor = EditorHarness(page)
        let start = editor.markdown
        var log = ["page \(page.debugDescription)"]
        for _ in 0..<steps {
            let lines = editor.textView.text.components(separatedBy: "\n").dropLast()
            let length = max(0, editor.storage.length - 1)
            switch random.int(0...16) {
            case 0...3:
                let text = random.pick(typed)
                log.append("type \(text.debugDescription)")
                editor.type(text, separateEvents: random.chance(2))
            case 4:
                let times = random.int(1...3)
                log.append("backspace \(times)")
                editor.backspace(times)
            case 5, 6:
                let line = random.int(0...max(0, lines.count - 1))
                let lineLength = (lines.isEmpty ? 0 : (lines[line] as NSString).length)
                var column = random.chance(2) ? nil : random.int(0...lineLength)
                if let offset = column, offset < lineLength {
                    column = (lines[line] as NSString).rangeOfComposedCharacterSequence(at: offset).location
                }
                log.append("caret \(line):\(column.map(String.init) ?? "end")")
                editor.moveCaret(line: line, column: column)
            case 7:
                let from = random.int(0...length)
                let to = random.int(from...min(length, from + random.pick([2, 8, 40, 400])))
                let selection = whole(NSRange(location: from, length: to - from), in: editor)
                log.append("select \(selection.location)..<\(NSMaxRange(selection))")
                editor.textView.selectedRange = selection
            case 8:
                let action = random.pick(actions)
                log.append("button \(action)")
                editor.controller.perform(action)
            case 9:
                let text = random.pick(pasted)
                log.append("paste \(text.debugDescription)")
                editor.controller.paste(text)
            case 10:
                if random.chance(2) {
                    log.append("undo")
                    editor.undo()
                } else {
                    log.append("redo")
                    editor.redo()
                }
            case 11:
                // UIKit loses the undo step of text just typed when an input method composes over
                // a selection that takes it in, even in a plain text view, and nothing here can
                // tell it's happened. So a selection goes first, and `UIKitLostUndoTests` covers
                // what's left of that.
                if editor.textView.selectedRange.length > 0 {
                    log.append("backspace the selection")
                    editor.backspace()
                }
                log.append("compose")
                editor.compose(["w", "wo"], commit: "word")
            case 12:
                guard editor.textView.selectedRange.length > 0 else { continue }
                log.append("cut")
                editor.textView.cut(nil)
            case 13:
                let line = random.int(0...max(0, lines.count - 1))
                let location = lines.prefix(line).reduce(0) { $0 + ($1 as NSString).length + 1 }
                log.append("checkbox \(line)")
                editor.controller.toggleTodo(at: location)
            case 16:
                // A drag within the page: some text, or whole lines, with or without the line
                // break after the last one.
                var from = random.int(0...length)
                var to = random.int(from...min(length, from + random.pick([1, 5, 30])))
                if random.chance(2), !lines.isEmpty {
                    let first = random.int(0...(lines.count - 1))
                    let last = random.int(first...min(lines.count - 1, first + 2))
                    from = lines.prefix(first).reduce(0) { $0 + ($1 as NSString).length + 1 }
                    let lastEnd = lines.prefix(last + 1).reduce(0) { $0 + ($1 as NSString).length + 1 } - 1
                    to = min(length, random.chance(2) ? lastEnd : lastEnd + 1)
                }
                let dragged = whole(NSRange(location: from, length: to - from), in: editor)
                let drop = whole(NSRange(location: random.int(0...length), length: 0), in: editor).location
                log.append("drag \(dragged.location)..<\(NSMaxRange(dragged)) to \(drop)")
                editor.controller.move(dragged, to: drop)
            default:
                // Typing over a selection, Return included.
                let from = random.int(0...length)
                let to = random.int(from...min(length, from + random.pick([1, 5, 30])))
                let text = random.pick(["x", "\n", "- ", "\u{4E2D}"])
                let selection = whole(NSRange(location: from, length: to - from), in: editor)
                log.append("select \(selection.location)..<\(NSMaxRange(selection)), type \(text.debugDescription)")
                editor.textView.selectedRange = selection
                editor.type(text)
            }
            // Each edit is its own event, as on a phone. It also lets the keyboard's own work run:
            // without it, the keyboard could wait for the spelling checker forever.
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.001))
            trace?(log.last ?? "", editor)
            let problems = problems(in: editor)
            if !problems.isEmpty { return (log, problems) }
        }

        // Undo everything, then redo it. First redo whatever the run left undone, which redoing
        // everything would bring back too.
        while editor.textView.undoManager?.canRedo == true {
            editor.redo()
        }
        let afterRedoingTheRest = problems(in: editor)
        if !afterRedoingTheRest.isEmpty { return (log + ["redo the rest"], afterRedoingTheRest) }
        let end = editor.markdown
        var undos = 0
        while editor.textView.undoManager?.canUndo == true, undos < 5000 {
            editor.undo()
            undos += 1
            trace?("undo \(undos)", editor)
        }
        log.append("undo all (\(undos))")
        if editor.markdown != start {
            return (log, ["undoing everything gives \(editor.markdown.debugDescription), started as \(start.debugDescription)"])
        }
        let afterUndo = problems(in: editor)
        if !afterUndo.isEmpty { return (log, afterUndo) }
        var redos = 0
        while editor.textView.undoManager?.canRedo == true, redos < 5000 {
            editor.redo()
            redos += 1
            trace?("redo \(redos)", editor)
        }
        log.append("redo all (\(redos))")
        if editor.markdown != end {
            return (log, ["redoing everything gives \(editor.markdown.debugDescription), ended as \(end.debugDescription)"])
        }
        let afterRedo = problems(in: editor)
        return afterRedo.isEmpty ? nil : (log, afterRedo)
    }

    @Test func randomEditsKeepThePageSound() {
        let environment = ProcessInfo.processInfo.environment
        // Each edit lets the run loop turn, as between keystrokes on a phone. This many runs take
        // a few seconds; `TEST_RUNNER_FUZZ_SEEDS=300` runs more.
        let seeds = Int(environment["FUZZ_SEEDS"] ?? "") ?? 40
        let steps = Int(environment["FUZZ_STEPS"] ?? "") ?? 25
        let firstSeed = Int(environment["FUZZ_FIRST_SEED"] ?? "") ?? 1
        var failures: [String] = []
        for seed in firstSeed..<(firstSeed + seeds) {
            if let failure = Self.run(seed: UInt64(seed), steps: steps) {
                failures.append("seed \(seed): \(failure.problems.prefix(3).joined(separator: "; "))\n  " + failure.log.joined(separator: "\n  "))
            }
            if failures.count >= 8 { break }
        }
        #expect(failures.isEmpty, "\(failures.joined(separator: "\n"))")
        for failure in failures { print("FUZZ", failure) }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

/// UIKit loses the undo step of text just typed when an input method composes over a selection
/// that takes it in; a plain `UITextView` does the same. The steps before it then point at text
/// that has moved, and must not be applied there.
struct UIKitLostUndoTests {
    @Test func undoingPastALostStepLeavesThePageSound() {
        let editor = EditorHarness("1. ab\n2. cd")
        editor.moveCaret(line: 0)
        editor.controller.perform(.bullet)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.001))
        editor.type(">", separateEvents: true)
        editor.type(" ", separateEvents: true)
        // "b> ", taking in what was just typed.
        editor.textView.selectedRange = NSRange(location: 1, length: 3)
        editor.compose(["w", "wo"], commit: "word")
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.001))
        #expect(editor.markdown == "- aword\n1. cd")
        for _ in 0..<10 where editor.textView.undoManager?.canUndo == true {
            editor.undo()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.001))
        }
        #if canImport(UIKit)
        // The typed "> " stays, as it would in any text view; the line isn't split.
        #expect(editor.markdown == "- ab> \n1. cd")
        #else
        // AppKit keeps every step, so undo goes all the way back.
        #expect(editor.markdown == "1. ab\n2. cd")
        #endif
        #expect(EditorFuzzTests.problems(in: editor).isEmpty)
    }
}
