import Testing
@testable import IceMacOS27Core

@Suite("Translucent filled glyphs are usable")
struct FilledGlyph27Tests {
    @Test("A confined translucent square with an opaque outline is an icon")
    func filledSquare() {
        let width = 76, height = 48
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 6..<38 {
            for x in 22..<54 {
                let border = x < 25 || x >= 51 || y < 9 || y >= 35
                pixels[(y * width + x) * 4 + 3] = border ? 255 : 52
            }
        }
        #expect(!ItemImages27.keepsTheBar(pixels: pixels, width: width, height: height))
    }

    @Test("Haze extending to the capture edges is still rejected")
    func retainedBackground() {
        let width = 76, height = 48
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 22..<54 { pixels[(y * width + x) * 4 + 3] = y == 24 ? 255 : 52 }
        }
        #expect(ItemImages27.keepsTheBar(pixels: pixels, width: width, height: height))
    }
}
