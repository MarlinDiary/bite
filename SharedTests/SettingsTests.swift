#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif
import Testing
import BiteKit
@testable import Bite

/// The choices in Settings, and what follows them.
@MainActor
@Suite(.serialized)
struct SettingsTests {
    init() {
        EditorHarness.privatePreferences
        Preferences.defaults.removePersistentDomain(forName: "BiteTests")
    }

    @Test func iCloudIsOnAndSpellingOffUntilChosen() {
        #expect(Preferences.syncsWithICloud)
        #expect(!Preferences.checksSpelling)
    }

    #if canImport(UIKit)
    /// A web page opens in Bite, over the page, until Settings says the person's browser; mail,
    /// and another app's links, always in the app for them.
    @Test func webPagesOpenInBiteUntilTurnedOff() throws {
        let page = try #require(URL(string: "https://example.com"))
        let mail = try #require(URL(string: "mailto:sam@example.com"))
        #expect(Preferences.opensLinksInBite)
        #expect(EditorController.opensInBite(page))
        #expect(!EditorController.opensInBite(mail))
        Preferences.opensLinksInBite = false
        #expect(!EditorController.opensInBite(page))
        Preferences.opensLinksInBite = true
        #expect(EditorController.opensInBite(page))
    }
    #endif

    @Test func hapticsAreOnUntilTurnedOff() {
        #expect(Preferences.playsHaptics)
        Preferences.playsHaptics = false
        #expect(!Preferences.playsHaptics)
        Preferences.playsHaptics = true
        #expect(Preferences.playsHaptics)
    }

    #if canImport(UIKit)
    /// A tapped checkbox clicks as it's ticked and gives softly as it's unticked, unless Settings
    /// turns haptics off.
    @Test func aCheckboxClicksAsItsTicked() throws {
        let editor = EditorHarness("text\n- [ ] task")
        let view = editor.textView
        view.layoutIfNeeded()
        let layoutManager = try #require(view.textLayoutManager)
        var checkbox: CGRect?
        layoutManager.enumerateTextLayoutFragments(from: layoutManager.documentRange.location, options: [.ensuresLayout]) { fragment in
            if let line = fragment as? BlockLayoutFragment, line.block.kind == .todo {
                checkbox = line.checkboxFrame
                return false
            }
            return true
        }
        let frame = try #require(checkbox)
        let point = CGPoint(x: frame.midX + view.textContainerInset.left, y: frame.midY + view.textContainerInset.top)

        view.tapCheckboxForTesting(at: point)
        #expect(editor.markdown == "text\n- [x] task")
        view.tapCheckboxForTesting(at: point)
        #expect(editor.markdown == "text\n- [ ] task")
        #expect(view.checkboxHapticsForTesting == [true, false])

        Preferences.playsHaptics = false
        defer { Preferences.playsHaptics = true }
        view.tapCheckboxForTesting(at: point)
        #expect(editor.markdown == "text\n- [x] task")
        #expect(view.checkboxHapticsForTesting == [true, false])
    }
    #endif

    /// Every page follows at once, and the change is told to whatever follows it.
    @Test func spellingIsCheckedOnEveryPageOnlyWhenChosen() async {
        let editors = [EditorHarness("a"), EditorHarness("b")]
        #expect(editors.allSatisfy { !Self.checksSpelling($0.textView) })
        await confirmation { told in
            let observer = NotificationCenter.default.addObserver(forName: Preferences.didChange, object: nil, queue: nil) { _ in
                told()
            }
            Preferences.checksSpelling = true
            NotificationCenter.default.removeObserver(observer)
        }
        #expect(editors.allSatisfy { Self.checksSpelling($0.textView) })
        Preferences.checksSpelling = false
        #expect(editors.allSatisfy { !Self.checksSpelling($0.textView) })
        // A page opened later starts as chosen.
        Preferences.checksSpelling = true
        #expect(Self.checksSpelling(EditorHarness("c").textView))
        Preferences.checksSpelling = false
    }

    private static func checksSpelling(_ view: BiteTextView) -> Bool {
        #if canImport(UIKit)
        view.spellCheckingType == .yes
        #else
        view.isContinuousSpellCheckingEnabled
        #endif
    }

    /// Every page goes back to how it came on first launch, and each one that changed goes to
    /// iCloud as a change made here.
    @Test func resettingPutsEveryPageBackAsItCame() {
        let store = DotStore(folder: FileManager.default.temporaryDirectory.appending(path: "BiteResetTests-\(UUID().uuidString)"))
        store.update(dot: 0, markdown: "mine\n")
        store.update(dot: 5, markdown: "more of mine\n")
        let revisions = store.revisions
        var changed: [Int] = []
        store.onLocalChange = { changed.append($0) }
        store.resetAllPages()
        for dot in 0..<DotPalette.count {
            #expect(store.markdown[dot] == SampleContent.markdown(for: dot))
            #expect(store.isEmpty[dot] == DotStore.isBlank(SampleContent.markdown(for: dot)))
        }
        #expect(changed == [0, 5])
        #expect(store.revisions[0] == revisions[0] + 1)
        #expect(store.revisions[1] == revisions[1])
    }

