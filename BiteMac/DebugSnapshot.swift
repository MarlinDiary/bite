#if DEBUG
import AppKit
import ScreenCaptureKit

/// For checking the look without a screen recording permission: launched with `-snapshot`, the
/// app opens its panel and prints pictures of its own windows, which an app may capture
/// without asking.
enum DebugSnapshot {
    static var isRequested: Bool {
        CommandLine.arguments.contains("-snapshot")
    }

    /// `-snapshotDark` shows the dark appearance, and `-snapshotGlass` the glass panel. The choices
    /// in Settings are the run's own, never the person's.
    static func prepare() {
        guard isRequested else { return }
        let defaults = UserDefaults(suiteName: "BiteSnapshot")!
        defaults.removePersistentDomain(forName: "BiteSnapshot")
        Preferences.defaults = defaults
        if CommandLine.arguments.contains("-snapshotGlass") {
            Preferences.panelIsGlass = true
        }
        if CommandLine.arguments.contains("-snapshotDark") {
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    /// Shows what the launch arguments ask for, then captures it: `-snapshotDot N` picks a dot,
    /// `-snapshotMenu` opens the "…" menu, `-snapshotSettings` the Settings window.
    static func run(panel: PanelController, store: DotStore) {
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "-snapshotDot"), index + 1 < arguments.count, let dot = Int(arguments[index + 1]) {
            store.selection = dot
        }
        panel.showOnceRingIsPlaced()
        // `-snapshotSelect start length` selects text; `-snapshotScroller` shows the indicator;
        // `-snapshotDetached` shows the panel as dragged away from the ring.
        // `-snapshotPage MARKDOWN` puts MARKDOWN, with "\n" for line breaks, on the page shown.
        if let index = arguments.firstIndex(of: "-snapshotPage"), index + 1 < arguments.count {
            panel.controllers[store.selection].load(markdown: arguments[index + 1].replacingOccurrences(of: "\\n", with: "\n"))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            let page = panel.controllers[store.selection].textView
            if let index = arguments.firstIndex(of: "-snapshotSelect"), index + 2 < arguments.count,
               let start = Int(arguments[index + 1]), let length = Int(arguments[index + 2]) {
                page.setSelectedRange(NSRange(location: start, length: length), affinity: .downstream, stillSelecting: true)
            }
            // `-snapshotMarked TEXT` has an input method composing TEXT at the end of the page,
            // underlined in the system's accent as Shuangpin asks.
            if let index = arguments.firstIndex(of: "-snapshotMarked"), index + 1 < arguments.count {
                page.window?.makeFirstResponder(page)
                page.setSelectedRange(NSRange(location: page.string.utf16.count - 1, length: 0))
                let text = arguments[index + 1]
                let composing = NSAttributedString(string: text, attributes: [
                    .underlineStyle: NSUnderlineStyle.single.rawValue, .underlineColor: NSColor.controlAccentColor,
                    .markedClauseSegment: 0,
                ])
                page.setMarkedText(composing, selectedRange: NSRange(location: text.utf16.count, length: 0),
                                   replacementRange: NSRange(location: NSNotFound, length: 0))
            }
            if arguments.contains("-snapshotLayers") {
                func dump(_ view: NSView, _ depth: Int) {
                    let layers = (view.layer?.sublayers ?? []).map { "\(type(of: $0))" }.joined(separator: ",")
                    print("LAYERS " + String(repeating: "  ", count: depth) + "\(type(of: view)) frame \(view.frame) layers [\(layers)]")
                    view.subviews.forEach { dump($0, depth + 1) }
                }
                dump(page, 0)
            }
            if arguments.contains("-snapshotInactive") {
                // As when the panel's been dragged away from the ring and another window takes the
                // keyboard.
                panel.placement.isDetached = true
                let other = BitePanel(contentRect: NSRect(x: 0, y: 0, width: 60, height: 60), styleMask: [.borderless, .nonactivatingPanel],
                                      backing: .buffered, defer: false)
                other.makeKeyAndOrderFront(nil)
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    other.orderOut(nil)
                }
            }
            if arguments.contains("-snapshotScroller") {
                (page.enclosingScrollView as? PageScrollView)?.showIndicatorForSnapshot()
            }
            if arguments.contains("-snapshotDetached") {
                panel.placement.isDetached = true
            }
            // `-snapshotLink` brings the link card up for the selection, or the link the caret's in;
            // `-snapshotLinkHover` the pill, as for the pointer on the link at the caret.
            // `-snapshotLinkComing` brings the card up just before the capture, its coming slowed,
            // to see it halfway.
            if arguments.contains("-snapshotLink") {
                page.window?.makeFirstResponder(page)
                panel.controllers[store.selection].perform(.link)
                // `-snapshotLinkTextRow` moves the keys up to the text row.
                if arguments.contains("-snapshotLinkTextRow") {
                    let card = panel.linkCardForTesting
                    card.typeNameForTesting(card.nameForTesting)
                }
                // `-snapshotLinkSelectAll` selects what's in the row with the keys, to see its colour.
                if arguments.contains("-snapshotLinkSelectAll") {
                    page.window?.firstResponder?.tryToPerform(#selector(NSText.selectAll(_:)), with: nil)
                }
            }
            if arguments.contains("-snapshotLinkComing") {
                LinkCard.animationSlowdown = 20
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                    page.window?.makeFirstResponder(page)
                    panel.controllers[store.selection].perform(.link)
                }
            }
            if arguments.contains("-snapshotLinkHover") {
                let controller = panel.controllers[store.selection]
                if let link = controller.link(at: page.selectedRange().location) {
                    panel.hoverForTesting(link, on: controller)
                }
            }
        }
        if arguments.contains("-snapshotSettings") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                (NSApp.delegate as? AppDelegate)?.showSettings(nil)
            }
        }
        capture(after: .seconds(arguments.contains("-snapshotScroller") ? 1.1 : 2))
        if arguments.contains("-snapshotMenu") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                // `-snapshotMenuDown N` moves the menu's highlight down N items, as the arrow key
                // does: the keys wait in the queue for the menu to take them.
                if let index = arguments.firstIndex(of: "-snapshotMenuDown"), index + 1 < arguments.count,
                   let count = Int(arguments[index + 1]) {
                    let arrow = String(UnicodeScalar(UInt16(NSDownArrowFunctionKey))!)
                    for _ in 0..<count {
                        if let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                                        windowNumber: 0, context: nil, characters: arrow,
                                                        charactersIgnoringModifiers: arrow, isARepeat: false, keyCode: 125) {
                            NSApp.postEvent(event, atStart: false)
                        }
                    }
                    // `-snapshotMenuRight` then opens the highlighted row's own menu.
                    if arguments.contains("-snapshotMenuRight") {
                        let right = String(UnicodeScalar(UInt16(NSRightArrowFunctionKey))!)
                        if let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                                        windowNumber: 0, context: nil, characters: right,
                                                        charactersIgnoringModifiers: right, isARepeat: false, keyCode: 124) {
                            NSApp.postEvent(event, atStart: false)
                        }
                    }
                    // `-snapshotMenuReturn` then chooses the highlighted item, and `-snapshotMenuEscape`
                    // closes the menu, each with the key going down and back up.
                    for (flag, key, code) in [("-snapshotMenuReturn", "\r", UInt16(36)), ("-snapshotMenuEscape", "\u{1b}", 53)]
                    where arguments.contains(flag) {
                        for type in [NSEvent.EventType.keyDown, .keyUp] {
                            if let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: 0,
                                                            windowNumber: 0, context: nil, characters: key,
                                                            charactersIgnoringModifiers: key, isARepeat: false, keyCode: code) {
                                NSApp.postEvent(event, atStart: false)
                            }
                        }
                    }
                }
                panel.showMenuForSnapshot()
            }
        }
        if arguments.contains("-snapshotShare") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                panel.shareForSnapshot()
            }
        }
    }

    /// Off the main thread, which an open menu keeps busy.
    nonisolated static func capture(after delay: Duration = .seconds(1.5), name: String = "panel") {
        Task.detached {
            try? await Task.sleep(for: delay)
            do {
                let content = try await SCShareableContent.currentProcess
                // `-snapshotDisplay` also captures the display with only Bite's windows on it, at the
                // screen's own pixels: a menu's own capture comes back as the panel and its menus
                // together, scaled down into the menu's size.
                if CommandLine.arguments.contains("-snapshotDisplay"),
                   let menu = content.windows.first(where: { $0.isOnScreen && $0.windowLayer == 101 }),
                   let display = content.displays.first(where: { $0.frame.intersects(menu.frame) }) {
                    let windows = content.windows.filter { $0.isOnScreen && $0.windowLayer >= 0 && $0.windowLayer != 24 }
                    let filter = SCContentFilter(display: display, including: windows)
                    let configuration = SCStreamConfiguration()
                    configuration.width = Int(display.frame.width * 2)
                    configuration.height = Int(display.frame.height * 2)
                    configuration.showsCursor = false
                    let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
                    let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) ?? Data()
                    for window in windows { print("SNAPSHOT window \(window.frame) layer \(window.windowLayer)") }
                    print("SNAPSHOT display \(display.frame)")
                    print("PNG display \(png.base64EncodedString())")
                }
                // Not the desktop or the menu bar, which come with every app's windows.
                for (index, window) in content.windows.enumerated() where window.isOnScreen && window.windowLayer >= 0 && window.windowLayer != 24 {
                    let filter = SCContentFilter(desktopIndependentWindow: window)
                    let configuration = SCStreamConfiguration()
                    let scale = window.windowLayer > 0 ? 4.0 : 2.0
                    configuration.width = Int(window.frame.width * scale)
                    configuration.height = Int(window.frame.height * scale)
                    configuration.showsCursor = false
                    configuration.ignoreShadowsSingleWindow = false
                    let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
                    let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) ?? Data()
                    // The app's own folder can't be read from outside its sandbox, so the picture
                    // goes out on standard output.
                    print("SNAPSHOT \(name)-\(index) frame \(window.frame) layer \(window.windowLayer)")
                    print("PNG \(name)-\(index) \(png.base64EncodedString())")
                }
            } catch {
                // With the screen locked nothing can be captured. The windows draw themselves
                // instead, all but the glass, which only the window server draws.
                print("SNAPSHOT failed: \(error); drawing instead")
                await MainActor.run {
                    for (index, window) in NSApp.windows.enumerated() where window.isVisible {
                        guard let view = window.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                        view.cacheDisplay(in: view.bounds, to: rep)
                        let png = rep.representation(using: .png, properties: [:]) ?? Data()
                        print("SNAPSHOT \(name)-drawn-\(index) frame \(window.frame)")
                        print("PNG \(name)-drawn-\(index) \(png.base64EncodedString())")
                    }
                }
            }
            print("SNAPSHOT done")
            fflush(stdout)
        }
    }
}
#endif
