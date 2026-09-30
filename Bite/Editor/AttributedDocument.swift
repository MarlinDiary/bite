import UIKit
import BiteKit

/// Converts between `BiteDocument` and the attributed text inside the editor.
///
/// In the editor every line ends with a newline, including the last one. That final newline
/// is never selectable; it's there so an empty last line (say, a fresh to-do) still has a
/// character to carry its block attributes.
nonisolated enum AttributedDocument {
    /// Only block and inline attributes are set; the editor derives the display attributes.
    static func attributedString(from document: BiteDocument) -> NSMutableAttributedString {
        attributedString(blocks: document.blocks.isEmpty ? [Block()] : document.blocks, terminated: true)
    }

    static func attributedString(blocks: [Block], terminated: Bool) -> NSMutableAttributedString {
        let result = NSMutableAttributedString()
        for (index, block) in blocks.enumerated() {
            let lineAttributes = BlockAttributes(block).dictionary
            for run in block.runs {
                var attributes = lineAttributes
                attributes[.biteInline] = block.kind == .code ? 0 : run.style.rawValue
                result.append(NSAttributedString(string: run.text, attributes: attributes))
            }
            if terminated || index < blocks.count - 1 {
                var attributes = lineAttributes
                attributes[.biteInline] = 0
                result.append(NSAttributedString(string: "\n", attributes: attributes))
            }
        }
        return result
    }

    /// Reads the lines touching `range` back into blocks. A partial line keeps its line's kind.
    /// Ordered items carry the number they show and how it's written, so part of a list copies
    /// as it looks.
    static func document(from text: NSAttributedString, in range: NSRange? = nil) -> BiteDocument {
        let string = text.string as NSString
        let range = range ?? NSRange(location: 0, length: string.length)
        let end = NSMaxRange(range)
        var blocks: [Block] = []
        var location = range.location
        while location < end {
            let line = string.paragraphRange(for: NSRange(location: location, length: 0))
            let contentEnd = min(end, contentRange(of: line, in: string).upperBound)
            let lineAttributes = BlockAttributes(text.attributes(at: line.location, effectiveRange: nil))
            var runs: [InlineRun] = []
            if contentEnd > location {
                let content = NSRange(location: location, length: contentEnd - location)
                text.enumerateAttribute(.biteInline, in: content) { value, runRange, _ in
                    runs.append(InlineRun(string.substring(with: runRange), style: InlineStyle(rawValue: value as? Int ?? 0)))
                }
            }
            let shown = text.attribute(.biteOrdinal, at: line.location, effectiveRange: nil) as? Int
            let shownStyle = (text.attribute(.biteShownStyle, at: line.location, effectiveRange: nil) as? String).flatMap(NumberStyle.init(rawValue:))
            blocks.append(Block(kind: lineAttributes.kind, indent: lineAttributes.indent, isChecked: lineAttributes.isChecked,
                                number: shown ?? lineAttributes.number, numberStyle: shownStyle ?? lineAttributes.numberStyle,
                                language: lineAttributes.language, runs: runs))
            location = NSMaxRange(line)
        }
        return BiteDocument(blocks: blocks)
    }

    /// The line without its trailing newline.
    static func contentRange(of line: NSRange, in string: NSString) -> Range<Int> {
        var end = NSMaxRange(line)
        if end > line.location, string.character(at: end - 1) == 0x0A {
            end -= 1
        }
        return line.location..<end
    }
}

/// A page's text at one moment, to read back as Markdown on another thread. The text must not
/// change afterwards: an immutable copy, or the text storage itself while on the main thread.
nonisolated struct PageSnapshot: @unchecked Sendable {
    let text: NSAttributedString

    func markdown() -> String {
        MarkdownSerializer.markdown(from: AttributedDocument.document(from: text))
    }
}