    #if canImport(UIKit)
    /// Code is never checked, chosen or not.
    @Test func codeIsNeverSpellChecked() {
        Preferences.checksSpelling = true
        defer { Preferences.checksSpelling = false }
        let editor = EditorHarness("```\nlet x\n```")
        editor.moveCaret(line: 1)
        #expect(editor.textView.isTypingCode)
        #expect(editor.textView.spellCheckingType == .no)
    }

    /// The screen stays on while Bite is in front, and a phone's Bite stays upright, only when
    /// chosen.
    @Test func theScreenStaysOnAndBiteUprightOnlyWhenChosen() {
        defer {
            Preferences.keepsScreenOn = false
            Preferences.locksPortrait = false
            ScreenChoices.apply()
        }
        #expect(!Preferences.keepsScreenOn)
        #expect(!Preferences.locksPortrait)
        ScreenChoices.apply()
        #expect(!UIApplication.shared.isIdleTimerDisabled)
        #expect(AppDelegate().application(.shared, supportedInterfaceOrientationsFor: nil) == .allButUpsideDown)

        Preferences.keepsScreenOn = true
        Preferences.locksPortrait = true
        ScreenChoices.apply()
        #expect(UIApplication.shared.isIdleTimerDisabled)
        #expect(AppDelegate().application(.shared, supportedInterfaceOrientationsFor: nil) == .portrait)
    }
    #else
    /// The Mac's panel is a page unless Liquid Glass is chosen in Settings, and follows the choice
    /// at once.
    @Test func thePanelIsGlassOnlyWhenChosen() {
        let store = DotStore(folder: FileManager.default.temporaryDirectory.appending(path: "BiteGlassTests-\(UUID().uuidString)"))
        let panel = PanelController(store: store, forTesting: true)
        #expect(!Preferences.panelIsGlass)
        #expect(!panel.backgroundIsGlassForTesting)
        Preferences.panelIsGlass = true
        #expect(panel.backgroundIsGlassForTesting)
        Preferences.panelIsGlass = false
        #expect(!panel.backgroundIsGlassForTesting)
    }

    /// Edit > Spelling > Check Spelling While Typing is the same choice, for every page.
    @Test func theEditMenusSpellingItemIsTheChoiceInSettings() {
        let editor = EditorHarness("a")
        let other = EditorHarness("b")
        editor.textView.toggleContinuousSpellChecking(nil)
        #expect(Preferences.checksSpelling)
        #expect(other.textView.isContinuousSpellCheckingEnabled)
        editor.textView.toggleContinuousSpellChecking(nil)
        #expect(!Preferences.checksSpelling)
        #expect(!other.textView.isContinuousSpellCheckingEnabled)
    }

    /// Selecting text doesn't bring up Writing Tools, and what an input method is composing is
    /// lit in the page's colour, as the selection is, and underlined in it where the input method
    /// asks for the system's accent, as Shuangpin does (it was the input method's orange).
    @Test func noWritingToolsAndComposingInThePagesColour() {
        let editor = EditorHarness("a")
        #expect(editor.textView.writingToolsBehavior == .none)
        let lit = editor.textView.markedTextAttributes?[.backgroundColor] as? NSColor
        #expect(lit == editor.textView.selectionColor)
        // As Shuangpin gives it.
        let composing = NSAttributedString(string: "ni", attributes: [
            .underlineStyle: NSUnderlineStyle.single.rawValue, .underlineColor: NSColor.controlAccentColor,
            .markedClauseSegment: 0, .backgroundColor: NSColor.controlAccentColor,
        ])
        let page = NSColor.systemRed
        let selection = NSColor.systemRed.withAlphaComponent(0.22)
        let shown = BiteTextView.inPageColour(composing, underline: page, highlight: selection) as? NSAttributedString
        let attributes = shown?.attributes(at: 0, effectiveRange: nil) ?? [:]
        #expect(attributes[.underlineColor] as? NSColor == page)
        #expect(attributes[.backgroundColor] as? NSColor == selection)
        #expect(attributes[.underlineStyle] as? Int == NSUnderlineStyle.single.rawValue)
        #expect(attributes[.markedClauseSegment] as? Int == 0)
        #expect(shown?.string == "ni")
        // Without an underline or highlight of its own, none is added.
        let plain = BiteTextView.inPageColour(NSAttributedString(string: "ni"), underline: page, highlight: selection) as? NSAttributedString
        #expect(plain?.attributes(at: 0, effectiveRange: nil).isEmpty == true)
    }
    #endif
}
