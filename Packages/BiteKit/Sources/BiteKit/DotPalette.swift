import Foundation

/// A dot's colour, as sRGB hex for light and dark appearance.
public struct DotColor: Sendable, Hashable {
    public let name: String
    public let light: UInt32
    public let dark: UInt32
}

public enum DotPalette {
    /// Earthy, slightly muted tones that read as one set rather than a rainbow. In order they
    /// go once round the colour wheel, from yellow through red and blue back to green.
    public static let colors: [DotColor] = [
        DotColor(name: "Yellow", light: 0xD9A21B, dark: 0xF0C041),
        DotColor(name: "Orange", light: 0xDD7B2C, dark: 0xF29A4E),
        DotColor(name: "Red", light: 0xD4523F, dark: 0xEE735F),
        DotColor(name: "Purple", light: 0x8C5BB6, dark: 0xB083DB),
        DotColor(name: "Blue", light: 0x4A6FC4, dark: 0x7394E6),
        DotColor(name: "Teal", light: 0x2E8F8C, dark: 0x4FB5B1),
        DotColor(name: "Green", light: 0x5E9E4A, dark: 0x7FBF69),
    ]

    /// The neutral grey a dot shows while it's empty. Lighter than the colours so empty dots recede.
    public static let empty = DotColor(name: "Empty", light: 0xBEBEC2, dark: 0x5E5E62)

    public static var count: Int { colors.count }
}

extension DotColor {
    /// The colour's name in the language Bite is shown in. `name` stays as it is, English, as it
    /// names Bite's pictures and icons too.
    public var localizedName: String {
        Bundle.module.localizedString(forKey: name, value: name, table: nil)
    }

    /// What a page with no title of its own is called: "Yellow Dot".
    public var pageName: String {
        String(format: String(localized: "%@ Dot", bundle: .module), localizedName)
    }
}
