import Testing
import UIKit
import SafariServices
import BiteKit
@testable import Bite

/// A tap on a link's text goes where the link goes, while the page isn't being edited. On a page
/// being edited, it brings the link up in the format bar to change (see `LinkBarTests`), or, with
/// no bar on the keys, puts the caret in its text, as in any.
@MainActor
struct LinkTapTests {
    private func center(of range: NSRange, in editor: EditorHarness) throws -> CGPoint {
        let frame = try #require(editor.textView.textFramesForTesting(of: range).first)
        return CGPoint(x: frame.midX, y: frame.midY)
    }

    @Test func aTapOnALinksTextOpensIt() throws {
        let editor = EditorHarness("See [the site](https://example.com) now, or www.apple.com")
        editor.textView.resignFirstResponder()
        editor.textView.layoutIfNeeded()
        var opened: URL?
        editor.controller.openURL = { opened = $0 }
        #expect(editor.textView.tapLinkForTesting(at: try center(of: NSRange(location: 4, length: 8), in: editor)))
        #expect(opened == URL(string: "https://example.com"))
        // An address written out goes to its secure site.
        #expect(editor.textView.tapLinkForTesting(at: try center(of: NSRange(location: 21, length: 13), in: editor)))
        #expect(opened == URL(string: "https://www.apple.com"))
        // Beside a link, on the same line, there's none.
        opened = nil
        #expect(!editor.textView.tapLinkForTesting(at: try center(of: NSRange(location: 13, length: 3), in: editor)))
        #expect(opened == nil)
    }

    /// Opened as Settings has it unless turned off, a web page shows over the page, in Safari's own
    /// view, from whatever is showing then.
    @Test func aWebPageShowsOverThePage() throws {
        EditorHarness.privatePreferences
        let editor = EditorHarness("See [the site](https://example.com) now")
        let root = UIViewController()
        editor.window.rootViewController = root
        root.view.addSubview(editor.textView)
        defer { root.dismiss(animated: false) }
        editor.controller.openLink(at: 5)
        let shown = try #require(root.presentedViewController as? SFSafariViewController)
        #expect(shown.isBeingPresented || shown.presentingViewController === root)
        // Up from the bottom, as a sheet, rather than across from the side.
        #expect(shown.modalPresentationStyle == .pageSheet)
    }

    /// The web pages a page links to that open over it are readied as it comes on screen: each
    /// once, in order, and only so many; mail is the mail app's, and with Settings saying the
    /// person's browser, none.
    @Test func thePagesWebLinksAreTheOnesReadied() throws {
        EditorHarness.privatePreferences
        let editor = EditorHarness("""
        [One](https://one.example) and [mail](mailto:sam@example.com)
        www.two.example, [one again](https://one.example)
        https://three.example
        """)
        let pages = ["https://one.example", "https://www.two.example", "https://three.example"].compactMap(URL.init(string:))
        #expect(editor.controller.linkedWebPages() == pages)
        #expect(editor.controller.linkedWebPages(limit: 2) == Array(pages.prefix(2)))
        Preferences.opensLinksInBite = false
        defer { Preferences.opensLinksInBite = true }
        #expect(editor.controller.linkedWebPages().isEmpty)
    }

    /// Every one of the text's taps gives way on a link, UIKit's own tap counting and tap-then-drag
    /// too, which aren't `UITapGestureRecognizer`s; holding down and dragging don't.
    @Test func everyTapGivesWayOnALink() throws {
        let tapClasses = ["UITextMultiTapRecognizer", "UITapAndAHalfRecognizer"].compactMap { NSClassFromString($0) as? UIGestureRecognizer.Type }
        #expect(tapClasses.count == 2)
        for tapClass in tapClasses {
            #expect(BiteTextView.isTap(tapClass.init(target: nil, action: nil)))
        }
        #expect(BiteTextView.isTap(UITapGestureRecognizer()))
        #expect(!BiteTextView.isTap(UILongPressGestureRecognizer()))
        #expect(!BiteTextView.isTap(UIPanGestureRecognizer()))
    }

