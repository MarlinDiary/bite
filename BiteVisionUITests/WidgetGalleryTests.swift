import XCTest

/// Bite's widgets in Apple Vision Pro's widget gallery, and in the room. The screen can't be
/// pictured from here (a picture of it comes out a single point): a widget put in the room is left
/// there, to be pictured after, which only `TEST_RUNNER_ROOM=1` does, as each run adds one. With
/// `TEST_RUNNER_SHOTS_DIR` set, the gallery's elements go there at each step.
///
/// A widget's to-do boxes can't be ticked from here reliably: in the simulator a tap on one most
/// often opened Bite on the page, as a tap beside it does. One that went through was ticked by
/// Bite, which the system ran the tick in, Bite being open (2026-10-09).
final class WidgetGalleryTests: XCTestCase {
    @MainActor private var gallery: XCUIApplication {
        XCUIApplication(bundleIdentifier: "com.apple.RealityWidgets")
    }

    /// Bite is in the gallery, with its three widgets in all five of Apple Vision Pro's sizes.
    @MainActor func testGalleryHasBitesWidgets() throws {
        let gallery = openOnBite()
        let pages = gallery.pageIndicators["LibraryAvailableAppWidgetsView"].firstMatch
        XCTAssertEqual(pages.value as? String, "page 1 of 15")
        var names: Set<String> = []
        for page in 1...15 {
            go(to: page, in: gallery)
            names.insert(gallery.staticTexts["displayName"].firstMatch.label)
        }
        XCTAssertEqual(names, ["Page", "Pages", "To-Dos"])
    }

    /// The gallery's `WIDGET_PAGE`th widget (default 1), into the room: Pages, Page and To-Dos, each
    /// small, medium, large, extra large and extra large upright.
    @MainActor func testAddsWidget() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["ROOM"] == "1", "Adds a widget to the room")
        let page = Int(ProcessInfo.processInfo.environment["WIDGET_PAGE"] ?? "") ?? 1
        let gallery = openOnBite()
        go(to: page, in: gallery)
        keep("before-add", of: gallery)
        gallery.buttons["Add Widget"].firstMatch.tap()
        sleep(4)
        keep("after-add", of: gallery)
    }

    /// The gallery, open on Bite's widgets.
    @MainActor private func openOnBite() -> XCUIApplication {
        continueAfterFailure = false
        let gallery = gallery
        gallery.launch()
        XCTAssertTrue(gallery.wait(for: .runningForeground, timeout: 10))
        let bite = gallery.otherElements["com.chenyeni.bite"].firstMatch
        XCTAssertTrue(bite.waitForExistence(timeout: 10))
        bite.tap()
        XCTAssertTrue(gallery.pageIndicators["LibraryAvailableAppWidgetsView"].firstMatch.waitForExistence(timeout: 5))
        sleep(2)
        return gallery
    }

    /// Swipes the gallery's widgets along to the `page`th, as its page dots count them. A swipe
    /// on the gallery as a whole fails: it's on its row of widgets.
    @MainActor private func go(to page: Int, in gallery: XCUIApplication) {
        let dots = gallery.pageIndicators["LibraryAvailableAppWidgetsView"].firstMatch
        let widgets = gallery.scrollViews["LibraryAvailableAppWidgetsView"].firstMatch
        for _ in 0..<20 {
            guard let value = dots.value as? String, let shown = value.split(separator: " ").dropFirst().first.flatMap({ Int($0) }),
                  shown != page else { return }
            if shown < page { widgets.swipeLeft() } else { widgets.swipeRight() }
            sleep(1)
        }
        XCTFail("Couldn't turn the gallery to page \(page)")
    }

    /// The app's elements, as `name`, where `TEST_RUNNER_SHOTS_DIR` says.
    @MainActor private func keep(_ name: String, of app: XCUIApplication) {
        guard let folder = ProcessInfo.processInfo.environment["SHOTS_DIR"] else { return }
        let url = URL(fileURLWithPath: folder)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try? app.debugDescription.write(to: url.appendingPathComponent("\(name).txt"), atomically: true, encoding: .utf8)
    }
}
