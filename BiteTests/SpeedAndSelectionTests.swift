import Testing
import UIKit
import BiteKit
@testable import Bite

/// Nothing reaches past the page's final newline.
struct FinalNewlineSelectionTests {
    @Test func selectingEverythingStopsBeforeIt() {
        let editor = EditorHarness("ab\ncd")
        let textView = editor.textView
        textView.selectedTextRange = textView.textRange(from: textView.beginningOfDocument, to: textView.endOfDocument)
        #expect(textView.selectedRange == NSRange(location: 0, length: 5))
    }

    @Test func aRangeThroughItIsDrawnWithoutIt() {
        let editor = EditorHarness("ab\ncd")
        let textView = editor.textView
        let start = textView.position(from: textView.beginningOfDocument, offset: 3)!
        let withNewline = textView.textRange(from: start, to: textView.endOfDocument)!
        let withoutNewline = textView.textRange(from: start, to: textView.position(from: start, offset: 2)!)!
        #expect(textView.selectionRects(for: withNewline).map(\.rect) == textView.selectionRects(for: withoutNewline).map(\.rect))
    }

    @Test func aPointBelowTheTextLandsAtTheEndOfTheLastLine() {
        let editor = EditorHarness("ab\ncd")
        let textView = editor.textView
        let position = textView.closestPosition(to: CGPoint(x: 300, y: 2000))!
        #expect(textView.offset(from: textView.beginningOfDocument, to: position) == 5)
    }
}

/// Notes go down as typed.
struct TypingAsTypedTests {
    @Test func noAutocorrection() {
        let editor = EditorHarness()
        #expect(editor.textView.autocorrectionType == .no)
        #expect(editor.textView.inlinePredictionType == .no)
    }

    /// Code turning autocorrection off and on again for its own sake mustn't turn it back on.
    @Test func leavingCodeKeepsItOff() {
        let editor = EditorHarness("```\nx\n```\ny")
        editor.moveCaret(line: 0)
        editor.moveCaret(line: 1)
        #expect(editor.textView.autocorrectionType == .no)
    }
}

/// The page goes out as Markdown once typing pauses, worked out off the main thread.
struct ReportTests {
    @Test func aPauseReportsTheMarkdown() async {
        let editor = EditorHarness("a")
        var reported: [String] = []
        editor.controller.onChange = { reported.append($0) }
        editor.moveCaret(line: 0)
        editor.type("b")
        #expect(reported.isEmpty)
        // Other tests share the main thread, so allow for some waiting.
        for _ in 0..<100 where reported.isEmpty {
            try? await Task.sleep(for: .milliseconds(50))
        }
        #expect(reported == ["ab\n"])
    }

    @Test func savingReportsAtOnce() {
        let editor = EditorHarness("a")
        var reported: [String] = []
        editor.controller.onChange = { reported.append($0) }
        editor.moveCaret(line: 0)
        editor.type("b")
        editor.controller.reportPendingChange()
        #expect(reported == ["ab\n"])
        // Nothing more to report, and the report already on its way is dropped.
        editor.controller.reportPendingChange()
        #expect(reported == ["ab\n"])
    }

    @Test func emptinessIsReportedStraightAway() {
        let editor = EditorHarness("a")
        var empty: [Bool] = []
        editor.controller.onEmptyChange = { empty.append($0) }
        editor.moveCaret(line: 0)
        editor.backspace()
        #expect(empty == [true])
        editor.type("c")
        #expect(empty == [true, false])
    }

    @Test func aReportFromBeforeALoadIsDropped() async {
        let editor = EditorHarness("a")
        var reported: [String] = []
        editor.controller.onChange = { reported.append($0) }
        editor.moveCaret(line: 0)
        editor.type("b")
        editor.controller.load(markdown: "fresh")
        try? await Task.sleep(for: .milliseconds(600))
        #expect(reported.isEmpty)
    }
}

/// A loaded page is styled all at once; it has to come out as if every line had been styled
/// by hand.
struct LoadedStyleTests {
    @Test func loadingMatchesStylingLineByLine() {
        let markdown = """
        # Title
        Some **bold** and *italic* text, with `code`.
        - item
            - nested
        1. one
        2. two
        > quote
        > more
        ```swift
        let x = 1
        ```
        ---
        - [x] done
        Chinese italic: *\\u{4E2D}\\u{6587}*
        """
        let loaded = EditorHarness(markdown)
        let typed = EditorHarness("")
        typed.controller.paste(markdown)
        let a = loaded.textView.textStorage, b = typed.textView.textStorage
        #expect(a.string == b.string)
        var location = 0
        while location < a.length {
            var rangeA = NSRange(), rangeB = NSRange()
            let attributesA = a.attributes(at: location, effectiveRange: &rangeA)
            let attributesB = b.attributes(at: location, effectiveRange: &rangeB)
            for key: NSAttributedString.Key in [.biteBlock, .biteIndent, .biteInline, .biteOrdinal, .biteRunPosition, .font, .foregroundColor, .strikethroughStyle, .backgroundColor] {
                #expect(String(describing: attributesA[key]) == String(describing: attributesB[key]), "\(key.rawValue) at \(location)")
            }
            let styleA = attributesA[.paragraphStyle] as? NSParagraphStyle, styleB = attributesB[.paragraphStyle] as? NSParagraphStyle
            #expect(styleA?.headIndent == styleB?.headIndent && styleA?.paragraphSpacing == styleB?.paragraphSpacing
                    && styleA?.paragraphSpacingBefore == styleB?.paragraphSpacingBefore, "paragraph style at \(location)")
            location = min(NSMaxRange(rangeA), NSMaxRange(rangeB))
        }
    }
}

