#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif
import CoreSpotlight
import ImageIO
import Testing
import BiteKit
@testable import Bite

/// The pages' lines in Spotlight, and a page opened at a line picked there.
@MainActor
@Suite(.serialized)
struct SpotlightTests {
    init() {
        EditorHarness.privatePreferences
        Preferences.defaults.removePersistentDomain(forName: "BiteTests")
    }

    /// What goes in and comes out, kept here rather than in Spotlight, with what it has and the
    /// state kept with the last batch, lost as Spotlight loses an app's items.
    final class Index: PageSearchIndex {
        var putIn: [String] = []
        var takenOut: [String] = []
        var batches = 0
        var outsideBatches = 0
        var has: Set<String> = []
        var state: Data?
        private var inBatch = false

        func beginBatch() {
            inBatch = true
        }

        func index(_ items: [CSSearchableItem]) {
            if !inBatch { outsideBatches += 1 }
            putIn += items.map(\.uniqueIdentifier)
            has.formUnion(items.map(\.uniqueIdentifier))
        }

        func delete(identifiers: [String]) {
            if !inBatch { outsideBatches += 1 }
            takenOut += identifiers
            has.subtract(identifiers)
        }

        func endBatch(state: Data, then done: @escaping @Sendable (Bool) -> Void) {
            inBatch = false
            batches += 1
            self.state = state
            done(true)
        }

        func fetchState(then done: @escaping @Sendable (Data?) -> Void) {
            done(state)
        }

        func fetchIdentifiers(then done: @escaping @Sendable ([String]) -> Void) {
            done(has.sorted())
        }

        func clear() {
            putIn = []
            takenOut = []
            batches = 0
        }
    }

    private func store(pages: [String] = []) -> DotStore {
        let store = DotStore(folder: FileManager.default.temporaryDirectory.appending(path: "BiteSpotlightTests-\(UUID().uuidString)"))
        for dot in DotPalette.colors.indices {
            store.update(dot: dot, markdown: dot < pages.count ? pages[dot] : "")
        }
        store.saveNow()
        return store
    }

