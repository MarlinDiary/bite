import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

extension Color {
    /// The system's colours for text, for quieter text, and for a rule between things.
    static var systemLabel: Color {
        #if canImport(UIKit)
        Color(uiColor: .label)
        #else
        Color(nsColor: .labelColor)
        #endif
    }

    static var systemSecondaryLabel: Color {
        #if canImport(UIKit)
        Color(uiColor: .secondaryLabel)
        #else
        Color(nsColor: .secondaryLabelColor)
        #endif
    }

    static var systemSeparator: Color {
        #if canImport(UIKit)
        Color(uiColor: .separator)
        #else
        Color(nsColor: .separatorColor)
        #endif
    }
}
