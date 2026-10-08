import SwiftUI
import BiteKit

/// The menu bar's on an iPad, and the shortcuts a hardware keyboard gives: a new window,
/// Settings, finding on the page, the page's formatting and the dots, as Bite's menus are on a Mac (see `MainMenu`
/// there). Each acts in the window in front, of Bite's several (see `PageWindow`).
///
/// Find and Format are menus of Bite's own. The system's, in SwiftUI's places for text, come up
/// empty: SwiftUI fills them only for its own text fields, and a page is UIKit's. Their shortcuts
/// did nothing, but for the two the page itself had, ⌘⇧S and ⌘E (2026-10-09).
struct MenuBarCommands: Commands {
    let store: DotStore
    @FocusedValue(PageWindow.self) private var window

    var body: some Commands {
        // Another window, on the page Bite's on, as Safari's ⌘N opens one: Bite has no new page to
        // make. Only where there can be several windows, on an iPad.
        CommandGroup(replacing: .newItem) {
            if UIApplication.shared.supportsMultipleScenes {
                Button("New Window") { PageWindows.shared.openWindow(from: window) }
                    .keyboardShortcut("n")
            }
        }
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { window?.isShowingSettings = true }
                .keyboardShortcut(",")
        }
        // As on a Mac: no Use Selection for Find, whose ⌘E is Code's, and the find bar's own
        // replace.
        CommandGroup(after: .pasteboard) {
            Menu("Find") {
                Button("Find…") { window?.find() }
                    .keyboardShortcut("f")
                Button("Find Next") { window?.findNext() }
                    .keyboardShortcut("g")
                Button("Find Previous") { window?.findPrevious() }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
            }
        }
        CommandMenu("Format") {
            format("Bold", .bold, key: "b")
            format("Italic", .italic, key: "i")
            format("Strikethrough", .strikethrough, key: "s", modifiers: [.command, .shift])
            Button("Code") { editing { $0.toggleInline(.code) } }
                .keyboardShortcut("e")
            format("Link", .link, key: "k")
            Divider()
            format("To-do", .todo)
            format("Bulleted List", .bullet)
            format("Numbered List", .ordered)
            format("Heading", .heading)
            format("Quote", .quote)
            format("Code Block", .code)
            Divider()
            format("Indent", .indent, key: "]")
            format("Outdent", .outdent, key: "[")
        }
        CommandMenu("Dots") {
            ForEach(DotPalette.colors.indices, id: \.self) { dot in
                Button(DotPalette.colors[dot].name) {
                    window?.page = dot
                }
                .keyboardShortcut(KeyEquivalent(Character(String(dot + 1))))
            }
        }
    }

    private func format(_ title: String, _ action: FormatAction, key: KeyEquivalent? = nil,
                        modifiers: EventModifiers = .command) -> some View {
        Button(title) { editing { $0.perform(action) } }
            .keyboardShortcut(key.map { KeyboardShortcut($0, modifiers: modifiers) })
    }

    /// The page being typed in, in the window in front, if one is: a style goes on what's selected
    /// or typed next there.
    private func editing(_ change: (EditorController) -> Void) {
        guard let editor = window?.editor else { return }
        change(editor)
    }
}