    /// Where the first checkbox on the page is.
    private func checkbox(in editor: EditorHarness) throws -> CGPoint {
        let layoutManager = try #require(editor.textView.textLayoutManager)
        var checkbox: CGRect?
        layoutManager.enumerateTextLayoutFragments(from: layoutManager.documentRange.location, options: [.ensuresLayout]) { fragment in
            if let line = fragment as? BlockLayoutFragment, line.block.kind == .todo {
                checkbox = line.checkboxFrame
                return false
            }
            return true
        }
        let frame = try #require(checkbox)
        let inset = editor.textView.textContainerInset
        return CGPoint(x: frame.midX + inset.left, y: frame.midY + inset.top)
    }

    /// UIKit's tap counting waits a moment after a tap for the next, and takes it without asking
    /// whether it's on a link (user, 2026-10-05: a link tapped just after the link card was put
    /// away got the caret, and no card). A touch going down on a link or a checkbox cuts the run
    /// short first, so the tap is theirs; elsewhere the run goes on, for a double tap to select
    /// a word.
    @Test func aTouchOnALinkOrACheckboxCutsTheTextsTapRunShort() throws {
        let editor = EditorHarness("See [the site](https://example.com) now\n- [ ] task")
        editor.textView.layoutIfNeeded()
        editor.controller.canEditLinkInBar = { true }
        let run = MultiTapRun()
        editor.textView.addGestureRecognizer(run)
        defer { editor.textView.removeGestureRecognizer(run) }
        let touch = TouchEvent()
        _ = editor.textView.hitTest(try center(of: NSRange(location: 13, length: 3), in: editor), with: touch)
        #expect(run.timesCut == 0)
        _ = editor.textView.hitTest(try center(of: NSRange(location: 4, length: 8), in: editor), with: touch)
        #expect(run.timesCut == 1)
        _ = editor.textView.hitTest(try checkbox(in: editor), with: touch)
        #expect(run.timesCut == 2)
        #expect(run.isEnabled)
    }

    /// VoiceOver opens a page's links from its actions, one for each link.
    @Test func voiceOverOpensLinksFromThePagesActions() throws {
        let editor = EditorHarness("See [the site](https://example.com) or www.apple.com")
        var opened: URL?
        editor.controller.openURL = { opened = $0 }
        let actions = editor.textView.accessibilityCustomActions ?? []
        #expect(actions.map(\.name).suffix(2) == ["Open the site", "Open www.apple.com"])
        let open = try #require(actions.first { $0.name == "Open www.apple.com" })
        _ = open.actionHandler?(open)
        #expect(opened == URL(string: "https://www.apple.com"))
    }

    /// While the page is edited with no bar on the keys, a tap on a link's text is a tap on text:
    /// nothing opens.
    @Test func aLinkDoesntOpenWhileThePageIsEdited() throws {
        let editor = EditorHarness("See [the site](https://example.com) now")
        editor.textView.layoutIfNeeded()
        var opened: URL?
        editor.controller.openURL = { opened = $0 }
        #expect(editor.textView.isFirstResponder)
        #expect(!editor.textView.tapLinkForTesting(at: try center(of: NSRange(location: 4, length: 8), in: editor)))
        #expect(opened == nil)
    }
}

/// A touch going down, as the window hit-tests it.
private final class TouchEvent: UIEvent {
    override var type: UIEvent.EventType { .touches }
}

/// Stands in for UIKit's tap counting, `UITextMultiTapRecognizer`, which isn't a
/// `UITapGestureRecognizer`: counts the times its run is cut short, turned off and on again.
private final class MultiTapRun: UIGestureRecognizer {
    private(set) var timesCut = 0

    override var isEnabled: Bool {
        didSet { if !isEnabled { timesCut += 1 } }
    }
}
