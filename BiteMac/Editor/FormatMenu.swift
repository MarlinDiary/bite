import AppKit

/// The Format menu: the menu bar's, and the one in a page's right-click menu (see `MainMenu`,
/// `BiteTextView.menu(for:)`).
enum FormatMenu {
    /// Every style, with Notion's shortcuts for those the system has none for. Also in the text's
    /// right-click menu, without Link, as Add Link… is above it there.
    static func make(withLink: Bool = true) -> NSMenuItem {
        let link = withLink ? [item("Link", #selector(BiteTextView.addLink(_:)), "k")] : []
        return submenu("Format", [
            item("Bold", #selector(BiteTextView.toggleBold(_:)), "b"),
            item("Italic", #selector(BiteTextView.toggleItalic(_:)), "i"),
            item("Strikethrough", #selector(BiteTextView.toggleStrikethrough(_:)), "s", [.command, .shift]),
            item("Code", #selector(BiteTextView.toggleInlineCode(_:)), "e"),
        ] + link + [
            .separator(),
            item("To-do", #selector(BiteTextView.toggleTodoList(_:))),
            item("Bulleted List", #selector(BiteTextView.toggleBulletedList(_:))),
            item("Numbered List", #selector(BiteTextView.toggleNumberedList(_:))),
            item("Heading", #selector(BiteTextView.cycleHeading(_:))),
            item("Quote", #selector(BiteTextView.toggleQuote(_:))),
            item("Code Block", #selector(BiteTextView.toggleCodeBlock(_:))),
            .separator(),
            item("Indent", #selector(BiteTextView.indentLines(_:)), "]"),
            item("Outdent", #selector(BiteTextView.outdentLines(_:)), "["),
        ])
    }

    private static func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let menu = NSMenu(title: title)
        items.forEach(menu.addItem)
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    private static func item(_ title: String, _ action: Selector, _ key: String = "",
                             _ modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        return item
    }
}
