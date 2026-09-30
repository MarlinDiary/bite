/// How deep each list item really sits.
///
/// Markdown can't say that an item sits two levels below the one before it, or that a list
/// starts indented. It reads indentation relative to the items before: an item nests one level
/// below the nearest earlier item with less indentation. So deeper indents are pulled up, items
/// that were siblings stay siblings and a subtree keeps its shape. Anything that isn't a list
/// ends the list. The indents can be levels or widths in spaces; only their order matters.
public enum ListNesting {
    public static func levels(for items: [(kind: BlockKind, indent: Int)]) -> [Int] {
        // The indents of the levels that are open, outermost first.
        var open: [Int] = []
        return items.map { item in
            guard item.kind.isList else {
                open.removeAll()
                return 0
            }
            while let last = open.last, item.indent < last {
                open.removeLast()
            }
            if open.last.map({ item.indent > $0 }) ?? true {
                open.append(item.indent)
            }
            return open.count - 1
        }
    }
}
