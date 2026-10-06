import AppIntents
import SwiftUI
import UIKit
import WidgetKit
import BiteKit

/// The editor's sizes (see `EditorTheme`), times `scale`, for a page in a widget.
nonisolated struct GlanceMetrics {
    let scale: CGFloat
    /// Headings set no bigger than the text, for the Lock Screen's few lines.
    var flatHeadings = false

    var body: CGFloat { 17 * scale }
    // Headings stand out from the text less than in the editor: at its sizes a page's title took
    // half a small widget.
    var heading1: CGFloat { flatHeadings ? body : 23 * scale }
    var heading2: CGFloat { flatHeadings ? body : 20 * scale }
    var heading3: CGFloat { flatHeadings ? body : 18 * scale }
    var code: CGFloat { 14.5 * scale }
    var number: CGFloat { 16 * scale }
    /// Room between a list line's indent and its text, where the marker is drawn.
    var markerWidth: CGFloat { 28 * scale }
    var indentStep: CGFloat { 24 * scale }
    var quoteIndent: CGFloat { 18 * scale }
    var capHeight: CGFloat { UIFont.systemFont(ofSize: body).capHeight }

    /// Where a list line's text starts, as in the editor: deeper than six levels lines up with six.
    func listTextX(indent: Int) -> CGFloat {
        CGFloat(min(indent, 6)) * indentStep + markerWidth
    }

    /// The height of a row of text in a font of `size`.
    static func row(_ size: CGFloat, weight: UIFont.Weight = .regular) -> CGFloat {
        UIFont.systemFont(ofSize: size, weight: weight).lineHeight
    }
}

/// A page's lines as the editor draws them: headings, lists with their bullets, numbers and
/// checkboxes, quotes with their bar, code on its wash, dividers. As many as fit, whole: a line cut
/// through by the bottom shows only if most of it fits, fading out as more to come.
struct PageGlanceView: View {
    let glance: PageGlance
    /// The page, counting from 0 along the dot bar, for its to-dos' ticks.
    let page: Int
    let ink: DotColor
    let metrics: GlanceMetrics
    /// Whether a checkbox ticks its to-do off: not on the Lock Screen, which anyone can see.
    var ticks = true
    /// Room kept clear right of the first part, for a control in the corner.
    var firstPartTrailing: CGFloat = 0
    /// How far above the bottom a line has to end to show whole (see `PageColumn`).
    var safeBottom: CGFloat = 0

    /// A line on its own, or quote or code lines in a row, which share one bar or one wash.
    private enum Part {
        case line(PageGlance.Line)
        case quote([PageGlance.Line])
        case code([PageGlance.Line])

        var kind: BlockKind {
            switch self {
            case .line(let line): line.kind
            case .quote: .quote
            case .code: .code
            }
        }

        var lines: [PageGlance.Line] {
            switch self {
            case .line(let line): [line]
            case .quote(let lines), .code(let lines): lines
            }
        }

        /// The line, when it's a bullet, a numbered item or a to-do, with its marker in front.
        var listLine: PageGlance.Line? {
            guard case .line(let line) = self, [.bullet, .ordered, .todo].contains(line.kind) else { return nil }
            return line
        }

        var isBlank: Bool {
            if case .line(let line) = self { line.isBlank } else { false }
        }
    }

    private var parts: [Part] {
        var parts: [Part] = []
        for line in glance.lines {
            switch (line.kind, parts.last) {
            case (.quote, .quote(let lines)?): parts[parts.count - 1] = .quote(lines + [line])
            case (.code, .code(let lines)?): parts[parts.count - 1] = .code(lines + [line])
            case (.quote, _): parts.append(.quote([line]))
            case (.code, _): parts.append(.code([line]))
            default: parts.append(.line(line))
            }
        }
        return parts
    }

    var body: some View {
        let parts = parts
        PageColumn(safeBottom: safeBottom) {
            ForEach(parts.indices, id: \.self) { index in
                view(for: parts[index])
                    .padding(.trailing, index == 0 ? firstPartTrailing : 0)
                    .layoutValue(key: PartFit.self, value: fit(of: parts[index], after: index == 0 ? nil : parts[index - 1]))
            }
            // What hides the rest: at once below a whole line, or a line going on under the bottom
            // edge, fading out as it goes, eased as a scroll view's edge is.
            Rectangle()
                .blendMode(.destinationOut)
                .layoutValue(key: Eraser.self, value: .cut)
            LinearGradient(stops: PageColumn.fade, startPoint: .top, endPoint: .bottom)
                .blendMode(.destinationOut)
                .layoutValue(key: Eraser.self, value: .fade)
        }
        .compositingGroup()
        .clipped()
    }