    /// Defaults of the test's own for what's been put in, never the app's.
    private func withDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
        let name = "BiteSpotlightTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        try body(defaults)
    }

    private func identifiers(_ markdown: String, dot: Int = 0) -> [String] {
        SpotlightIndex.lines(for: dot, markdown: markdown).map(\.identifier)
    }

    // MARK: Lines

    /// A line is its text as it reads, with no bullet, box or Markdown; empty lines aren't lines.
    @Test func linesAreTheTextAsItReads() {
        let lines = SpotlightIndex.lines(for: 2, markdown: "# Groceries\n- [ ] Milk\n- [x] Eggs\n\nCall **Sam** at 5\n")
        #expect(lines.map(\.text) == ["Groceries", "Milk", "Eggs", "Call Sam at 5"])
        #expect(lines.map(\.position) == [0, 1, 2, 4])
        #expect(lines.allSatisfy { $0.identifier.hasPrefix("dot-3:") })
        #expect(SpotlightIndex.lines(for: 0, markdown: "\n\n\n").isEmpty)
    }

    /// Lines that read the same are told apart, and a line keeps its identifier wherever it moves.
    @Test func aLineKeepsItsIdentifierWhereverItMoves() {
        let twice = identifiers("Milk\nEggs\nMilk")
        #expect(Set(twice).count == 3)
        #expect(Array(identifiers("New\nMilk\nEggs\nMilk").dropFirst()) == twice)
        #expect(identifiers("Milk", dot: 0) != identifiers("Milk", dot: 1))
    }

    @Test func pagesAreNamedAsTheirFilesAre() {
        for dot in DotPalette.colors.indices {
            #expect(identifiers("Milk", dot: dot).allSatisfy { SpotlightIndex.dot(forIdentifier: $0) == dot })
        }
        for identifier in ["dot-0:1:0", "dot-8:1:0", "dot-:1:0", "page-1", ""] {
            #expect(SpotlightIndex.dot(forIdentifier: identifier) == nil)
        }
    }

    /// Under a line is its page's first line; under the first line, what follows it.
    @Test func aLinesItemShowsItsPagesFirstLine() throws {
        let lines = SpotlightIndex.lines(for: 2, markdown: "# Groceries\n- [ ] Milk\n- [x] Eggs\n")
        let milk = SpotlightIndex.item(for: lines[1], in: lines, dot: 2, modified: nil)
        #expect(milk.uniqueIdentifier == lines[1].identifier)
        #expect(milk.domainIdentifier == "dot-3")
        #expect(milk.attributeSet.title == "Milk")
        #expect(milk.attributeSet.contentDescription == "Groceries")
        #expect(milk.attributeSet.thumbnailURL == SpotlightIndex.thumbnailURL(for: 2))
        #expect(milk.attributeSet.thumbnailURL != nil)
        #expect(milk.expirationDate == .distantFuture)
        let first = SpotlightIndex.item(for: lines[0], in: lines, dot: 2, modified: nil)
        #expect(first.attributeSet.title == "Groceries")
        #expect(first.attributeSet.contentDescription == "Milk  Eggs")
    }

    /// A line's picture is its page's ring, as the app icon in that colour has it: clear in the middle.
    @Test func aLineShowsItsPagesRing() throws {
        let data = try Data(contentsOf: #require(SpotlightIndex.thumbnailURL(for: 1)))
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let side = image.width
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        pixels.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        }
        func alpha(_ x: Int, _ y: Int) -> UInt8 {
            pixels[(y * side + x) * 4 + 3]
        }
        #expect(alpha(side / 2, side / 2) == 0)
        #expect(alpha(2, 2) == 0)
        // Across the middle, a third of the way in from the left edge of the ring.
        #expect(alpha(side / 6 + side / 18, side / 2) == 255)
    }

    // MARK: Keeping them in

    /// The first time, every line goes in.
    @Test func everyLineGoesInTheFirstTime() {
        withDefaults { defaults in
            let store = store(pages: ["Milk\nEggs", "", "Gate code 4512"])
            let index = Index()
            let spotlight = SpotlightIndex(store: store, index: index, defaults: defaults)
            spotlight.start()
            #expect(index.putIn == identifiers("Milk\nEggs", dot: 0) + identifiers("Gate code 4512", dot: 2))
            #expect(index.takenOut.isEmpty)
            #expect(index.batches == 1)
            #expect(index.outsideBatches == 0)
            withExtendedLifetime(spotlight) {}
        }
    }

    /// Saved, a page's new lines go in and the ones gone come out; its first line goes in each
    /// time, as it shows what follows it. Emptied, all of them come out.
    @Test func onlyWhatChangedGoesInAsAPageIsSaved() {
        withDefaults { defaults in
            let store = store(pages: ["Milk\nEggs"])
            let index = Index()
            let spotlight = SpotlightIndex(store: store, index: index, defaults: defaults)
            spotlight.start()
            index.clear()
            store.update(dot: 0, markdown: "Milk\nOat milk\nEggs")
            #expect(index.putIn.isEmpty)
            store.saveNow()
            let lines = identifiers("Milk\nOat milk\nEggs")
            #expect(index.putIn == [lines[0], lines[1]])
            #expect(index.takenOut.isEmpty)
            index.clear()
            store.update(dot: 0, markdown: "Milk\nOat milk")
            store.saveNow()
            #expect(index.putIn == [lines[0]])
            #expect(index.takenOut == [lines[2]])
            index.clear()
            store.clear(dot: 0)
            #expect(index.putIn.isEmpty)
            #expect(Set(index.takenOut) == Set(lines.prefix(2)))
            #expect(index.outsideBatches == 0)
            withExtendedLifetime(spotlight) {}
        }
    }

    /// Every line shows its page's first line, so a new one puts the whole page in again.
    @Test func aNewFirstLinePutsThePageInAgain() {
        withDefaults { defaults in
            let store = store(pages: ["Groceries\nMilk\nEggs"])
            let index = Index()
            let spotlight = SpotlightIndex(store: store, index: index, defaults: defaults)
            spotlight.start()
            index.clear()
            store.update(dot: 0, markdown: "Weekend groceries\nMilk\nEggs")
            store.saveNow()
            #expect(index.putIn == identifiers("Weekend groceries\nMilk\nEggs"))
            #expect(index.takenOut == identifiers("Groceries"))
            withExtendedLifetime(spotlight) {}
        }
    }

    /// As Bite starts again, with Spotlight still having what was put in, only what changed
    /// meanwhile goes in or comes out.
    @Test func onlyWhatChangedMeanwhileGoesInAsBiteStartsAgain() {
        withDefaults { defaults in
            let store = store(pages: ["Milk\nEggs", "Gate code 4512"])
            let index = Index()
            let first = SpotlightIndex(store: store, index: index, defaults: defaults)
            first.start()
            store.onSave = nil
            store.update(dot: 1, markdown: "Gate code 4512\nBins on Tuesday")
            store.saveNow()
            index.clear()
            let again = SpotlightIndex(store: store, index: index, defaults: defaults)
            again.start()
            #expect(index.putIn == identifiers("Milk", dot: 0) + identifiers("Gate code 4512\nBins on Tuesday", dot: 1))
            #expect(index.takenOut.isEmpty)
            withExtendedLifetime([first, again]) {}
        }
    }

    /// Spotlight forgets an app's items at times, as when it's installed again: as Bite next
    /// starts, everything goes in afresh, whatever was noted as put in.
    @Test func whatSpotlightForgotGoesInAgain() {
        withDefaults { defaults in
            let store = store(pages: ["Milk\nEggs", "Gate code 4512"])
            let first = SpotlightIndex(store: store, index: Index(), defaults: defaults)
            first.start()
            let forgetful = Index()
            let again = SpotlightIndex(store: store, index: forgetful, defaults: defaults)
            again.start()
            #expect(forgetful.putIn == identifiers("Milk\nEggs", dot: 0) + identifiers("Gate code 4512", dot: 1))
            #expect(forgetful.takenOut.isEmpty)
            withExtendedLifetime([first, again]) {}
        }
    }

    /// Going in afresh, whatever else of Bite's Spotlight has comes out, one by one: taken out
    /// all at once, Spotlight took the lines put in after with them.
    @Test func whateverElseOfBitesComesOutAsEverythingGoesIn() {
        withDefaults { defaults in
            let store = store(pages: ["Milk\nEggs"])
            let index = Index()
            index.has = ["dot-1", "dot-2:0:0"]
            index.has.formUnion(identifiers("Milk"))
            let spotlight = SpotlightIndex(store: store, index: index, defaults: defaults)
            spotlight.start()
            #expect(index.putIn == identifiers("Milk\nEggs"))
            #expect(index.takenOut == ["dot-1", "dot-2:0:0"])
            #expect(index.has == Set(identifiers("Milk\nEggs")))
            #expect(index.batches == 1)
            withExtendedLifetime(spotlight) {}
        }
    }

    /// Moved, as an update moves it, the app has its pictures somewhere else: everything goes in
    /// again, with where they are now.
    @Test func everythingGoesInAgainAsTheAppMoves() throws {
        try withDefaults { defaults in
            let store = store(pages: ["Milk\nEggs"])
            let index = Index()
            let first = SpotlightIndex(store: store, index: index, defaults: defaults)
            first.start()
            let data = try #require(defaults.data(forKey: "spotlight"))
            var saved = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(saved["app"] as? String == Bundle.main.bundlePath)
            saved["app"] = "/elsewhere/Bite.app"
            defaults.set(try JSONSerialization.data(withJSONObject: saved), forKey: "spotlight")
            index.clear()
            let again = SpotlightIndex(store: store, index: index, defaults: defaults)
            again.start()
            #expect(index.putIn == identifiers("Milk\nEggs"))
            withExtendedLifetime([first, again]) {}
        }
    }

    /// Asked by Spotlight, which lost what it had, everything goes in again.
    @Test func everythingGoesInAgainAsSpotlightAsks() async {
        let name = "BiteSpotlightTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = store(pages: ["Milk\nEggs"])
        let index = Index()
        let spotlight = SpotlightIndex(store: store, index: index, defaults: defaults)
        spotlight.start()
        index.clear()
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            spotlight.searchableIndex(CSSearchableIndex(name: name), reindexAllSearchableItemsWithAcknowledgementHandler: {
                done.resume()
            })
        }
        #expect(index.putIn == identifiers("Milk\nEggs"))
        #expect(index.takenOut.isEmpty)
    }

    /// Turned off in Settings, everything comes out and nothing goes in; on again, it all goes back.
    @Test func turnedOffEverythingComesOut() {
        withDefaults { defaults in
            let store = store(pages: ["Milk"])
            let index = Index()
            let spotlight = SpotlightIndex(store: store, index: index, defaults: defaults)
            spotlight.start()
            index.clear()
            Preferences.showsInSpotlight = false
            #expect(index.takenOut == identifiers("Milk"))
            #expect(index.has.isEmpty)
            store.update(dot: 0, markdown: "Oat milk")
            store.saveNow()
            #expect(index.putIn.isEmpty)
            Preferences.showsInSpotlight = true
            #expect(index.putIn == identifiers("Oat milk"))
            #expect(index.has == Set(identifiers("Oat milk")))
            #expect(index.outsideBatches == 0)
            withExtendedLifetime(spotlight) {}
        }
    }

    /// Started with Spotlight turned off, turned on, everything goes in.
    @Test func turnedOnAfterStartingOffEverythingGoesIn() {
        withDefaults { defaults in
            Preferences.showsInSpotlight = false
            defer { Preferences.showsInSpotlight = true }
            let store = store(pages: ["Milk"])
            let index = Index()
            let spotlight = SpotlightIndex(store: store, index: index, defaults: defaults)
            spotlight.start()
            #expect(index.putIn.isEmpty)
            Preferences.showsInSpotlight = true
            #expect(index.putIn == identifiers("Milk"))
            withExtendedLifetime(spotlight) {}
        }
    }

    // MARK: Opening a result

    /// A line picked opens its page at the line, where it is now, with what was searched for.
    @Test func aLinePickedOpensItsPageAtTheLine() throws {
        let store = store(pages: ["", "", "", "", "Gate code 4512"])
        let selection = store.selection
        defer { store.selection = selection }
        let identifier = try #require(identifiers("Gate code 4512", dot: 4).first)
        store.update(dot: 4, markdown: "Bins on Tuesday\nGate code 4512")
        var shown: [String] = []
        store.revealInEditor = { dot, line, query in shown.append("\(dot) \(line.map(String.init) ?? "-") \(query)") }
        let activity = NSUserActivity(activityType: CSSearchableItemActionType)
        activity.userInfo = [CSSearchableItemActivityIdentifier: identifier, CSSearchQueryString: "gate"]
        #expect(SpotlightIndex.open(activity, in: store))
        #expect(store.selection == 4)
        #expect(shown == ["4 1 gate"])
        #expect(!SpotlightIndex.open(NSUserActivity(activityType: "com.chenyeni.bite.elsewhere"), in: store))
    }

    /// Picked as Bite opens, before the editors are there, it waits for them.
    @Test func aPageOpenedBeforeTheEditorsWaitsForThem() {
        let store = store()
        let selection = store.selection
        defer { store.selection = selection }
        store.reveal(dot: 2, line: 3, query: "milk")
        #expect(store.selection == 2)
        var shown: [String] = []
        store.revealInEditor = { dot, line, query in shown.append("\(dot) \(line ?? -1) \(query)") }
        store.revealInEditor = { _, _, _ in shown.append("again") }
        #expect(shown == ["2 3 milk"])
    }

    /// On the line picked, not wherever it's first on the page: lit, with the caret before it.
    /// It isn't selected, or typing would replace it.
    @Test func whatWasSearchedForIsLitOnTheLine() {
        let editor = EditorHarness("Milk\nBuy oat MILK\nmilk again")
        #expect(editor.controller.reveal("milk", line: 1))
        #expect(editor.textView.foundForTesting == NSRange(location: 13, length: 4))
        #expect(editor.textView.selectedRange == NSRange(location: 13, length: 0))
    }

    /// Not on the line, as when the line changed meanwhile, the line is lit.
    @Test func notOnTheLineTheLineIsLit() {
        let editor = EditorHarness("Milk\nBuy oat MILK\nmilk again")
        #expect(editor.controller.reveal("zebra", line: 1))
        #expect(editor.textView.foundForTesting == NSRange(location: 5, length: 12))
        #expect(editor.controller.reveal("milk", line: 40))
        #expect(editor.textView.foundForTesting == NSRange(location: 0, length: 4))
    }

    @Test func theFirstPlaceIsLitWhateverItsCase() {
        let editor = EditorHarness("Shopping\nBuy oat MILK\nmilk again")
        #expect(editor.controller.reveal("milk"))
        #expect(editor.textView.foundForTesting == NSRange(location: 17, length: 4))
    }

    @Test func accentsDontMatter() {
        let editor = EditorHarness("Lunch at Café Mémé")
        #expect(editor.controller.reveal("cafe meme"))
        #expect(editor.textView.foundForTesting == NSRange(location: 9, length: 9))
    }

    /// Spotlight finds a line with each word somewhere on it: not found together, the first word
    /// that's there is shown.
    @Test func wordsNotTogetherAreFoundOneByOne() {
        let editor = EditorHarness("Call Sam about the gate")
        #expect(editor.controller.reveal("gate tomorrow"))
        #expect(editor.textView.foundForTesting == NSRange(location: 19, length: 4))
    }

    @Test func nothingFoundLeavesThePageAsItWas() {
        let editor = EditorHarness("Call Sam")
        let selection = editor.textView.selectedRange
        #expect(!editor.controller.reveal("zebra"))
        #expect(!editor.controller.reveal("   "))
        #expect(editor.textView.selectedRange == selection)
        #expect(editor.textView.foundForTesting == nil)
    }

    /// Far down a long page, it's scrolled into view, lit where it's drawn; in view already, the
    /// page stays put.
    @Test func aPlaceFarDownIsScrolledIntoView() throws {
        let editor = EditorHarness((0..<300).map { "Line \($0)" }.joined(separator: "\n") + "\nThe gate code is 4512")
        layOut(editor)
        let top = scrolled(editor)
        #expect(editor.controller.reveal("Line 2"))
        layOut(editor)
        #expect(scrolled(editor) == top)
        #expect(editor.controller.reveal("4512", line: 300))
        layOut(editor)
        #expect(scrolled(editor) > top + 1000)
        let line = try #require(lineFrame(at: editor.textView.selectedRange.location, in: editor))
        #expect(line.minY >= scrolled(editor))
        #expect(line.maxY <= scrolled(editor) + visibleHeight(editor))
        let light = try #require(editor.textView.foundLightForTesting)
        #expect(light.midY > line.minY && light.midY < line.maxY)
        #expect(light.width > 10 && light.width < 100)
    }

    /// Lit at once, it stays a moment and goes by itself, calmly.
    @Test func theLightGoesByItself() async {
        let editor = EditorHarness("Buy oat milk")
        editor.textView.foundLight.hold = 0.05
        #expect(editor.controller.reveal("milk"))
        #expect(editor.textView.foundLight.fadeForTesting == nil)
        try? await Task.sleep(for: .seconds(0.3))
        #expect(editor.textView.foundForTesting == nil)
        #expect(editor.textView.foundLight.fadeForTesting == FoundLight.slowFade)
    }

    /// What's typed goes in before the text found, and its light goes at once: fading, it stayed
    /// where the text had been.
    @Test func typingPutsTheLightOutAtOnce() {
        let editor = EditorHarness("Buy oat milk")
        #expect(editor.controller.reveal("milk"))
        editor.type("x")
        #expect(editor.markdown == "Buy oat xmilk")
        #expect(editor.textView.foundForTesting == nil)
        #expect(editor.textView.foundLight.fadeForTesting == nil)
    }

    /// Already fading, as the page was scrolled, it goes at once as the text changes too.
    @Test func typingPutsOutALightThatsFading() {
        let editor = EditorHarness("Buy oat milk")
        #expect(editor.controller.reveal("milk"))
        editor.textView.hideFound()
        #expect(editor.textView.foundLight.fadeForTesting == FoundLight.quickFade)
        editor.type("x")
        #expect(editor.textView.foundLight.fadeForTesting == nil)
    }

    /// The page changed on another device, the text found may have moved: its light goes.
    @Test func aChangeFromAnotherDevicePutsTheLightOut() {
        let editor = EditorHarness("Buy oat milk")
        #expect(editor.controller.reveal("milk"))
        editor.controller.applyRemote(markdown: "Buy oat milk\nAnd bread")
        #expect(editor.textView.foundForTesting == nil)
        #expect(editor.textView.foundLight.fadeForTesting == nil)
    }

    /// Scrolled by hand, the page puts it out quickly.
    @Test func scrollingPutsTheLightOut() throws {
        let editor = EditorHarness("Buy oat milk")
        #expect(editor.controller.reveal("milk"))
        #if canImport(UIKit)
        editor.controller.scrollViewWillBeginDragging(editor.textView)
        #else
        let wheel = try #require(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: -10, wheel2: 0, wheel3: 0))
        editor.textView.scrollWheel(with: try #require(NSEvent(cgEvent: wheel)))
        #endif
        #expect(editor.textView.foundForTesting == nil)
        #expect(editor.textView.foundLight.fadeForTesting == FoundLight.quickFade)
    }

    #if canImport(UIKit)
    /// A finger landing on the page puts it out quickly. A click on the Mac: `MacMouseTests`.
    @Test func touchingThePagePutsTheLightOut() {
        let editor = EditorHarness("Buy oat milk")
        #expect(editor.controller.reveal("milk"))
        editor.textView.touchDownForTesting()
        #expect(editor.textView.foundForTesting == nil)
        #expect(editor.textView.foundLight.fadeForTesting == FoundLight.quickFade)
    }
    #endif

    #if !canImport(UIKit)
    /// A key pressed in the page, an arrow too, puts it out.
    @Test func aKeyPutsTheLightOut() throws {
        let editor = EditorHarness("Buy oat milk")
        #expect(editor.controller.reveal("milk"))
        let right = String(UnicodeScalar(NSRightArrowFunctionKey)!)
        let key = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                                windowNumber: editor.window.windowNumber, context: nil, characters: right,
                                                charactersIgnoringModifiers: right, isARepeat: false, keyCode: 124))
        editor.textView.keyDown(with: key)
        #expect(editor.textView.foundForTesting == nil)
        #expect(editor.textView.selectedRange == NSRange(location: 9, length: 0))
    }
    #endif

    private func layOut(_ editor: EditorHarness) {
        #if canImport(UIKit)
        editor.textView.layoutIfNeeded()
        #else
        editor.textView.layoutSubtreeIfNeeded()
        #endif
    }

    /// How far down the page is scrolled.
    private func scrolled(_ editor: EditorHarness) -> CGFloat {
        #if canImport(UIKit)
        editor.textView.contentOffset.y
        #else
        editor.textView.visibleRect.minY
        #endif
    }

    private func visibleHeight(_ editor: EditorHarness) -> CGFloat {
        #if canImport(UIKit)
        editor.textView.bounds.height
        #else
        editor.textView.visibleRect.height
        #endif
    }

    /// Where the line `character` is on is, in the text view.
    private func lineFrame(at character: Int, in editor: EditorHarness) -> CGRect? {
        #if canImport(UIKit)
        let textView = editor.textView
        guard let position = textView.position(from: textView.beginningOfDocument, offset: character) else { return nil }
        return textView.caretRect(for: position)
        #else
        let textView = editor.textView
        guard let layoutManager = textView.textLayoutManager,
              let location = layoutManager.location(layoutManager.documentRange.location, offsetBy: character),
              let fragment = layoutManager.textLayoutFragment(for: location) else { return nil }
        let inParagraph = character - layoutManager.offset(from: layoutManager.documentRange.location, to: fragment.rangeInElement.location)
        guard let line = fragment.textLineFragments.first(where: { NSMaxRange($0.characterRange) > inParagraph }) else { return nil }
        return line.typographicBounds.offsetBy(dx: fragment.layoutFragmentFrame.minX + textView.textContainerOrigin.x,
                                               dy: fragment.layoutFragmentFrame.minY + textView.textContainerOrigin.y)
        #endif
    }
}
