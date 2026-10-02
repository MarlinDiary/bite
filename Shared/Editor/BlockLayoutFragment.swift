#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif
import CoreText
import BiteKit

/// Hands TextKit a `BlockLayoutFragment` for each line that needs a marker or a background.
nonisolated final class BlockLayoutDelegate: NSObject, NSTextLayoutManagerDelegate {
    let theme: EditorTheme

    init(theme: EditorTheme) {
        self.theme = theme
    }

    func textLayoutManager(
        _ textLayoutManager: NSTextLayoutManager,
        textLayoutFragmentFor location: NSTextLocation,
        in textElement: NSTextElement
    ) -> NSTextLayoutFragment {
        guard let paragraph = textElement as? NSTextParagraph, paragraph.attributedString.length > 0 else {
            return NSTextLayoutFragment(textElement: textElement, range: textElement.elementRange)
        }
        let attributes = paragraph.attributedString.attributes(at: 0, effectiveRange: nil)
        let block = BlockAttributes(attributes)
        guard block.kind != .paragraph, !block.kind.isHeading else {
            return NSTextLayoutFragment(textElement: textElement, range: textElement.elementRange)
        }
        let fragment = BlockLayoutFragment(textElement: textElement, range: textElement.elementRange)
        fragment.block = block
        fragment.ordinal = attributes[.biteOrdinal] as? Int ?? 1
        fragment.numberStyle = (attributes[.biteShownStyle] as? String).flatMap(NumberStyle.init(rawValue:))
        fragment.runPosition = RunPosition(rawValue: attributes[.biteRunPosition] as? Int ?? 0) ?? .single
        fragment.theme = theme
        return fragment
    }
}

/// Shows TextKit the document's final newline as a plain space. After a final newline TextKit
/// lays out an empty extra line, and when the last line itself is empty it measures that extra
/// line in a default font. So the page lost some 27 points whenever the last line was emptied
/// and got them back with the first letter typed, and text scrolled to the end jumped. The final
/// newline can't be selected, so nothing else notices the swap. (A zero-width space broke the
/// geometry of text being composed in an input method, and with it the composing underline.)
nonisolated final class FinalNewlineDelegate: NSObject, NSTextContentStorageDelegate {
    func textContentStorage(_ textContentStorage: NSTextContentStorage, textParagraphWith range: NSRange) -> NSTextParagraph? {
        guard let storage = textContentStorage.textStorage, range.length > 0, NSMaxRange(range) == storage.length,
              (storage.string as NSString).character(at: NSMaxRange(range) - 1) == 0x0A else { return nil }
        let text = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: range))
        // Same length, so every offset stays put. The space keeps the newline's font and line
        // attributes, but no strikethrough or other marks that would reach past the last word.
        let last = NSRange(location: text.length - 1, length: 1)
        text.replaceCharacters(in: last, with: " ")
        for key: NSAttributedString.Key in [.strikethroughStyle, .underlineStyle, .backgroundColor] {
            text.removeAttribute(key, range: last)
        }
        return NSTextParagraph(attributedString: text)
    }
}

