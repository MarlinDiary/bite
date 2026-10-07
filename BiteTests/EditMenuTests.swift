import Testing
import UIKit
@testable import Bite

/// The menu over the caret or selected text is the system's, without what Bite has no use for: its
/// Format menu, as the format bar has every style, AutoFill, and changing between Simplified and
/// Traditional Chinese.
@MainActor
struct EditMenuTests {
    @Test func itHasNoFormatMenu() throws {
        let editor = EditorHarness("Some text")
        let view = editor.textView
        let range = try #require(view.textRange(from: view.beginningOfDocument, to: view.endOfDocument))
        let bold = UICommand(title: "Bold", action: #selector(UIResponderStandardEditActions.toggleBoldface(_:)))
        let suggested: [UIMenuElement] = [
            UIMenu(identifier: .standardEdit, options: .displayInline, children: [
                UICommand(title: "Copy", action: #selector(UIResponderStandardEditActions.copy(_:))),
            ]),
            UIMenu(title: "Format", identifier: .format, children: [
                UIMenu(title: "Text Style", identifier: .textStyle, children: [bold]),
            ]),
            UIMenu(identifier: .lookup, options: .displayInline, children: [
                UIMenu(title: "Text Style", identifier: .textStyle, children: [bold]),
                UIAction(title: "Look Up") { _ in },
            ]),
        ]
        let menu = try #require(view.editMenu(for: range, suggestedActions: suggested))
        #expect(menu.children.compactMap { ($0 as? UIMenu)?.identifier } == [.standardEdit, .lookup])
        let lookup = try #require(menu.children.last as? UIMenu)
        #expect(lookup.children.map(\.title) == ["Look Up"])
    }

    @Test func itHasNoAutoFillChineseConversionOrDrawing() throws {
        let editor = EditorHarness("Some text")
        let view = editor.textView
        let range = try #require(view.textRange(from: view.beginningOfDocument, to: view.endOfDocument))
        let suggested: [UIMenuElement] = [
            UIMenu(identifier: .replace, options: .displayInline, children: [
                UICommand(title: "Replace…", action: #selector(UIResponderStandardEditActions.paste(_:))),
                UICommand(title: "简⇄繁", action: Selector(("transliterateChinese:"))),
                UICommand(title: "Insert Drawing", action: Selector(("_insertDrawing:"))),
                UIMenu(title: "AutoFill", identifier: .autoFill, children: [
                    UICommand(title: "Scan Text", action: #selector(UIResponder.captureTextFromCamera(_:))),
                ]),
            ]),
        ]
        let menu = try #require(view.editMenu(for: range, suggestedActions: suggested))
        let replace = try #require(menu.children.first as? UIMenu)
        #expect(replace.children.map(\.title) == ["Replace…"])
    }

    /// Translate comes before Look Up, as the one more often wanted.
    @Test func translateComesBeforeLookUp() throws {
        let editor = EditorHarness("Some text")
        let view = editor.textView
        let range = try #require(view.textRange(from: view.beginningOfDocument, to: view.endOfDocument))
        let suggested: [UIMenuElement] = [
            UIMenu(identifier: .lookup, options: .displayInline, children: [
                UICommand(title: "Look Up", action: Selector(("_define:"))),
                UICommand(title: "Translate", action: Selector(("_translate:"))),
                UICommand(title: "Find", action: Selector(("findSelected:"))),
            ]),
        ]
        let menu = try #require(view.editMenu(for: range, suggestedActions: suggested))
        let lookup = try #require(menu.children.first as? UIMenu)
        #expect(lookup.children.map(\.title) == ["Translate", "Look Up", "Find"])
    }
}
