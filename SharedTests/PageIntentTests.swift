import AppIntents
import Foundation
import Testing
import BiteKit
@testable import Bite

/// What Siri and Shortcuts ask of Bite: a to-do added to a page, a page opened. A store of the
/// tests' own leaves the app's pages alone.
@MainActor
@Suite(.serialized)
struct PageIntentTests {
    private func folder() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "BiteIntentTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    /// The colours as the dot bar has them, in its order, for a page to open and one to add to.
    @Test func pagesAreTheDotsColours() {
        #expect(PageToOpen.allCases.count == DotPalette.count)
        #expect(PageForToDo.allCases.count == DotPalette.count)
        for page in PageToOpen.allCases {
            let name = DotPalette.colors[page.dot].name
            #expect(PageToOpen.caseDisplayRepresentations[page].map { String(localized: $0.title) } == name)
            let forToDo = PageForToDo(rawValue: page.rawValue)
            #expect(forToDo?.dot == page.dot)
            #expect(forToDo.flatMap { PageForToDo.caseDisplayRepresentations[$0] }.map { String(localized: $0.title) } == name)
        }
    }

    /// A to-do whatever the page ends with, on the page picked or the one last used.
    @Test func aToDoGoesToThePagePickedOrTheOneLastUsed() {
        let store = DotStore(folder: folder())
        store.update(dot: 5, markdown: "Notes\n")
        #expect(PageIntents.add("milk", to: .teal, in: store) == (5, true))
        #expect(store.markdown[5] == "Notes\n- [ ] milk\n")
        let last = store.selection
        store.update(dot: last, markdown: "- [ ] tea\n")
        #expect(PageIntents.add("eggs", to: nil, in: store) == (last, true))
        #expect(store.markdown[last] == "- [ ] tea\n- [ ] eggs\n")
    }

    @Test func nothingToAddChangesNothing() {
        let store = DotStore(folder: folder())
        let before = store.markdown[1]
        #expect(PageIntents.add("  \n", to: .orange, in: store) == (1, false))
        #expect(store.markdown[1] == before)
    }

    /// Bite may be stopped right after, run just for this: the page is written at once.
    @Test func itsWrittenToDiskAtOnce() {
        let folder = folder()
        let store = DotStore(folder: folder)
        PageIntents.add("milk", to: .blue, in: store)
        #expect(DotStore(folder: folder).markdown[4] == store.markdown[4])
        #expect(store.markdown[4].hasSuffix("- [ ] milk\n"))
    }

    /// Typing not reported yet goes in first, and the page being edited takes the to-do in, the
    /// caret staying where it was.
    @Test func thePageBeingEditedTakesItIn() {
        let store = DotStore(folder: folder())
        let editor = EditorHarness("Shopping\n- [ ] eggs")
        let page = editor.controller
        store.update(dot: page.dot, markdown: editor.markdown + "\n")
        page.onChange = { store.update(dot: page.dot, markdown: $0) }
        store.reportPendingEdits = { page.reportPendingChange() }
        store.applyInEditor = { dot, markdown in
            if dot == page.dot { page.applyRemote(markdown: markdown) }
        }
        editor.moveCaret(line: 0, column: 4)
        editor.type("!")
        PageIntents.add("milk", to: PageForToDo.allCases[page.dot], in: store)
        #expect(store.markdown[page.dot] == "Shop!ping\n- [ ] eggs\n- [ ] milk\n")
        #expect(editor.markdown == "Shop!ping\n- [ ] eggs\n- [ ] milk")
        #expect(editor.caret == 5)
    }

    /// Opened, the page is picked, and the Mac's panel is told to come up on it.
    @Test func openingPicksThePage() {
        let original = UserDefaults.standard.object(forKey: "selectedDot")
        defer { UserDefaults.standard.set(original, forKey: "selectedDot") }
        let store = DotStore(folder: folder())
        var shown: [Int] = []
        store.showInEditor = { shown.append($0) }
        store.open(dot: PageToOpen.blue.dot)
        #expect(store.selection == 4)
        #expect(shown == [4])
    }
}