/// Edits reach only as far as they can matter, however long the page.
struct LongPageEditTests {
    static let page = (0..<3000).map { i -> String in
        switch i % 10 {
        case 3: "- item \(i)"
        case 4: "    - nested \(i)"
        case 5: "1. number \(i)"
        case 6: "2. number \(i)"
        case 8: "> quote \(i)"
        default: "Line \(i) with some words in it"
        }
    }.joined(separator: "\n")

    /// A line typed into the middle of a list renumbers the rest of that list only.
    @Test func numbersFollowAnInsertedItem() {
        let editor = EditorHarness("1. a\n2. b\n3. c\n\n1. x\n2. y")
        editor.moveCaret(line: 0)
        editor.type("\n")
        editor.type("n")
        #expect(editor.markdown == "1. a\n2. n\n3. b\n4. c\n\n1. x\n2. y")
    }

    /// Two lists become one when the line between them goes.
    @Test func joiningTwoListsNumbersThemAsOne() {
        let editor = EditorHarness("1. a\n2. b\ntext\n1. c\n2. d")
        editor.moveCaret(line: 2)
        editor.backspace(4)
        editor.controller.perform(.ordered)
        #expect(editor.markdown == "1. a\n2. b\n3.\n4. c\n5. d")
    }

    /// Splitting a list starts the second part over.
    @Test func splittingAListStartsTheRestOver() {
        let editor = EditorHarness("1. a\n2. b\n3. c\n4. d")
        editor.moveCaret(line: 1)
        editor.controller.perform(.ordered)
        #expect(editor.markdown == "1. a\nb\n1. c\n2. d")
    }

    /// A quote line's neighbours see it change.
    @Test func quoteRunsFollowAnEditNextToThem() {
        let editor = EditorHarness("> a\n> b\n> c")
        editor.moveCaret(line: 1)
        editor.controller.perform(.quote)
        let storage = editor.textView.textStorage
        let positions = [0, 2, 4].map { storage.attribute(.biteRunPosition, at: $0, effectiveRange: nil) as? Int }
        #expect(positions == [RunPosition.single.rawValue, RunPosition.single.rawValue, RunPosition.single.rawValue])
    }

    @Test func structuralEditsStayQuick() {
        let editor = EditorHarness(Self.page)
        editor.moveCaret(line: 1500)
        editor.type("x")
        let clock = ContinuousClock()
        // Leaving out the keyboard's own bookkeeping, which takes the same time on any page.
        var times: [Duration] = []
        for _ in 0..<3 {
            times.append(clock.measure { editor.type("\n") })
            times.append(clock.measure { editor.backspace() })
        }
        #expect(times.sorted()[times.count / 2] < .milliseconds(40))
    }
}

struct NoSmartDeleteTests {
    /// Smart delete took the line break too, and the code line was gone.
    @Test func emptyingTheLastCodeLineKeepsTheLine() {
        let editor = EditorHarness("- a\n```\na\nb c\n```\n-")
        editor.textView.selectedRange = NSRange(location: 4, length: 3)
        editor.backspace()
        editor.type("w")
        #expect(editor.markdown == "- a\n```\na\nw\n```\n-")
    }
}

/// Text typed over lines leaves one line of the first one's kind. Redone, it has to come back
/// the same, the rest of the last line included.
struct RedoOfJoinTests {
    @Test func aLineTypedAfterAJoinComesBackPlain() {
        let editor = EditorHarness("p1\n1. a\n2. b")
        // From inside "p1" to the end of "b".
        editor.textView.selectedRange = NSRange(location: 1, length: (editor.textView.text as NSString).length - 2)
        editor.type("x", separateEvents: true)
        editor.type("\n", separateEvents: true)
        let typed = editor.markdown
        #expect(typed == "px\n")
        while editor.textView.undoManager?.canUndo == true { editor.undo() }
        #expect(editor.markdown == "p1\n1. a\n2. b")
        while editor.textView.undoManager?.canRedo == true { editor.redo() }
        #expect(editor.markdown == typed)
    }
}
