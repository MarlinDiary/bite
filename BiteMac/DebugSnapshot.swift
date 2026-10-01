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

    /// `-snapshotDark` shows the dark appearance.
    static func prepare() {
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
        // `-snapshotSelect start length` selects text; `-snapshotScroller` shows the indicator.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            let page = panel.controllers[store.selection].textView
            if let index = arguments.firstIndex(of: "-snapshotSelect"), index + 2 < arguments.count,
               let start = Int(arguments[index + 1]), let length = Int(arguments[index + 2]) {
                page.setSelectedRange(NSRange(location: start, length: length), affinity: .downstream, stillSelecting: true)
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
                // As when the panel is kept open and another window takes the keyboard.
                panel.setKeepsOpenForSnapshot(true)
                let other = BitePanel(contentRect: NSRect(x: 0, y: 0, width: 60, height: 60), styleMask: [.borderless, .nonactivatingPanel],
                                      backing: .buffered, defer: false)
                other.makeKeyAndOrderFront(nil)
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    other.orderOut(nil)
                    panel.setKeepsOpenForSnapshot(false)
                }
            }
            if arguments.contains("-snapshotScroller") {
                (page.enclosingScrollView as? PageScrollView)?.showIndicatorForSnapshot()
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
                panel.showMenuForSnapshot()
            }
        }
    }

    /// Off the main thread, which an open menu keeps busy.
    nonisolated static func capture(after delay: Duration = .seconds(1.5), name: String = "panel") {
        Task.detached {
            try? await Task.sleep(for: delay)
            do {
                let content = try await SCShareableContent.currentProcess
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
