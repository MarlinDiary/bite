import SwiftUI
import UniformTypeIdentifiers
import BiteKit
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// A page exported as a file: a PDF of it as Bite shows it, on white, in pages of paper; a picture
/// of all of it on its wash, as a page sent in Messages is; or its Markdown. Drawn as the widgets
/// and Messages draw a page (see `PageGlanceView`), in light appearance, as a page on paper is.
@MainActor
enum PageExport {
    enum Format: CaseIterable {
        case pdf, image, markdown

        var fileExtension: String {
            switch self {
            case .pdf: "pdf"
            case .image: "png"
            case .markdown: "md"
            }
        }

        var contentType: UTType {
            switch self {
            case .pdf: .pdf
            case .image: .png
            case .markdown: UTType(filenameExtension: "md", conformingTo: .plainText) ?? .plainText
            }
        }
    }

    /// What the file is called: the page's first words, or its dot's name, as a page with no words
    /// is called in Messages.
    static func name(page: Int, markdown: String) -> String {
        let title = PageGlance(markdown: markdown).title ?? "\(DotPalette.colors[page].name) Dot"
        // Nothing a file's name can't hold, and not a whole paragraph of it.
        let name = String(title.map { "/:\\".contains($0) ? "-" : $0 }.prefix(60))
        return name.trimmingCharacters(in: .whitespaces)
    }

    static func data(_ format: Format, page: Int, markdown: String, scale: CGFloat) -> Data? {
        switch format {
        case .pdf: pdf(page: page, markdown: markdown)
        case .image: image(page: page, markdown: markdown, scale: scale)
        case .markdown: Data(markdown.utf8)
        }
    }

    /// The file, as the share sheet takes it: among the temporary files, in a folder of its own that
    /// holds only the latest, the file before shared by then.
    static func file(_ format: Format, page: Int, markdown: String, scale: CGFloat) -> URL? {
        guard let data = data(format, page: page, markdown: markdown, scale: scale) else { return nil }
        let folder = FileManager.default.temporaryDirectory.appending(path: "Export", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "\(name(page: page, markdown: markdown)).\(format.fileExtension)")
        return (try? data.write(to: url)) == nil ? nil : url
    }

    // MARK: PDF

    /// The paper: US Letter where the person measures in inches, A4 everywhere else.
    static var paper: CGSize {
        Locale.current.measurementSystem == .us ? CGSize(width: 612, height: 792) : CGSize(width: 595.28, height: 841.89)
    }

    /// Round the page on its paper, as a document's.
    static let margin: CGFloat = 56
    /// Text the size of a document's, a little under Bite's own: its 17 points made 12.
    static let pdfMetrics = GlanceMetrics(scale: 0.72)

    /// The page on paper, as many pages of it as it takes, its lines each on one page, whole. A page
    /// of paper starts with something on it, and doesn't end with a heading, which goes with what it
    /// heads. Its text is text: it can be found, and copied.
    static func pdf(page: Int, markdown: String) -> Data? {
        let glance = PageGlance(markdown: markdown)
        let ink = DotPalette.colors[page]
        let paper = paper
        let width = paper.width - 2 * margin
        let sheets = paginate(glance, page: page, ink: ink, width: width, height: paper.height - 2 * margin)
        let data = NSMutableData()
        var box = CGRect(origin: .zero, size: paper)
        let info = [kCGPDFContextTitle: name(page: page, markdown: markdown), kCGPDFContextCreator: "Bite"] as CFDictionary
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &box, info) else { return nil }
        for lines in sheets {
            var sheet = glance
            sheet.lines = lines
            let view = column(sheet, page: page, ink: ink, width: width)
                .padding(margin)
                .frame(width: paper.width, height: paper.height, alignment: .topLeading)
                .background(Color.white)
            context.beginPDFPage(nil)
            ImageRenderer(content: view.environment(\.colorScheme, .light)).render { _, draw in
                draw(context)
            }
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }

    /// The page's lines, in the pages of paper they go on: as many on each as fit, found by halves.
    /// A line taller than a page of paper has one of its own, and goes on under its foot.
    private static func paginate(_ glance: PageGlance, page: Int, ink: DotColor, width: CGFloat,
                                 height: CGFloat) -> [[PageGlance.Line]] {
        let lines = glance.lines
        func fits(_ range: Range<Int>) -> Bool {
            var sheet = glance
            sheet.lines = Array(lines[range])
            var tall: CGFloat = 0
            ImageRenderer(content: column(sheet, page: page, ink: ink, width: width).environment(\.colorScheme, .light))
                .render { size, _ in tall = size.height }
            return tall <= height + 0.5
        }
        var sheets: [[PageGlance.Line]] = []
        var start = 0
        while start < lines.count {
            while start < lines.count, lines[start].isBlank { start += 1 }
            guard start < lines.count else { break }
            var low = start + 1
            var high = lines.count
            if fits(start..<low) {
                while low < high {
                    let middle = (low + high + 1) / 2
                    if fits(start..<middle) { low = middle } else { high = middle - 1 }
                }
            }
            var end = low
            while end - 1 > start, end < lines.count, lines[end - 1].kind.isHeading { end -= 1 }
            sheets.append(Array(lines[start..<end]))
            start = end
        }
        return sheets.isEmpty ? [[]] : sheets
    }

    private static func column(_ glance: PageGlance, page: Int, ink: DotColor, width: CGFloat) -> some View {
        PageGlanceView(glance: glance, page: page, ink: ink, metrics: pdfMetrics, ticks: false, showsAll: true)
            .frame(width: width, alignment: .topLeading)
    }

    // MARK: Picture

    /// As wide as a phone, all of the page, on its wash: for a chat that takes only pictures.
    static let imageWidth: CGFloat = 390
    /// The most pixels down a picture goes, which many apps take, and their memory too: a page longer
    /// than that, at `scale`, is drawn at less of it, down to a pixel a point.
    static let tallestImage: CGFloat = 16_384

    static func image(page: Int, markdown: String, scale: CGFloat) -> Data? {
        let ink = DotPalette.colors[page]
        let view = PageGlanceView(glance: PageGlance(markdown: markdown), page: page, ink: ink, metrics: GlanceMetrics(scale: 1),
                                  ticks: false, showsAll: true)
            .padding(EdgeInsets(top: 28, leading: 24, bottom: 32, trailing: 24))
            .frame(width: imageWidth, alignment: .topLeading)
            .background(PageWash(ink: ink))
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: view)
        var tall: CGFloat = 0
        renderer.render { size, _ in tall = size.height }
        renderer.scale = max(1, min(scale, tallestImage / max(tall, 1)))
        guard let image = renderer.cgImage else { return nil }
        #if canImport(UIKit)
        return UIImage(cgImage: image).pngData()
        #else
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        #endif
    }
}
