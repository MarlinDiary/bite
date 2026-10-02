import Foundation

/// What a page holds, counted in its text as it reads, without the Markdown or the bullets,
/// numbers and boxes drawn in front of lines.
public struct PageStatistics: Sendable, Hashable {
    /// Words as the system tells them apart, so a number is a word and a dash isn't.
    public var words = 0
    /// Spaces included; the breaks between lines aren't.
    public var characters = 0
    /// Lines with something in them. A divider has nothing in it.
    public var paragraphs = 0

    public init(words: Int = 0, characters: Int = 0, paragraphs: Int = 0) {
        self.words = words
        self.characters = characters
        self.paragraphs = paragraphs
    }

    public init(document: BiteDocument) {
        var words = 0
        for block in document.blocks {
            let text = block.text
            characters += text.count
            guard text.contains(where: { !$0.isWhitespace }) else { continue }
            paragraphs += 1
            text.enumerateSubstrings(in: text.startIndex..., options: [.byWords, .substringNotRequired]) { _, _, _, _ in
                words += 1
            }
        }
        self.words = words
    }
}
