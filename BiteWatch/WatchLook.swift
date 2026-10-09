import SwiftUI
import BiteKit

/// How a page looks on the watch: on black, as the system's own apps are, its dot's colour a deep
/// wash from the top down, rather than the phone's pale paper.
enum WatchLook {
    /// The page's colour behind it: its dot's, deepened, fading toward black with the system's own
    /// gradient for a page's background.
    static func background(_ ink: DotColor) -> some ShapeStyle {
        Color(platform: PlatformColor(hex: ColorMath.adjustingLightness(ink.dark, by: -0.2))).gradient
    }

    /// The editor's sizes for a page's lines, scaled as the watch's body text is, at the person's
    /// text size.
    static func metrics(textSize: CGFloat) -> GlanceMetrics {
        GlanceMetrics(scale: textSize / 17)
    }

    /// The watch's body text at its usual size, which the person's text size scales.
    static let textSize: CGFloat = 16

    /// What an empty page says, as its widget does.
    static let emptyLine = "Nothing here yet"
    static let emptySizes: (title: CGFloat, line: CGFloat) = (24, 15)
}
