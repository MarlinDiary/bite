import AppIntents
import SwiftUI
import WidgetKit
import BiteKit

/// A widget's own rounded corner, and the size of a control set in one. A control in a corner sits
/// round the corner's own centre, so the gap between the two is even all round. The corner, measured
/// on an iPhone 17, curves round a centre 26.5 points in from either edge.
enum WidgetCorner {
    static let radius: CGFloat = 26.5
    /// Bite's own controls at 0.7 of their size: the "…" button's 44 points, the dot bar's height.
    static let control: CGFloat = 31
    /// From the widget's edges to a corner control's: 11 points, as Apple gives controls.
    static var gap: CGFloat { radius - control / 2 }
}

/// A page on its dot's faint wash, as in Bite. A small one turns by an arrow in its corner, a
/// medium one by the dots down its side, a large one by the dot bar across its top. On the Lock
/// Screen it's the page's first lines, or Bite's ring.
struct PageWidgetView: View {
    let entry: PageEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetContentMargins) private var margins
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    private var ink: DotColor {
        DotPalette.colors[entry.page]
    }

    /// `x` on the nearest whole pixel.
    private func onPixels(_ x: CGFloat) -> CGFloat {
        (x * displayScale).rounded() / displayScale
    }

    var body: some View {
        content
            .widgetURL(PageTurns.link(to: entry.page))
            .modifier(OwnBackground(isOnHomeScreen: family.isOnHomeScreen) { PageWash(ink: ink) })
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .systemSmall:
            // The arrow in the top corner, beside the first line, as the "…" button is beside
            // Bite's dot bar, on whole pixels, as its glass was pictured.
            GeometryReader { proxy in
                ZStack(alignment: .topLeading) {
                    PageGlanceView(glance: entry.glance, page: entry.page, ink: ink, metrics: GlanceMetrics(scale: 0.76),
                                   firstPartTrailing: WidgetCorner.gap + WidgetCorner.control + 6 - margins.trailing,
                                   safeBottom: PageLines.bottom)
                        .padding(EdgeInsets(top: margins.top, leading: margins.leading, bottom: 0, trailing: margins.trailing))
                    NextPageButton(entry: entry)
                        .offset(x: onPixels(proxy.size.width - WidgetCorner.gap - WidgetCorner.control), y: WidgetCorner.gap)
                }
            }
        case .systemMedium:
            ZStack(alignment: .trailing) {
                PageGlanceView(glance: entry.glance, page: entry.page, ink: ink, metrics: GlanceMetrics(scale: 0.78),
                               safeBottom: PageLines.bottom)
                    .padding(EdgeInsets(top: margins.top, leading: margins.leading, bottom: 0,
                                        trailing: WidgetCorner.radius + DotColumn.dot / 2 + 10))
                DotColumn(entry: entry)
            }
        case .accessoryCircular:
            PageRing(entry: entry)
        case .accessoryRectangular:
            PageGlanceView(glance: entry.glance, page: entry.page, ink: ink,
                           metrics: GlanceMetrics(scale: 0.8, flatHeadings: true), ticks: false)
        default:
            // Large, and taller: a page as tall as the Home Screen's (iOS 27), and an iPad's extra
            // large one, at the iPad's own bigger size.
            VStack(spacing: 12) {
                GlassDotBar(entry: entry)
                    .padding(.top, WidgetCorner.gap)
                PageGlanceView(glance: entry.glance, page: entry.page, ink: ink,
                               metrics: GlanceMetrics(scale: family == .systemExtraLarge ? 0.9 : 0.84), safeBottom: PageLines.bottom)
                    .padding(EdgeInsets(top: 0, leading: margins.leading, bottom: 0, trailing: margins.trailing))
            }
        }
    }
}

/// How near the bottom a whole line may come: as close to the edge as Apple lets anything come,
/// rather than stopping at the text's usual margin with room for it left over. Past it, a line goes
/// on under the edge, fading (see `PageColumn`).
enum PageLines {
    static let bottom: CGFloat = 11
}

nonisolated extension WidgetFamily {
    /// Not one of the Lock Screen's, which have no background of their own.
    var isOnHomeScreen: Bool {
        ![.accessoryCircular, .accessoryRectangular, .accessoryInline].contains(self)
    }
}

/// A widget's background, drawn by the widget itself as well as given to the system. In dark
/// appearance the Home Screen lays a sheen over a widget's background, white from about a tenth at
/// the top to a twentieth at the bottom, so a page there came out paler than in Bite; over the
/// widget's own views it lays nothing. Where the system takes the background away (StandBy) or
/// tints the widget, the widget leaves it to the system: drawn there, it was a block of tint.
struct OwnBackground<Background: View>: ViewModifier {
    let isOnHomeScreen: Bool
    @ViewBuilder let background: () -> Background
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.showsWidgetContainerBackground) private var showsBackground

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                if isOnHomeScreen, renderingMode == .fullColor, showsBackground {
                    background()
                }
            }
            .containerBackground(for: .widget) {
                if isOnHomeScreen { background() } else { Color.clear }
            }
    }
}

/// A page's faint wash of its dot's colour, as behind every page in Bite.
struct PageWash: View {
    let ink: DotColor
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ink.color.opacity(colorScheme == .dark ? 0.09 : 0.08)
            .background(colorScheme == .dark ? Color.black : Color.white)
    }
}

