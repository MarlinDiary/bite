import Foundation

public enum ColorMath {
    /// Moves a colour's OKLab lightness by `delta` (roughly -1...1) and keeps its hue and
    /// chroma, so darker shades stay saturated instead of turning muddy like a mix with black.
    public static func adjustingLightness(_ hex: UInt32, by delta: Double) -> UInt32 {
        func toLinear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        func toGamma(_ c: Double) -> Double { c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1 / 2.4) - 0.055 }

        let r = toLinear(Double((hex >> 16) & 0xFF) / 255)
        let g = toLinear(Double((hex >> 8) & 0xFF) / 255)
        let b = toLinear(Double(hex & 0xFF) / 255)

        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        let lightness = min(max(0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s + delta, 0), 1)
        let labA = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
        let labB = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s

        let l3 = pow(lightness + 0.3963377774 * labA + 0.2158037573 * labB, 3)
        let m3 = pow(lightness - 0.1055613458 * labA - 0.0638541728 * labB, 3)
        let s3 = pow(lightness - 0.0894841775 * labA - 1.2914855480 * labB, 3)
        let channels = [
            4.0767416621 * l3 - 3.3077115913 * m3 + 0.2309699292 * s3,
            -1.2684380046 * l3 + 2.6097574011 * m3 - 0.3413193965 * s3,
            -0.0041960863 * l3 - 0.7034186147 * m3 + 1.7076147010 * s3,
        ].map { UInt32((min(max(toGamma($0), 0), 1) * 255).rounded()) }
        return channels[0] << 16 | channels[1] << 8 | channels[2]
    }
}
