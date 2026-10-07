import Testing
import SwiftUI
import CoreGraphics
import BiteKit
@testable import Bite

/// The dot of the page on screen glows when Settings says so: on a screen that can show it, HDR,
/// it's lit past white, as nothing else is.
@MainActor
struct DotGlowTests {
    init() {
        EditorHarness.privatePreferences
    }

    /// Draws `view` HDR, as a screen that can show it does.
    private func hdr<Content: View>(_ view: Content) -> ImageRenderer<Content> {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        renderer.allowedDynamicRange = .high
        return renderer
    }

    /// `dot` as the dot bar lays each dot out, dimmed as one piece when touched.
    private func inTheBar(_ dot: DotIndicator, _ scheme: ColorScheme = .light) -> ImageRenderer<some View> {
        hdr(dot.frame(width: 30, height: 44).compositingGroup().opacity(1).environment(\.colorScheme, scheme))
    }

    /// What `renderer` draws, row by row: each pixel's brightest channel, in linear light where 1
    /// is white, and whether anything is drawn there.
    private func rows(_ renderer: ImageRenderer<some View>) throws -> [[(value: Float, isDrawn: Bool)]] {
        let image = try #require(renderer.cgImage)
        let space = try #require(CGColorSpace(name: CGColorSpace.extendedLinearSRGB))
        let width = image.width, height = image.height
        var pixels = [Float](repeating: 0, count: width * height * 4)
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.floatComponents.rawValue
            | CGImageByteOrderInfo.order32Little.rawValue
        let context = try #require(CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 32,
                                             bytesPerRow: width * 16, space: space, bitmapInfo: info))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return (0..<height).map { y in
            (0..<width).map { x in
                let i = (y * width + x) * 4
                return (max(pixels[i], pixels[i + 1], pixels[i + 2]), pixels[i + 3] > 0)
            }
        }
    }

    /// The brightest any channel of what `renderer` draws comes out.
    private func brightest(_ renderer: ImageRenderer<some View>) throws -> Float {
        try rows(renderer).joined().map(\.value).max() ?? 0
    }

    @Test func thePageOnScreensDotIsLitPastWhite() throws {
        let ink = DotPalette.colors[1]
        let glowing = try brightest(inTheBar(DotIndicator(ink: ink, isSelected: true, glows: true)))
        let plain = try brightest(inTheBar(DotIndicator(ink: ink, isSelected: true)))
        #expect(plain <= 1.01, "\(plain)")
        #expect(glowing > 1.2, "\(glowing)")
        #expect(glowing > plain * 1.6, "\(glowing) against \(plain)")
    }

    /// Only the page on screen's: a dot not selected, and the icon picker's, are their colour.
    @Test func otherDotsAreTheirColour() throws {
        let ink = DotPalette.colors[1]
        #expect(try brightest(inTheBar(DotIndicator(ink: ink, isSelected: false, glows: true))) <= 1.01)
        #expect(try brightest(inTheBar(DotIndicator(ink: ink, isSelected: true, glows: false))) <= 1.01)
    }

    /// Every colour's is lit as brightly, the darker ones' as the lighter, in light and dark
    /// appearance.
    @Test func everyDotIsLitAsBrightly() throws {
        for scheme in [ColorScheme.light, .dark] {
            for ink in DotPalette.colors {
                let glowing = try brightest(inTheBar(DotIndicator(ink: ink, isSelected: true, glows: true), scheme))
                #expect(abs(glowing - Float(DotIndicator.glow)) < 0.1, "\(ink.name), \(scheme): \(glowing)")
            }
        }
    }

    /// Its light is added over the whole dot, so the shade the rim casts at the top is past white
    /// too, though still the darker end: the dot still looks set into the bar.
    @Test func theShadeAtTheTopIsLitToo() throws {
        for scheme in [ColorScheme.light, .dark] {
            for ink in DotPalette.colors {
                let image = try rows(inTheBar(DotIndicator(ink: ink, isSelected: true, glows: true), scheme))
                let middle = image.map { $0[$0.count / 2] }.filter(\.isDrawn).map(\.value)
                // The row under the top edge, which is partly the background's.
                let top = middle[1], bottom = try #require(middle.max())
                #expect(top > 1.05 && top < bottom * 0.97, "\(ink.name), \(scheme): \(top) to \(bottom)")
            }
        }
    }

    /// Off until chosen in Settings, and then the dot bar's lights up, and goes out, as chosen:
    /// the page on screen's, when it has something on it. An empty page's stays grey, which lit
    /// past white is white.
    @Test func theDotBarsGlowsOnlyOnceChosen() throws {
        let store = DotStore(folder: FileManager.default.temporaryDirectory.appending(path: "BiteGlowTests-\(UUID().uuidString)"))
        store.update(dot: 1, isEmpty: false)
        store.update(dot: 4, isEmpty: true)
        let bar = hdr(DotSwitcher(selection: .constant(1), highlighted: 1).environment(store))
        let onAnEmptyPage = hdr(DotSwitcher(selection: .constant(4), highlighted: 4).environment(store))
        #expect(!Preferences.dotGlows)
        #expect(try brightest(bar) <= 1.01)

        Preferences.dotGlows = true
        defer { Preferences.dotGlows = false }
        // The bar takes the change as the run loop turns, before the screen is next drawn.
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.001))
        let glowing = try brightest(bar)
        #expect(glowing > 1.7, "\(glowing)")
        #expect(try brightest(onAnEmptyPage) <= 1.01)

        Preferences.dotGlows = false
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.001))
        #expect(try brightest(bar) <= 1.01)
    }
}
