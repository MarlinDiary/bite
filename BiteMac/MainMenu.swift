import AppKit
import BiteKit

/// The app's menus. Bite shows no menu bar of its own, but their shortcuts work while the panel
/// is open: editing, formatting and ⌘1 to ⌘7 for the dots.
enum MainMenu {
    static func make() -> NSMenu {
        let main = NSMenu()
        main.addItem(submenu("Bite", [
            item("About Bite", #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
            .separator(),
            item("Settings…", #selector(AppDelegate.showSettings(_:)), ","),
            .separator(),
            item("Quit Bite", #selector(NSApplication.terminate(_:)), "q"),
        ]))
        main.addItem(submenu("Edit", [
            item("Undo", Selector(("undo:")), "z"),
            item("Redo", Selector(("redo:")), "z", [.command, .shift]),
            .separator(),
            item("Cut", #selector(NSText.cut(_:)), "x"),
            item("Copy", #selector(NSText.copy(_:)), "c"),
            item("Paste", #selector(NSText.paste(_:)), "v"),
            item("Paste and Match Style", #selector(NSTextView.pasteAsPlainText(_:)), "v", [.command, .option, .shift]),
            item("Delete", #selector(NSText.delete(_:))),
            item("Select All", #selector(NSText.selectAll(_:)), "a"),
            .separator(),
            submenu("Find", [
                findItem("Find…", .showFindInterface, "f"),
                findItem("Find Next", .nextMatch, "g"),
                findItem("Find Previous", .previousMatch, "g", [.command, .shift]),
            ]),
            submenu("Spelling", [
                item("Show Spelling and Grammar", #selector(NSText.showGuessPanel(_:)), ":"),
                item("Check Document Now", #selector(NSText.checkSpelling(_:)), ";"),
                item("Check Spelling While Typing", #selector(NSTextView.toggleContinuousSpellChecking(_:))),
            ]),
            submenu("Substitutions", [
                item("Smart Quotes", #selector(NSTextView.toggleAutomaticQuoteSubstitution(_:))),
                item("Text Replacement", #selector(NSTextView.toggleAutomaticTextReplacement(_:))),
            ]),
        ]))
        main.addItem(format())
        main.addItem(submenu("Dots", DotPalette.colors.indices.map { dot in
            let dotItem = item(DotPalette.colors[dot].name, #selector(PanelController.selectDot(_:)), "\(dot + 1)")
            dotItem.tag = dot
            return dotItem
        }))
        main.addItem(submenu("Window", [
            item("Close", #selector(NSWindow.performClose(_:)), "w"),
        ]))
        return main
    }

    /// Every style, with Notion's shortcuts for those the system has none for. Also in the text's
    /// right-click menu, without Link, as Add Link… is above it there.
    static func format(withLink: Bool = true) -> NSMenuItem {
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

    private static func findItem(_ title: String, _ action: NSTextFinder.Action, _ key: String,
                                 _ modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let item = item(title, #selector(NSTextView.performFindPanelAction(_:)), key, modifiers)
        item.tag = action.rawValue
        return item
    }
}