    // MARK: Parts

    /// A part, built the same whatever its kind: a marker's column, then its lines, with a quote's
    /// bar, a code block's wash and a divider's rule always there, shown or not. Turned to another
    /// page, a widget changes the views it had into the next page's, text going smoothly into text;
    /// a view it didn't have it puts in at once. Built kind by kind, a line of another kind was a
    /// view of another kind: with the title left out, a turn often changed nothing smoothly at all.
    private func view(for part: Part) -> some View {
        let lines = part.lines
        let kind = part.kind
        let scale = metrics.scale
        return HStack(alignment: .firstTextBaseline, spacing: 0) {
            marker(for: part)
                .frame(width: part.listLine.map { metrics.listTextX(indent: $0.indent) } ?? 0, alignment: .trailing)
            VStack(alignment: .leading, spacing: (kind == .quote ? 6 : kind == .code ? 2 : 0) * scale) {
                ForEach(lines.indices, id: \.self) { index in
                    text(lines[index])
                }
            }
            .padding(kind == .quote ? EdgeInsets(top: 0, leading: metrics.quoteIndent, bottom: 0, trailing: 0)
                     : kind == .code ? EdgeInsets(top: 9 * scale, leading: 14 * scale, bottom: 9 * scale, trailing: 14 * scale)
                     : EdgeInsets())
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ink.color.opacity(kind == .code ? 0.1 : 0), in: .rect(cornerRadius: 7 * scale))
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1.5 * scale)
                    .fill(ink.color)
                    .frame(width: 3 * scale)
                    .padding(.leading, 2 * scale)
                    .opacity(kind == .quote ? 1 : 0)
                    .widgetAccentable()
            }
        }
        // A divider's room round its rule, and an empty line's room.
        .frame(height: kind == .divider ? 1 + metrics.body * 0.8 : part.isBlank ? metrics.body * 0.75 : nil)
        .overlay {
            Rectangle()
                .fill(Color(uiColor: .separator))
                .frame(height: 1)
                .opacity(kind == .divider ? 1 : 0)
        }
    }

    // MARK: Markers

    @ViewBuilder
    private func marker(for part: Part) -> some View {
        if let line = part.listLine {
            marker(for: line)
        }
    }

    @ViewBuilder
    private func marker(for line: PageGlance.Line) -> some View {
        switch line.kind {
        case .bullet:
            // Centred 15 points left of the text, as in the editor.
            bullet(indent: line.indent)
                .frame(width: 30 * metrics.scale)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + metrics.capHeight / 2 }
        case .ordered:
            Text(line.label ?? "")
                .font(.system(size: metrics.number, weight: .semibold).monospacedDigit())
                .foregroundStyle(ink.color)
                .lineLimit(1)
                .fixedSize()
                .padding(.trailing, 7 * metrics.scale)
                .widgetAccentable()
        default:
            checkbox(for: line)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + metrics.capHeight / 2 }
                .padding(.trailing, 7 * metrics.scale)
        }
    }

    /// Ticks its to-do off, or on again, where the widget can: the box changes at once, and the
    /// page with it.
    @ViewBuilder
    private func checkbox(for line: PageGlance.Line) -> some View {
        let size = 19 * metrics.scale
        if ticks {
            Toggle(isOn: line.isChecked,
                   intent: ToggleToDoIntent(PageTick(page: page, block: line.block, text: line.text, done: !line.isChecked))) {
                EmptyView()
            }
            .toggleStyle(CheckboxStyle(ink: ink, size: size, scale: metrics.scale))
        } else {
            Checkbox(isChecked: line.isChecked, ink: ink, size: size, scale: metrics.scale)
        }
    }

    /// A filled dot at the top level, a ring one level in, a square the next, then round again.
    @ViewBuilder
    private func bullet(indent: Int) -> some View {
        let scale = metrics.scale
        Group {
            switch indent % 3 {
            case 0: Circle().fill(ink.color).frame(width: 6.5 * scale, height: 6.5 * scale)
            case 1: Circle().strokeBorder(ink.color, lineWidth: 1.5 * scale).frame(width: 7.5 * scale, height: 7.5 * scale)
            default: Rectangle().fill(ink.color).frame(width: 5.5 * scale, height: 5.5 * scale)
            }
        }
        .widgetAccentable()
    }

    // MARK: Text

    private func text(_ line: PageGlance.Line) -> some View {
        // A done to-do is struck through as a whole, in its text's own grey: a widget leaves out a
        // line through text given a colour of its own.
        Text(line.kind == .divider ? AttributedString() : attributed(line))
            .strikethrough(line.kind == .todo && line.isChecked)
            .lineSpacing(rowSpacing(line.kind))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func attributed(_ line: PageGlance.Line) -> AttributedString {
        let isDone = line.kind == .todo && line.isChecked
        let primary = Color(uiColor: .label), secondary = Color(uiColor: .secondaryLabel)
        var result = AttributedString()
        for run in line.runs {
            var part = AttributedString(run.text)
            part.font = font(for: line.kind, style: run.style)
            part.foregroundColor = isDone ? secondary : primary
            if run.style.contains(.code), line.kind != .code {
                part.foregroundColor = ink.color
                part.backgroundColor = ink.color.opacity(0.12)
            }
            if run.link != nil, run.link?.isEmpty == false {
                let colour: Color = isDone ? secondary : ink.color
                part.foregroundColor = colour
                part.underlineStyle = Text.LineStyle(pattern: .solid, color: colour.opacity(0.4))
            }
            if run.style.contains(.strikethrough) {
                part.strikethroughStyle = .single
            }
            result += part
        }
        return result
    }

    private func font(for kind: BlockKind, style: InlineStyle) -> Font {
        if kind == .code { return .system(size: metrics.code, design: .monospaced) }
        let (size, weight) = size(for: kind)
        if style.contains(.code) {
            return .system(size: size * 0.88, weight: style.contains(.bold) ? .semibold : .regular, design: .monospaced)
        }
        let font = Font.system(size: size, weight: style.contains(.bold) && weight == .regular ? .bold : weight)
        return style.contains(.italic) ? font.italic() : font
    }

    private func size(for kind: BlockKind) -> (CGFloat, Font.Weight) {
        switch kind {
        case .heading1: (metrics.heading1, .bold)
        case .heading2: (metrics.heading2, .bold)
        case .heading3, .heading4, .heading5, .heading6: (metrics.heading3, .semibold)
        default: (metrics.body, .regular)
        }
    }

    private func rowSpacing(_ kind: BlockKind) -> CGFloat {
        (kind.isHeading || kind == .code ? 2 : 4) * metrics.scale
    }

    // MARK: Spacing

    /// The room above a part, as the editor leaves after one line and before the next, and its rows.
    private func fit(of part: Part, after above: Part?) -> PartFit {
        let gap = above.map { (spacing(of: $0.kind).after + spacing(of: part.kind).before) * metrics.scale } ?? 0
        switch part {
        case .line(let line) where line.kind == .divider || line.isBlank:
            return PartFit(gap: gap, row: GlanceMetrics.row(metrics.body), spacing: 0, splits: false)
        case .line(let line):
            let (size, weight) = size(for: line.kind)
            let uiWeight: UIFont.Weight = weight == .bold ? .bold : weight == .semibold ? .semibold : .regular
            return PartFit(gap: gap, row: GlanceMetrics.row(size, weight: uiWeight), spacing: rowSpacing(line.kind), splits: true)
        case .quote, .code:
            return PartFit(gap: gap, row: GlanceMetrics.row(metrics.body), spacing: 0, splits: false)
        }
    }

    private func spacing(of kind: BlockKind) -> (before: CGFloat, after: CGFloat) {
        switch kind {
        case .heading1: (14, 6)
        case .heading2: (10, 6)
        case .heading3, .heading4, .heading5, .heading6: (6, 4)
        case .bullet, .ordered, .todo, .quote: (0, 6)
        case .code: (8, 8)
        case .divider: (0, 0)
        case .paragraph: (0, 8)
        }
    }
}

