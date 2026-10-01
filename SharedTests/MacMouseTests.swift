#if !canImport(UIKit)
import AppKit
import Testing
@testable import Bite

/// Clicks and drags in a page on the Mac, as AppKit hands them to the text view.
@MainActor
@Suite(.serialized)
struct MacMouseTests {
    private func editor(_ markdown: String) -> EditorHarness {
        let editor = EditorHarness(markdown)
        editor.window.makeKeyAndOrderFront(nil)
        editor.window.makeFirstResponder(editor.textView)
        if let manager = editor.textView.textLayoutManager { manager.ensureLayout(for: manager.documentRange) }
        return editor
    }

    private func event(_ type: NSEvent.EventType, at point: NSPoint, in editor: EditorHarness,
                       modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: editor.textView.convert(point, to: nil), modifierFlags: modifiers,
                           timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: editor.window.windowNumber,
                           context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1)!
    }

    /// Presses at `start`, drags through `path` and lets go at its last point. The text view
    /// tracks the drag itself, taking the queued events as they come.
    private func drag(in editor: EditorHarness, from start: NSPoint, through path: [NSPoint],
                      modifiers: NSEvent.ModifierFlags = []) {
        for point in path {
            NSApp.postEvent(event(.leftMouseDragged, at: point, in: editor, modifiers: modifiers), atStart: false)
        }
        NSApp.postEvent(event(.leftMouseUp, at: path.last ?? start, in: editor, modifiers: modifiers), atStart: false)
        editor.textView.mouseDown(with: event(.leftMouseDown, at: start, in: editor, modifiers: modifiers))
    }

    /// Where character `location` is drawn, in the text view.
    private func point(of location: Int, in editor: EditorHarness) -> NSPoint {
        let view = editor.textView
        let onScreen = view.firstRect(forCharacterRange: NSRange(location: location, length: 1), actualRange: nil)
        let inWindow = editor.window.convertPoint(fromScreen: NSPoint(x: onScreen.minX + 1, y: onScreen.midY))
        return view.convert(inWindow, from: nil)
    }

    private var blank: NSPoint { NSPoint(x: 120, y: 700) }

    /// Runs the main run loop in its default mode, as it is once a menu has gone, for `duration`
    /// or until `done`. Other tests' work on it may come first.
    private static func runLoop(for duration: Duration, until done: () -> Bool = { false }) {
        let deadline = ContinuousClock.now + duration
        while !done(), ContinuousClock.now < deadline {
            RunLoop.main.run(mode: .default, before: .now + 0.01)
        }
    }

    /// A press below the text puts the caret at its end, and a drag that stays down there
    /// selects nothing.
    @Test func aPressBelowTheTextPutsTheCaretAtTheEnd() {
        let editor = editor("first line here\nsecond")
        editor.moveCaret(line: 0, column: 3)
        let end = (editor.textView.string as NSString).length - 1
        drag(in: editor, from: blank, through: [NSPoint(x: 40, y: 720), NSPoint(x: 300, y: 650)])
        #expect(editor.textView.selectedRange == NSRange(location: end, length: 0))
    }

    /// Pressed below the text and dragged up into it, the text from there to the end is
    /// selected. It only moved the caret.
    @Test func aDragUpFromBelowTheTextSelectsToTheEnd() {
        let editor = editor("first line here\nsecond")
        let end = (editor.textView.string as NSString).length - 1
        let target = point(of: 2, in: editor)
        drag(in: editor, from: blank, through: [NSPoint(x: target.x, y: 400), target])
        #expect(editor.textView.selectedRange == NSRange(location: 2, length: end - 2))
        // Back down below the text, it's the end again.
        drag(in: editor, from: blank, through: [target, blank])
        #expect(editor.textView.selectedRange == NSRange(location: end, length: 0))
    }

    /// With Shift held, the selection runs on from where it was to the end.
    @Test func shiftClickingBelowTheTextSelectsOnToTheEnd() {
        let editor = editor("first line here\nsecond")
        let end = (editor.textView.string as NSString).length - 1
        editor.moveCaret(line: 0, column: 3)
        drag(in: editor, from: blank, through: [], modifiers: .shift)
        #expect(editor.textView.selectedRange == NSRange(location: 3, length: end - 3))
    }

    /// A row of Bite's menus clicked sends its action only once the menu has gone, as AppKit's
    /// rows do. Sent at once, Settings opened with the menu still up.
    @Test func aClickedMenuRowWaitsForTheMenuToGo() {
        final class Target: NSObject {
            var sent = 0
            @objc func act(_ sender: Any?) { sent += 1 }
        }
        let target = Target()
        let menu = NSMenu()
        menu.delegate = MenuRow.keyboard
        let item = MenuRow.item("Do It", symbol: "gearshape", action: #selector(Target.act(_:)), target: target, tint: .systemRed)
        menu.addItem(item)
        let click = NSEvent.mouseEvent(with: .leftMouseUp, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                       context: nil, eventNumber: 0, clickCount: 1, pressure: 0)!
        item.view?.mouseUp(with: click)
        #expect(target.sent == 0)
        MenuRow.keyboard.menuDidClose(menu)
        #expect(target.sent == 0)
        Self.runLoop(for: .seconds(1)) { target.sent > 0 }
        #expect(target.sent == 1)
        // Closed again, nothing more is sent.
        MenuRow.keyboard.menuDidClose(menu)
        Self.runLoop(for: .milliseconds(100))
        #expect(target.sent == 1)
    }

    /// Bite's menus are made for each showing and let go once closed, before the row's action
    /// goes. Sent through its menu, it never went, and Settings didn't open.
    @Test func aClickedRowsActionGoesOnceItsMenuIsGone() {
        final class Target: NSObject {
            var sent = 0
            @objc func act(_ sender: Any?) { sent += 1 }
        }
        let target = Target()
        weak var gone: NSMenu?
        let click = NSEvent.mouseEvent(with: .leftMouseUp, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                       context: nil, eventNumber: 0, clickCount: 1, pressure: 0)!
        autoreleasepool {
            let menu = NSMenu()
            menu.delegate = MenuRow.keyboard
            let item = MenuRow.item("Do It", symbol: "gearshape", action: #selector(Target.act(_:)), target: target, tint: .systemRed)
            menu.addItem(item)
            item.view?.mouseUp(with: click)
            MenuRow.keyboard.menuDidClose(menu)
            gone = menu
        }
        #expect(gone == nil)
        Self.runLoop(for: .seconds(1)) { target.sent > 0 }
        #expect(target.sent == 1)
    }

    /// Dragged on up past the first line, the selection holds, as AppKit's own drags do: between
    /// the page's top and the first line it reaches that line, and above the page, the start.
    /// It let go of the selection there, leaving only the caret at the end.
    @Test func aDragFromBelowOnPastTheTopKeepsSelecting() {
        let editor = editor("first line here\nsecond line\nthird")
        let view = editor.textView
        let end = (view.string as NSString).length - 1
        let inFirstLine = point(of: 3, in: editor)
        drag(in: editor, from: blank, through: [inFirstLine, NSPoint(x: inFirstLine.x, y: 4)])
        #expect(view.selectedRange.location <= 4)
        #expect(NSMaxRange(view.selectedRange) == end)
        drag(in: editor, from: blank, through: [inFirstLine, NSPoint(x: 60, y: -30)])
        #expect(view.selectedRange == NSRange(location: 0, length: end))
        // The same from in the text.
        drag(in: editor, from: point(of: 20, in: editor), through: [inFirstLine, NSPoint(x: 60, y: -30)])
        #expect(view.selectedRange == NSRange(location: 0, length: 20))
    }

    /// In the text, AppKit's own selecting goes on as before.
    @Test func aDragInTheTextSelectsAsBefore() {
        let editor = editor("first line here\nsecond")
        drag(in: editor, from: point(of: 1, in: editor), through: [point(of: 5, in: editor)])
        #expect(editor.textView.selectedRange == NSRange(location: 1, length: 4))
    }
}
#endif
