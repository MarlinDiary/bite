import Foundation

/// The room between the lines of a page, the same wherever a page is drawn: in the editor, on a
/// widget, on the watch, in Messages and in an exported page. In a phone's points, each of them
/// scaled with the text it's drawn at.
///
/// A gap is clear space: from the bottom of one line's letters to the top of the next line's, as
/// their fonts measure them (descender to ascender); to the edge of a code block's wash; to a
/// divider's rule. Gaps go up in steps of four points, and how far apart two lines are says how
/// closely they belong together:
/// - 4 between the rows of one line that wraps;
/// - 8 between the items of one list, and the lines of one quote, which read as one group;
/// - 12 between lines of any other kinds, and below a heading;
/// - 24 above a heading, where a new part of the page begins, and on either side of a divider.
///
/// A heading is twice as far from what's above it as from what's below, so that it reads as the
/// start of what follows. A first-level heading, set largest, gets a step more on both sides: 32
/// above, 16 below. Two headings in a row stay together, the second as close as a line below the
/// first. A page's first line has nothing above it.
public enum PageSpacing {
    /// Between the rows of one line that wraps.
    public static let row: CGFloat = 4
    /// Between the rows of a heading or of a code block, which are set closer.
    public static let tightRow: CGFloat = 2
    /// Between the items of one list, and the lines of one quote.
    public static let item: CGFloat = 8
    /// Between lines of any other kinds, and below a heading.
    public static let paragraph: CGFloat = 12
    /// Above a heading, and on either side of a divider.
    public static let section: CGFloat = 24
    /// Above and below a first-level heading.
    public static let aboveTitle: CGFloat = 32
    public static let belowTitle: CGFloat = 16

    /// The room between the rows of a line of `kind` that wraps.
    public static func rowGap(_ kind: BlockKind) -> CGFloat {
        kind.isHeading || kind == .code ? tightRow : row
    }

    /// The room between a line of kind `previous` and the line under it, of kind `kind`.
    public static func gap(after previous: BlockKind, before kind: BlockKind) -> CGFloat {
        // The lines of one code block are its rows.
        if previous == .code, kind == .code { return rowGap(.code) }
        if previous.isHeading { return previous == .heading1 ? belowTitle : paragraph }
        if kind.isHeading {
            // A divider has already parted it from what's above.
            if previous == .divider { return section }
            return kind == .heading1 ? aboveTitle : section
        }
        if previous == .divider || kind == .divider { return section }
        if previous.isList, kind.isList { return item }
        if previous == .quote, kind == .quote { return item }
        return paragraph
    }
}