/// How a part of a page sits in its column: the room above it, and the height of its rows and the
/// room between them, so a part cut through by the bottom keeps only its whole rows.
nonisolated struct PartFit: LayoutValueKey, Equatable {
    static let defaultValue = PartFit(gap: 0, row: 17, spacing: 0, splits: false)
    var gap: CGFloat
    var row: CGFloat
    var spacing: CGFloat
    /// Whether it can be cut between its rows: one paragraph can, a code block can't.
    var splits: Bool
}

/// What hides the rest of a page in a column: a part that isn't one of these is the page's own.
nonisolated enum Eraser: LayoutValueKey {
    static let defaultValue: Eraser? = nil
    case cut, fade
}

/// A page's parts from the top, as many as fit whole, the column reaching to the widget's bottom
/// edge. A line shows whole if it ends `safeBottom` above the edge. The next line, if most of a line
/// is left to the edge, goes on under it, fading out from its top to nothing at the edge, as a page
/// does going under the edge of a screen: cut off at the margin instead, it read as sliced through.
nonisolated struct PageColumn: Layout {
    var safeBottom: CGFloat = 0

    /// The fade over the line going under the edge: smoothstep, nothing hidden at its top and all of
    /// it at the edge, where a straight ramp made a seam at either end.
    static let fade: [Gradient.Stop] = stride(from: 0.0, through: 1.0, by: 0.125).map { t in
        Gradient.Stop(color: .black.opacity(t * t * (3 - 2 * t)), location: t)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions(by: CGSize(width: 100, height: 100))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let away = CGPoint(x: bounds.minX, y: bounds.maxY + 10_000)
        let limit = bounds.maxY - safeBottom
        var y = bounds.minY
        var erase: (top: CGFloat, fades: Bool)?
        var isFirst = true
        for part in subviews where part[Eraser.self] == nil {
            let fit = part[PartFit.self]
            let top = isFirst ? y : y + fit.gap
            isFirst = false
            guard erase == nil, top < bounds.maxY else {
                part.place(at: away, anchor: .topLeading, proposal: ProposedViewSize(width: bounds.width, height: nil))
                continue
            }
            let height = part.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil)).height
            part.place(at: CGPoint(x: bounds.minX, y: top), anchor: .topLeading,
                       proposal: ProposedViewSize(width: bounds.width, height: height))
            if top + height <= limit + 0.5 {
                y = top + height
                continue
            }
            let pitch = fit.row + fit.spacing
            let whole = fit.splits ? max(0, ((limit - top + fit.spacing) / pitch).rounded(.down)) : 0
            let end = whole > 0 ? top + whole * pitch - fit.spacing : y
            let next = whole > 0 ? end + fit.spacing : top
            erase = bounds.maxY - next >= 0.85 * fit.row ? (next, true) : (end, false)
        }
        for eraser in subviews {
            guard let kind = eraser[Eraser.self] else { continue }
            if let erase, (kind == .fade) == erase.fades {
                eraser.place(at: CGPoint(x: bounds.minX, y: erase.top), anchor: .topLeading,
                             proposal: ProposedViewSize(width: bounds.width, height: bounds.maxY - erase.top))
            } else {
                eraser.place(at: away, anchor: .topLeading, proposal: ProposedViewSize(width: 0, height: 0))
            }
        }
    }
}

