import UIKit
import BiteKit

/// What Bite's icon on the Home Screen offers, touched and held: a new line, or a new to-do, at
/// the end of the page Bite was last on, to type on with the keys up. Opening Bite and carrying on
/// a page otherwise takes a tap on the page and a scroll to its end. Each says which page it's
/// for, which is why they're set as Bite goes to the background, when that page may have changed,
/// rather than fixed in Info.plist.
enum HomeScreenActions {
    static let keepWriting = "com.chenyeni.bite.keep-writing"
    static let addToDo = "com.chenyeni.bite.add-to-do"

    /// Keep Writing, as the line is at the end of the page; Add To-Do, as Siri and Shortcuts call
    /// adding one. With Notes' symbols for writing and for checklists, the latter also the format
    /// bar's to-do button's.
    static func items(for dot: Int) -> [UIApplicationShortcutItem] {
        let page = DotPalette.colors[dot].name
        let userInfo = ["page": NSNumber(value: dot)]
        return [
            UIApplicationShortcutItem(type: keepWriting, localizedTitle: "Keep Writing", localizedSubtitle: page,
                                      icon: UIApplicationShortcutIcon(systemImageName: "square.and.pencil"), userInfo: userInfo),
            UIApplicationShortcutItem(type: addToDo, localizedTitle: "Add To-Do", localizedSubtitle: page,
                                      icon: UIApplicationShortcutIcon(systemImageName: "checklist"), userInfo: userInfo),
        ]
    }

    static func update(for store: DotStore) {
        UIApplication.shared.shortcutItems = items(for: store.selection)
    }

    /// Opens the page the item was for, with its line started. Says whether the item was Bite's.
    @discardableResult
    static func perform(_ item: UIApplicationShortcutItem, in store: DotStore) -> Bool {
        guard item.type == keepWriting || item.type == addToDo else { return false }
        let dot = (item.userInfo?["page"] as? NSNumber)?.intValue ?? store.selection
        store.startLine(on: dot, asToDo: item.type == addToDo)
        return true
    }
}
