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
        // As tall as the page and its margins: its heading and its line, at least.
        #expect((properties[kCGImagePropertyPixelHeight] as? Int ?? 0) > 3 * 100)
    }

    /// Every row of every line goes into a picture, on the page's wash to its edges. Drawn at
    /// three times its points, a paragraph whose first row just filled the width once gave up its
    /// second row to fit, and the picture had bare strips at its top and bottom.
    @Test func aPictureKeepsEveryRowOnItsWash() throws {
        let markdown = """
        # 写作笔记
        任何内容都是为了让人看懂而写的。读完仍然不懂，这篇文章就失败了。
        不要先预想一套理想的结果，再照着它去写。
        ## 让 AI 帮忙时
        - 先理顺自己的想法，再给出清晰的修改意见
        - 读着不舒服，就直接说出来
        ## 写作约束
        ### 先想清楚再写
        - [ ] 动笔前用一句话说清这一节是干什么的
        - [x] 一段只说一件事
        > 文字只服务于叙事本身。
        ---
        最后通读一遍再交。
        """
        let data = try #require(PageExport.data(.image, page: 4, markdown: markdown, scale: 3))
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        // The picture's middle column of pixels, top to bottom: wash all the way, nothing clear.
        var pixels = [UInt8](repeating: 0, count: image.height * 4)
        let context = try #require(CGContext(data: &pixels, width: 1, height: image.height, bitsPerComponent: 8, bytesPerRow: 4,
                                             space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: -CGFloat(image.width / 2), y: 0, width: CGFloat(image.width), height: CGFloat(image.height)))
        let clear = stride(from: 3, to: pixels.count, by: 4).filter { pixels[$0] < 250 }.count
        #expect(clear == 0)
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