/// Bite's dot bar at 0.7 of its size, on a picture of real Liquid Glass at that size over the
/// page's own wash: a widget can't hold glass. The bar sits on whole pixels, as the glass in the
/// picture did, or its edges would blur.
private struct GlassDotBar: View {
    let entry: PageEntry
    @Environment(\.displayScale) private var displayScale
    static let size = CGSize(width: 158, height: WidgetCorner.control)
    static let dot: CGFloat = 12.6
    static let pitch: CGFloat = 21

    var body: some View {
        GeometryReader { proxy in
            let x = ((proxy.size.width - Self.size.width) / 2 * displayScale).rounded(.down) / displayScale
            HStack(spacing: 0) {
                ForEach(0..<DotPalette.count, id: \.self) { dot in
                    Button(intent: TurnPageIntent(widget: entry.widget, page: dot)) {
                        DotRing(ink: entry.isEmpty[dot] ? DotPalette.empty : DotPalette.colors[dot], isSelected: dot == entry.page,
                                size: Self.dot)
                            .frame(width: Self.pitch, height: Self.size.height)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(DotPalette.colors[dot].name) page")
                }
            }
            .frame(width: Self.size.width, height: Self.size.height)
            .background(Glass(shape: .capsule, page: entry.page, size: Self.size))
            .offset(x: x)
        }
        .frame(height: Self.size.height)
    }
}

/// The seven dots down a medium widget's side, from the centre of its top corner to the centre of
/// its bottom one, each turning the widget to its page. With no bar behind them they leave the page
/// more room.
private struct DotColumn: View {
    let entry: PageEntry
    static let dot: CGFloat = 12.6

    var body: some View {
        GeometryReader { proxy in
            let pitch = (proxy.size.height - 2 * WidgetCorner.radius) / CGFloat(DotPalette.count - 1)
            ForEach(0..<DotPalette.count, id: \.self) { dot in
                Button(intent: TurnPageIntent(widget: entry.widget, page: dot)) {
                    DotRing(ink: entry.isEmpty[dot] ? DotPalette.empty : DotPalette.colors[dot], isSelected: dot == entry.page,
                            size: Self.dot)
                        .frame(width: 2 * WidgetCorner.radius, height: pitch)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(DotPalette.colors[dot].name) page")
                .position(x: proxy.size.width - WidgetCorner.radius, y: WidgetCorner.radius + CGFloat(dot) * pitch)
            }
        }
    }
}

/// Turns a small widget to the next page with something on it, as Bite's "…" button looks. With no
/// other page, it's only there faintly.
private struct NextPageButton: View {
    let entry: PageEntry

    var body: some View {
        let next = PageTurns.next(after: entry.page, isEmpty: entry.isEmpty)
        let size = CGSize(width: WidgetCorner.control, height: WidgetCorner.control)
        let arrow = Image(systemName: "chevron.right")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(DotPalette.colors[entry.page].color)
            .frame(width: size.width, height: size.height)
            .background(Glass(shape: .circle, page: entry.page, size: size))
            .widgetAccentable()
        if next == entry.page {
            arrow.opacity(0.4)
        } else {
            Button(intent: TurnPageIntent(widget: entry.widget, page: next)) {
                arrow
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Next page")
        }
    }
}

/// Real Liquid Glass, pictured at this size over each page's wash, in light and dark (see
/// `GlassSwatches` in Bite), and taken off the wash: a layer that gives the picture back exactly over
/// the wash, and over the light the system lays on a widget passes that through, as glass would.
/// It reaches past the shape, 3 points round and 12 below, for the glass's shadow. Where the system
/// draws the widget in one colour, a fine line in its place.
private struct Glass: View {
    enum Shape {
        case capsule, circle
    }

    let shape: Shape
    let page: Int
    let size: CGSize
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        if renderingMode == .fullColor {
            let name = "Glass\(shape == .capsule ? "Bar" : "Circle")-\(DotPalette.colors[page].name)"
            Image(name)
                .resizable()
                .frame(width: size.width + 6, height: size.height + 15)
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .offset(x: -3, y: -3)
                .allowsHitTesting(false)
        } else {
            Capsule().strokeBorder(.primary.opacity(0.35), lineWidth: 0.67)
        }
    }
}

/// Bite's ring on the Lock Screen, as its icon has it, opening Bite on the page.
private struct PageRing: View {
    let entry: PageEntry

    var body: some View {
        let diameter: CGFloat = 46
        ZStack {
            AccessoryWidgetBackground()
            // The icon's ring: its band is that share of the ring across.
            Circle()
                .strokeBorder(lineWidth: diameter * 160 / 770)
                .frame(width: diameter, height: diameter)
        }
        .widgetAccentable()
        .accessibilityElement()
        .accessibilityLabel("\(DotPalette.colors[entry.page].name) page")
    }
}

/// A dot as in Bite's dot bar: a ring that's solid when selected, set into its capsule, darker
/// toward the top edge, where a fine inner shadow falls. Everything as the app has it, at this size.
struct DotRing: View {
    let ink: DotColor
    let isSelected: Bool
    let size: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let scale = size / 18
        let shading = LinearGradient(colors: [ink.shade(-0.10), ink.shade(0.07)], startPoint: .top, endPoint: .bottom)
            .shadow(.inner(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.22), radius: 0.7 * scale, x: 0, y: 0.7 * scale))
        Group {
            if isSelected {
                Circle().fill(shading)
            } else {
                Circle().strokeBorder(shading, lineWidth: 3 * scale)
            }
        }
        .frame(width: size, height: size)
        .widgetAccentable()
    }
}