/// A checkbox that ticks its to-do in a widget.
struct CheckboxStyle: ToggleStyle {
    let ink: DotColor
    let size: CGFloat
    let scale: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        Checkbox(isChecked: configuration.isOn, ink: ink, size: size, scale: scale)
            .contentShape(.rect)
    }
}

/// A to-do's checkbox, drawn as the editor draws it: a rounded square, filled with a tick once done.
struct Checkbox: View {
    let isChecked: Bool
    let ink: DotColor
    let size: CGFloat
    let scale: CGFloat

    var body: some View {
        Group {
            if isChecked {
                RoundedRectangle(cornerRadius: 5.5 * scale)
                    .fill(ink.color)
                    .overlay {
                        Tick()
                            .stroke(.white, style: StrokeStyle(lineWidth: 2.1 * scale, lineCap: .round, lineJoin: .round))
                    }
            } else {
                RoundedRectangle(cornerRadius: 5 * scale)
                    .inset(by: 0.8 * scale)
                    .stroke(ink.color, lineWidth: 1.6 * scale)
            }
        }
        .frame(width: size, height: size)
        .widgetAccentable()
    }

    nonisolated private struct Tick: Shape {
        func path(in rect: CGRect) -> Path {
            Path { path in
                path.move(to: CGPoint(x: rect.minX + rect.width * 0.27, y: rect.minY + rect.height * 0.53))
                path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.44, y: rect.minY + rect.height * 0.70))
                path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.75, y: rect.minY + rect.height * 0.33))
            }
        }
    }
}

extension DotColor {
    /// The colour, in light appearance or dark.
    var color: Color {
        Color(uiColor: UIColor { [light, dark] traits in UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light) })
    }

    /// The colour made lighter or darker by `delta` in OKLab, in light appearance or dark.
    func shade(_ delta: Double) -> Color {
        Color(uiColor: UIColor { [light, dark] traits in
            UIColor(hex: ColorMath.adjustingLightness(traits.userInterfaceStyle == .dark ? dark : light, by: delta))
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
