import AppKit
import BiteKit

/// The app's menus. Bite shows no menu bar of its own, but their shortcuts work while the panel
/// is open: editing, formatting and ⌘1 to ⌘7 for the dots.
enum MainMenu {
    static func make() -> NSMenu {
        let main = NSMenu()
        main.addItem(submenu("Bite", [
            item(String(localized: "About Bite"), #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
            .separator(),
            item(String(localized: "Settings…"), #selector(AppDelegate.showSettings(_:)), ","),
            .separator(),
            item(String(localized: "Quit Bite"), #selector(NSApplication.terminate(_:)), "q"),
        ]))
        main.addItem(submenu(String(localized: "Edit"), [
            item(String(localized: "Undo"), Selector(("undo:")), "z"),
            item(String(localized: "Redo"), Selector(("redo:")), "z", [.command, .shift]),
            .separator(),
            item(String(localized: "Cut"), #selector(NSText.cut(_:)), "x"),
            item(String(localized: "Copy"), #selector(NSText.copy(_:)), "c"),
            item(String(localized: "Paste"), #selector(NSText.paste(_:)), "v"),
            item(String(localized: "Paste and Match Style"), #selector(NSTextView.pasteAsPlainText(_:)), "v", [.command, .option, .shift]),
            item(String(localized: "Delete"), #selector(NSText.delete(_:))),
            item(String(localized: "Select All"), #selector(NSText.selectAll(_:)), "a"),
            .separator(),
            submenu(String(localized: "Find"), [
                findItem(String(localized: "Find…"), .showFindInterface, "f"),
                findItem(String(localized: "Find Next"), .nextMatch, "g"),
                findItem(String(localized: "Find Previous"), .previousMatch, "g", [.command, .shift]),
            ]),
            submenu(String(localized: "Spelling"), [
                item(String(localized: "Show Spelling and Grammar"), #selector(NSText.showGuessPanel(_:)), ":"),
                item(String(localized: "Check Document Now"), #selector(NSText.checkSpelling(_:)), ";"),
                item(String(localized: "Check Spelling While Typing"), #selector(NSTextView.toggleContinuousSpellChecking(_:))),
            ]),
            submenu(String(localized: "Substitutions"), [
                item(String(localized: "Smart Quotes"), #selector(NSTextView.toggleAutomaticQuoteSubstitution(_:))),
                item(String(localized: "Text Replacement"), #selector(NSTextView.toggleAutomaticTextReplacement(_:))),
            ]),
        ]))
        main.addItem(FormatMenu.make())
        main.addItem(submenu(String(localized: "Dots"), DotPalette.colors.indices.map { dot in
            let dotItem = item(DotPalette.colors[dot].localizedName, #selector(PanelController.selectDot(_:)), "\(dot + 1)")
            dotItem.tag = dot
            return dotItem
        }))
        main.addItem(submenu(String(localized: "Window"), [
            item(String(localized: "Close"), #selector(NSWindow.performClose(_:)), "w"),
        ]))
        return main
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