/// Draws what a line needs besides its text: bullets, numbers, checkboxes, the quote bar and
/// dividers. None of these are characters in the text. Code blocks' backgrounds are painted by
/// the text view, a whole block at a time.
nonisolated final class BlockLayoutFragment: NSTextLayoutFragment {
    var block = BlockAttributes()
    var ordinal = 1
    var numberStyle: NumberStyle?
    var runPosition = RunPosition.single
    var theme = EditorTheme(accent: .systemBlue)

    /// The marks below are drawn at a phone's size, times this (see `EditorTheme.scale`).
    private var scale: CGFloat { EditorTheme.scale }

    private var containerWidth: CGFloat {
        textLayoutManager?.textContainer?.size.width ?? layoutFragmentFrame.width
    }

    override var renderingSurfaceBounds: CGRect {
        // Markers sit left of the text and backgrounds span the full width. A long number such
        // as 100. may reach into the margin (see `numberOverhang`).
        let full = CGRect(x: -layoutFragmentFrame.minX - 20, y: -1, width: containerWidth + 20, height: layoutFragmentFrame.height + 2)
        return super.renderingSurfaceBounds.union(full)
    }

    /// Where the text starts on a line whose marker is drawn to the left of it (a bullet, number,
    /// checkbox or quote bar), in text-container coordinates. Nil for other lines.
    var textStartAfterMarker: CGFloat? {
        switch block.kind {
        case .bullet, .ordered, .todo: theme.listTextX(indent: block.indent)
        case .quote: theme.quoteIndent
        default: nil
        }
    }

    /// How much of the line's height its marker or quote bar takes up, from the top of its first
    /// row of text to the bottom of its last, in text-container coordinates. The spacing around
    /// the line is left out. It's where a quote's bar starts and stops.
    var markerSpan: (minY: CGFloat, maxY: CGFloat) {
        (layoutFragmentFrame.minY + firstBaseline - theme.bodyFont.ascender - 1,
         layoutFragmentFrame.minY + lastBaseline - theme.bodyFont.descender + 1)
    }

    /// The checkbox, in text-container coordinates, for drawing and hit-testing.
    var checkboxFrame: CGRect {
        let size = 19 * scale
        let x = theme.listTextX(indent: block.indent) - size - 7 * scale
        return CGRect(x: x, y: layoutFragmentFrame.minY + markerCenterY - size / 2, width: size, height: size)
    }

    override func draw(at point: CGPoint, in context: CGContext) {
        super.draw(at: point, in: context)
        // On the phone the text view draws the marks, each in a layer of its own (see
        // `BiteTextView.updateLineMarks`). UIKit takes a line's view away at times, as Writing
        // Tools does while it rewrites the line, and a mark drawn here went with it.
        #if !canImport(UIKit)
        drawMark(at: point, in: context)
        #endif
    }

    /// Draws the line's mark, its bullet, number, checkbox, quote bar or divider, with the line's
    /// own origin at `point`.
    func drawMark(at point: CGPoint, in context: CGContext) {
        switch block.kind {
        case .bullet: drawBullet(at: point, in: context)
        case .ordered: drawNumber(at: point, in: context)
        case .todo: drawCheckbox(at: point, in: context)
        case .quote: drawQuoteBar(at: point, in: context)
        case .divider: drawDivider(at: point, in: context)
        default: break
        }
    }

    /// Where the line's mark is drawn, in text-container coordinates, or nil for a line without
    /// one. A list's marks lie left of its text and a number may reach into the page margin;
    /// a quote's bar lies left of its text; a divider runs across the page. Top to bottom it's
    /// where the line itself draws, so a mark lands on the same pixels either way.
    var markFrame: CGRect? {
        let left: CGFloat, right: CGFloat
        switch block.kind {
        case .bullet, .ordered, .todo:
            left = -Self.numberOverhang - 1
            right = theme.listTextX(indent: block.indent)
        case .quote:
            left = 0
            right = theme.quoteIndent
        case .divider:
            left = 0
            right = containerWidth
        default:
            return nil
        }
        let surface = renderingSurfaceBounds
        return CGRect(x: left, y: layoutFragmentFrame.minY + surface.minY, width: right - left, height: surface.height)
    }

    // MARK: Geometry

    private func baseline(of line: NSTextLineFragment) -> CGFloat {
        // A line with text gets its line spacing above it; an empty line gets it below, with the
        // baseline reported that much higher. Measured up from the bottom, the two agree, so a
        // marker doesn't jump when its line empties.
        if let font = Self.fontOfEmptyLine(line) {
            return line.typographicBounds.maxY + font.descender
        }
        return line.typographicBounds.minY + line.glyphOrigin.y
    }

    /// The font of a line holding nothing but its newline.
    static func fontOfEmptyLine(_ line: NSTextLineFragment) -> PlatformFont? {
        let range = line.characterRange
        let text = line.attributedString
        guard range.length == 1, range.location < text.length,
              (text.string as NSString).character(at: range.location) == 0x0A else { return nil }
        return text.attribute(.font, at: range.location, effectiveRange: nil) as? PlatformFont
    }

    private var firstBaseline: CGFloat {
        textLineFragments.first.map(baseline(of:)) ?? theme.bodyFont.ascender
    }

    /// The document's last line also carries TextKit's empty "extra line" after the final
    /// newline; that one doesn't count.
    private var lastBaseline: CGFloat {
        textLineFragments.last(where: { $0.characterRange.length > 0 }).map(baseline(of:)) ?? firstBaseline
    }

    /// Vertical middle of the first line's text, in fragment coordinates.
    private var markerCenterY: CGFloat {
        firstBaseline - theme.bodyFont.capHeight / 2
    }

    /// Maps an x in text-container coordinates into the drawing context.
    private func contextX(_ x: CGFloat, _ point: CGPoint) -> CGFloat {
        point.x + x - layoutFragmentFrame.minX
    }

    // MARK: Drawing

    private func drawBullet(at point: CGPoint, in context: CGContext) {
        let centerX = contextX(theme.listTextX(indent: block.indent) - 15 * scale, point)
        let centerY = point.y + markerCenterY
        context.saveGState()
        let color = theme.accent.cgColor
        switch block.indent % 3 {
        case 0:
            let radius = 3.25 * scale
            context.setFillColor(color)
            context.fillEllipse(in: CGRect(x: centerX - radius, y: centerY - radius, width: 2 * radius, height: 2 * radius))
        case 1:
            let radius = 3 * scale
            context.setStrokeColor(color)
            context.setLineWidth(1.5 * scale)
            context.strokeEllipse(in: CGRect(x: centerX - radius, y: centerY - radius, width: 2 * radius, height: 2 * radius))
        default:
            let half = 2.75 * scale
            context.setFillColor(color)
            context.fill(CGRect(x: centerX - half, y: centerY - half, width: 2 * half, height: 2 * half))
        }
        context.restoreGState()
    }

    /// How far a number may reach into the page margin, left of the text container.
    private static let numberOverhang: CGFloat = 14 * EditorTheme.scale

    private func drawNumber(at point: CGPoint, in context: CGContext) {
        let text = ListNumbering.label(for: ordinal, indent: block.indent, style: numberStyle)
        let right = theme.listTextX(indent: block.indent) - 7 * scale
        var line = numberLine(text, font: theme.numberFont)
        // A list can start at any number, and one like 2026. would run off the screen, so a
        // number too long for the room left of it is set smaller, on the same baseline.
        let room = right + Self.numberOverhang
        if line.width > room {
            line = numberLine(text, font: theme.numberFont.resized(to: theme.numberFont.pointSize * room / line.width))
        }
        context.saveGState()
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        context.textPosition = CGPoint(x: contextX(right, point) - line.width, y: point.y + firstBaseline)
        CTLineDraw(line.line, context)
        context.restoreGState()
    }

    private func numberLine(_ text: String, font: PlatformFont) -> (line: CTLine, width: CGFloat) {
        let label = NSAttributedString(string: text, attributes: [
            .font: font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): theme.accent.cgColor,
        ])
        let line = CTLineCreateWithAttributedString(label)
        return (line, CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)))
    }

    private func drawCheckbox(at point: CGPoint, in context: CGContext) {
        let frame = checkboxFrame
        let rect = CGRect(
            x: contextX(frame.minX, point),
            y: point.y + frame.minY - layoutFragmentFrame.minY,
            width: frame.width,
            height: frame.height
        )
        let color = theme.accent.cgColor
        context.saveGState()
        if block.isChecked {
            context.addPath(CGPath(roundedRect: rect, cornerWidth: 5.5 * scale, cornerHeight: 5.5 * scale, transform: nil))
            context.setFillColor(color)
            context.fillPath()
            let check = CGMutablePath()
            check.move(to: CGPoint(x: rect.minX + rect.width * 0.27, y: rect.minY + rect.height * 0.53))
            check.addLine(to: CGPoint(x: rect.minX + rect.width * 0.44, y: rect.minY + rect.height * 0.70))
            check.addLine(to: CGPoint(x: rect.minX + rect.width * 0.75, y: rect.minY + rect.height * 0.33))
            context.addPath(check)
            context.setStrokeColor(PlatformColor.white.cgColor)
            context.setLineWidth(2.1 * scale)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.strokePath()
        } else {
            let inset = rect.insetBy(dx: 0.8 * scale, dy: 0.8 * scale)
            context.addPath(CGPath(roundedRect: inset, cornerWidth: 5 * scale, cornerHeight: 5 * scale, transform: nil))
            context.setStrokeColor(color)
            context.setLineWidth(1.6 * scale)
            context.strokePath()
        }
        context.restoreGState()
    }

    /// Quote lines in a row share one bar. Where two of them meet, each runs half a point into
    /// the other; the colour is solid, so the overlap doesn't show and no gap can open.
    private func drawQuoteBar(at point: CGPoint, in context: CGContext) {
        let top = runPosition.isFirst ? firstBaseline - theme.bodyFont.ascender - 1 : -0.5
        let bottom = runPosition.isLast ? lastBaseline - theme.bodyFont.descender + 1 : layoutFragmentFrame.height + 0.5
        let rect = CGRect(x: contextX(2 * scale, point), y: point.y + top, width: 3 * scale, height: bottom - top)
        context.saveGState()
        context.addPath(Self.roundedPath(rect, radius: 1.5 * scale, roundTop: runPosition.isFirst, roundBottom: runPosition.isLast))
        context.setFillColor(theme.accent.cgColor)
        context.fillPath()
        context.restoreGState()
    }

    private func drawDivider(at point: CGPoint, in context: CGContext) {
        context.saveGState()
        context.setFillColor(PlatformColor.separatorLine.cgColor)
        context.fill(CGRect(x: contextX(0, point), y: point.y + markerCenterY - 0.5, width: containerWidth, height: 1))
        context.restoreGState()
    }

    /// This line's share of its code block's background, in text-container coordinates. Inner
    /// lines run edge to edge. The padding of a block's first and last lines can reach past the
    /// line: TextKit leaves out the paragraph spacing above the page's first line and below its
    /// last. The text view paints the block (see `BiteTextView.updateCodeBackgrounds`).
    var codeBackgroundFrame: CGRect {
        let font = theme.codeFont
        let top = runPosition.isFirst ? firstBaseline - font.ascender - theme.codePadding : 0
        let bottom = runPosition.isLast ? lastBaseline - font.descender + theme.codePadding : layoutFragmentFrame.height
        return CGRect(x: 0, y: layoutFragmentFrame.minY + top, width: containerWidth, height: bottom - top)
    }

    static func roundedPath(_ rect: CGRect, radius: CGFloat, roundTop: Bool, roundBottom: Bool) -> CGPath {
        let top = roundTop ? radius : 0
        let bottom = roundBottom ? radius : 0
        let path = CGMutablePath()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + top))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: rect.minX + top, y: rect.minY), radius: top)
        path.addLine(to: CGPoint(x: rect.maxX - top, y: rect.minY))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.minY + top), radius: top)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottom))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.maxX - bottom, y: rect.maxY), radius: bottom)
        path.addLine(to: CGPoint(x: rect.minX + bottom, y: rect.maxY))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.maxY - bottom), radius: bottom)
        path.closeSubpath()
        return path
    }
}
