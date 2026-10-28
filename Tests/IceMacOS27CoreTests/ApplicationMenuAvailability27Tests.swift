import CoreGraphics
import Testing
@testable import IceMacOS27Core

@Suite("Application menus must never become Ice empty space during an incomplete AX read")
struct ApplicationMenuAvailability27Tests {
    let bar = CGRect(x: 0, y: 0, width: 1512, height: 33)
    let titles = [
        CGRect(x: 10, y: 0, width: 35, height: 33),
        CGRect(x: 65, y: 0, width: 120, height: 33),
        CGRect(x: 200, y: 0, width: 50, height: 33),
        CGRect(x: 900, y: 0, width: 50, height: 33),
    ]

    @Test("Every drawn title contributes to the measurement, independent of whether it is enabled")
    func allTitlesOccupySpace() {
        #expect(ApplicationMenuArea27.measuredFrame(titleFrames: titles) == CGRect(x: 10, y: 0, width: 940, height: 33))
    }

    @Test("A missing trailing title must invalidate the short partial measurement")
    func partialRead() {
        let frame = ApplicationMenuArea27.measuredFrame(titleFrames: [titles[0], titles[1], nil])
        #expect(frame == nil)
        #expect(ApplicationMenuArea27.contains(point: CGPoint(x: 925, y: 15), measuredArea: frame, barBounds: bar))
    }

    @Test("An empty or failed AX child list protects the menu titles")
    func missingChildren() {
        let frame = ApplicationMenuArea27.measuredFrame(titleFrames: [])
        #expect(frame == nil)
        #expect(ApplicationMenuArea27.contains(point: CGPoint(x: 220, y: 15), measuredArea: frame, barBounds: bar))
    }

    @Test("A zero or malformed frame cannot establish empty menu bar space")
    func invalidFrames() {
        let invalid = [
            CGRect.zero,
            CGRect.null,
            CGRect.infinite,
            CGRect(x: 900, y: 0, width: 50, height: 0),
            CGRect(x: 900, y: 0, width: -50, height: 33),
            CGRect(x: CGFloat.nan, y: 0, width: 50, height: 33),
        ]
        for frame in invalid {
            #expect(ApplicationMenuArea27.measuredFrame(titleFrames: [titles[0], frame]) == nil)
            #expect(ApplicationMenuArea27.contains(point: CGPoint(x: 220, y: 15), measuredArea: frame, barBounds: bar))
        }
    }

    @Test("Uncertainty disables even apparently empty space until a complete measurement returns")
    func uncertainGap() {
        #expect(ApplicationMenuArea27.contains(point: CGPoint(x: 1100, y: 15), measuredArea: nil, barBounds: bar))
    }

    @Test("A complete read restores the real empty gap without disabling native menus")
    func recovery() throws {
        let frame = try #require(ApplicationMenuArea27.measuredFrame(titleFrames: titles))
        let area = ApplicationMenuArea27.area(menuFrame: frame, ownerDisplay: bar, display: bar, barHeight: bar.height)
        #expect(ApplicationMenuArea27.contains(point: CGPoint(x: 925, y: 15), measuredArea: area, barBounds: bar))
        #expect(!ApplicationMenuArea27.contains(point: CGPoint(x: 1100, y: 15), measuredArea: area, barBounds: bar))
    }

    @Test("The conservative fallback is confined to the requested display's menu bar")
    func otherDisplay() {
        let other = CGRect(x: -1512, y: 98, width: 1512, height: 33)
        #expect(ApplicationMenuArea27.contains(point: CGPoint(x: -600, y: 110), measuredArea: nil, barBounds: other))
        #expect(!ApplicationMenuArea27.contains(point: CGPoint(x: 220, y: 15), measuredArea: nil, barBounds: other))
        #expect(!ApplicationMenuArea27.contains(point: CGPoint(x: -600, y: 180), measuredArea: nil, barBounds: other))
        #expect(ApplicationMenuArea27.contains(point: CGPoint(x: -600, y: 110), measuredArea: bar, barBounds: other))
    }
}
