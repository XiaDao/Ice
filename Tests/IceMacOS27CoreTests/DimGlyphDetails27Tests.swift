import Testing
@testable import IceMacOS27Core

@Suite("Dim glyph details survive background removal")
struct DimGlyphDetails27Tests {
    let size = 28

    func capture(background: [Double], foreground: [Double], alpha: (Int, Int) -> Double) -> [UInt8] {
        var pixels = [UInt8]()
        for y in 0..<size {
            for x in 0..<size {
                let a = alpha(x, y)
                pixels += (0..<3).map { UInt8((background[$0] + a * (foreground[$0] - background[$0])).rounded()) }
                pixels.append(255)
            }
        }
        return pixels
    }

    func extract(_ pixels: [UInt8], tone: ItemImages27.GlyphTone) -> [UInt8] {
        let background = ItemImages27.backgroundColor(pixels: pixels, width: size, height: size)
        let matte = ItemImages27.removingBackground(pixels: pixels, width: size, height: size, background: background, tone: tone)
        return ItemImages27.droppingFaintMarks(pixels: matte, width: size, height: size, preserveDimDetails: ItemImages27.hasSmoothBackground(pixels: pixels, width: size, height: size))
    }

    @Test("All nine dots survive, including intentionally dim disconnected dots")
    func nineDots() {
        let centers = [6, 13, 20]
        let pixels = capture(background: [20, 20, 110], foreground: [245, 245, 245]) { x, y in
            for cy in centers {
                for cx in centers where (x - cx) * (x - cx) + (y - cy) * (y - cy) <= 2 {
                    return cy == 20 ? 1 : 0.3
                }
            }
            return 0
        }
        let result = extract(pixels, tone: .light)
        for y in centers {
            for x in centers { #expect(result[(y * size + x) * 4 + 3] >= 65) }
        }
        #expect(result[3] == 0)
    }

    @Test("A dim ring remains separate from its bright badge in both glyph tones")
    func ringAndBadge() {
        for light in [true, false] {
            let pixels = capture(background: light ? [20, 20, 100] : [220, 230, 240], foreground: light ? [245, 245, 245] : [15, 15, 15]) { x, y in
                if (19...22).contains(x), (19...23).contains(y) { return 1 }
                let radius = Double((x - 12) * (x - 12) + (y - 12) * (y - 12)).squareRoot()
                return radius >= 6 && radius <= 8 ? 0.3 : 0
            }
            let result = extract(pixels, tone: light ? .light : .dark)
            #expect(result[(5 * size + 12) * 4 + 3] >= 65)
            #expect(result[(12 * size + 5) * 4 + 3] >= 65)
            #expect(result[(21 * size + 20) * 4 + 3] > 240)
            #expect(result[(12 * size + 12) * 4 + 3] == 0)
        }
    }

    @Test("Smooth gradients still clear and detached one-pixel streaks remain noise")
    func backgroundAndNoise() {
        let pixels = capture(background: [25, 25, 100], foreground: [245, 245, 245]) { x, y in
            if (10...14).contains(x), (10...14).contains(y) { return 1 }
            if x == 23, (4...8).contains(y) { return 0.3 }
            return 0
        }
        let result = extract(pixels, tone: .light)
        #expect(result[(6 * size + 23) * 4 + 3] == 0)
        #expect(result[(12 * size + 12) * 4 + 3] == 255)
    }
}
