import Foundation
import PDFKit
import Testing
import BiteKit
@testable import Bite

/// A page exported as a PDF, a picture, or its Markdown.
@MainActor
struct PageExportTests {
    @Test func aShortPageIsOnePageOfPaperWithItsText() throws {
        let data = try #require(PageExport.data(.pdf, page: 0, markdown: "# Groceries\n- [ ] Milk\n- [x] Eggs", scale: 2))
        #expect(data.starts(with: Data("%PDF".utf8)))
        let pdf = try #require(PDFDocument(data: data))
        #expect(pdf.pageCount == 1)
        let text = try #require(pdf.string)
        #expect(text.contains("Groceries"))
        #expect(text.contains("Milk"))
        // On the paper of where the person is.
        let bounds = try #require(pdf.page(at: 0)).bounds(for: .mediaBox)
        #expect(abs(bounds.width - PageExport.paper.width) < 0.5)
        #expect(abs(bounds.height - PageExport.paper.height) < 0.5)
    }

    /// A long page goes on as many pages of paper as it takes, every line of it on one of them,
    /// once.
    @Test func aLongPageGoesOnPagesOfPaperEveryLineOnce() throws {
        let lines = (1...150).map { "Line \($0) of a long page" }
        let data = try #require(PageExport.data(.pdf, page: 2, markdown: lines.joined(separator: "\n"), scale: 2))
        let pdf = try #require(PDFDocument(data: data))
        #expect(pdf.pageCount > 2)
        let text = (0..<pdf.pageCount).compactMap { pdf.page(at: $0)?.string }.joined(separator: "\n")
        for number in 1...150 {
            #expect(text.components(separatedBy: "Line \(number) of").count == 2, "line \(number)")
        }
    }

    /// A heading doesn't end a page of paper: it goes over with what it heads.
    @Test func aHeadingGoesOverWithWhatItHeads() throws {
        // Lines enough to fill the first page of paper, and then some.
        var lines = (1...300).map { "Line \($0)" }
        let data = try #require(PageExport.data(.pdf, page: 0, markdown: lines.joined(separator: "\n"), scale: 2))
        let first = try #require(PDFDocument(data: data)?.page(at: 0)?.string)
        let fit = first.components(separatedBy: .newlines).filter { $0.hasPrefix("Line ") }.count
        // A heading where the first page's last line was.
        lines[fit - 1] = "## Next part"
        let headedData = try #require(PageExport.data(.pdf, page: 0, markdown: lines.joined(separator: "\n"), scale: 2))
        let headed = try #require(PDFDocument(data: headedData))
        let firstAgain = try #require(headed.page(at: 0)?.string)
        let second = try #require(headed.page(at: 1)?.string)
        #expect(!firstAgain.contains("Next part"))
        #expect(second.hasPrefix("Next part"))
    }

    @Test func aPictureIsAsWideAsAPhoneAtItsScale() throws {
        let data = try #require(PageExport.data(.image, page: 1, markdown: "# Groceries\n- [ ] Milk", scale: 3))
        #expect(data.starts(with: Data([0x89, 0x50, 0x4E, 0x47])))
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect(properties[kCGImagePropertyPixelWidth] as? Int == Int(PageExport.imageWidth * 3))
    }

    @Test func markdownIsThePageAsItIs() throws {
        let markdown = "# Groceries\n- [ ] Milk\n\n**Bold** and [a link](https://example.com)"
        let data = try #require(PageExport.data(.markdown, page: 0, markdown: markdown, scale: 1))
        #expect(String(data: data, encoding: .utf8) == markdown)
    }

    /// The file is called by the page's first words, or by its dot with none, and holds nothing a
    /// file's name can't.
    @Test func theFileIsCalledByThePagesFirstWords() throws {
        #expect(PageExport.name(page: 0, markdown: "\n# Weekend groceries\n- [ ] Milk") == "Weekend groceries")
        #expect(PageExport.name(page: 0, markdown: "Notes: a/b") == "Notes- a-b")
        #expect(PageExport.name(page: 3, markdown: "") == "\(DotPalette.colors[3].name) Dot")
        let file = try #require(PageExport.file(.pdf, page: 0, markdown: "# Weekend groceries", scale: 1))
        #expect(file.lastPathComponent == "Weekend groceries.pdf")
        #expect(FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))
    }
}
