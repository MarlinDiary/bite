import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

extension Color {
    /// The system's colours for text, for quieter text, and for a rule between things. A watch has
    /// none of them by name: its text is white on black, as the system's own apps' is.
    static var systemLabel: Color {
        #if os(watchOS)
        .white
        #elseif canImport(UIKit)
        Color(uiColor: .label)
        #else
        Color(nsColor: .labelColor)
        #endif
    }

    static var systemSecondaryLabel: Color {
        #if os(watchOS)
        .white.opacity(0.6)
        #elseif canImport(UIKit)
        Color(uiColor: .secondaryLabel)
        #else
        Color(nsColor: .secondaryLabelColor)
        #endif
    }

    static var systemSeparator: Color {
        #if os(watchOS)
        .white.opacity(0.2)
        #elseif canImport(UIKit)
        Color(uiColor: .separator)
        #else
        Color(nsColor: .separatorColor)
        #endif
    }
}
