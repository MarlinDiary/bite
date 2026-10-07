import Testing
@testable import BiteKit

struct ColorMathTests {
    private func channels(_ hex: UInt32) -> [Int] {
        [Int((hex >> 16) & 0xFF), Int((hex >> 8) & 0xFF), Int(hex & 0xFF)]
    }

    @Test(arguments: DotPalette.colors.flatMap { [$0.light, $0.dark] })
    func zeroDeltaKeepsTheColour(_ hex: UInt32) {
        let result = channels(ColorMath.adjustingLightness(hex, by: 0))
        for (a, b) in zip(result, channels(hex)) {
            #expect(abs(a - b) <= 1)
        }
    }

    @Test func darkerStaysSaturated() {
        // Darkening yellow in OKLab keeps it clearly yellow: red and green stay well above blue.
        let darker = channels(ColorMath.adjustingLightness(0xD9A21B, by: -0.10))
        #expect(darker[0] < 0xD9 && darker[1] < 0xA2)
        #expect(darker[0] - darker[2] > 120)
    }

    /// In linear light: white's is 1, black's 0, and sRGB's middle grey, 0x80, about a fifth.
    @Test func brightestChannelIsInLinearLight() {
        #expect(ColorMath.brightestChannel(of: 0xFFFFFF) == 1)
        #expect(ColorMath.brightestChannel(of: 0x000000) == 0)
        #expect(abs(ColorMath.brightestChannel(of: 0x808080) - 0.216) < 0.001)
        #expect(ColorMath.brightestChannel(of: 0x2080FF) == 1)
        #expect(ColorMath.brightestChannel(of: 0x802010) == ColorMath.brightestChannel(of: 0x808080))
    }
}
