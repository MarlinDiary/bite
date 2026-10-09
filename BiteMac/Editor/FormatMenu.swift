import AppKit

/// The Format menu: the menu bar's, and the one in a page's right-click menu (see `MainMenu`,
/// `BiteTextView.menu(for:)`).
enum FormatMenu {
    /// Every style, with Notion's shortcuts for those the system has none for. Also in the text's
    /// right-click menu, without Link, as Add Link… is above it there.
    static func make(withLink: Bool = true) -> NSMenuItem {
        let link = withLink ? [item(String(localized: "Link"), #selector(BiteTextView.addLink(_:)), "k")] : []
        return submenu(String(localized: "Format"), [
            item(String(localized: "Bold"), #selector(BiteTextView.toggleBold(_:)), "b"),
            item(String(localized: "Italic"), #selector(BiteTextView.toggleItalic(_:)), "i"),
            item(String(localized: "Strikethrough"), #selector(BiteTextView.toggleStrikethrough(_:)), "s", [.command, .shift]),
            item(String(localized: "Code"), #selector(BiteTextView.toggleInlineCode(_:)), "e"),
        ] + link + [
            .separator(),
            item(String(localized: "To-do"), #selector(BiteTextView.toggleTodoList(_:))),
            item(String(localized: "Bulleted List"), #selector(BiteTextView.toggleBulletedList(_:))),
            item(String(localized: "Numbered List"), #selector(BiteTextView.toggleNumberedList(_:))),
            item(String(localized: "Heading"), #selector(BiteTextView.cycleHeading(_:))),
            item(String(localized: "Quote"), #selector(BiteTextView.toggleQuote(_:))),
            item(String(localized: "Code Block"), #selector(BiteTextView.toggleCodeBlock(_:))),
            .separator(),
            item(String(localized: "Indent"), #selector(BiteTextView.indentLines(_:)), "]"),
            item(String(localized: "Outdent"), #selector(BiteTextView.outdentLines(_:)), "["),
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
