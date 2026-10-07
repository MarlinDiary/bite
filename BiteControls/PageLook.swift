import SwiftUI
import WidgetKit
import BiteKit

// How a page looks outside Bite: in its widgets, and in the cards Bite sends in Messages.

/// How near the bottom a whole line may come: as close to the edge as Apple lets anything come,
/// rather than stopping at the text's usual margin with room for it left over. Past it, a line goes
/// on under the edge, fading (see `PageColumn`).
enum PageLines {
    static let bottom: CGFloat = 11
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

/// A word or two in bold, its full stop one of Bite's dots, over a quieter line, in the middle of a
/// widget: "All done" when nothing's left to do, a page's name when there's nothing on it.
struct DotStatement: View {
    let title: String
    let ink: DotColor
    let line: String
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let (titleSize, lineSize): (CGFloat, CGFloat) = switch family {
        #if os(iOS)
        case .accessoryRectangular: (20, 13)
        #endif
        case .systemSmall: (30, 13)
        case .systemMedium: (34, 15)
        case .systemLarge: (40, 17)
        default: (44, 17)
        }
        VStack(spacing: titleSize * 0.1) {
            HStack(alignment: .firstTextBaseline, spacing: titleSize * 0.04) {
                Text(title)
                    .font(.system(size: titleSize, weight: .bold))
                Circle()
                    .fill(ink.color)
                    .frame(width: titleSize * 0.2, height: titleSize * 0.2)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] }
                    .widgetAccentable()
            }
            Text(line)
                .font(.system(size: lineSize))
                .foregroundStyle(Color.systemSecondaryLabel)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
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
