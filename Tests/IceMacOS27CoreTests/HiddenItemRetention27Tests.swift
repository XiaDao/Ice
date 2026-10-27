import CoreGraphics
import Testing
@testable import IceMacOS27Core

@Suite("Hidden item enumeration")
struct HiddenItemRetention27Tests {
    @Test("A concealed application's missing extras survive a scan")
    func concealed() {
        #expect(HiddenItemRetention27.retainedIDs(
            previous: [(1, 100), (2, 100)], fresh: [], running: [100], managedHidden: [100]
        ) == [1, 2])
    }

    @Test("Fresh entries replace cached entries without duplicates")
    func fresh() {
        #expect(HiddenItemRetention27.retainedIDs(
            previous: [(1, 100), (2, 100)], fresh: [1], running: [100], managedHidden: [100]
        ) == [2])
    }

    @Test("Termination and PID changes discard old items")
    func termination() {
        #expect(HiddenItemRetention27.retainedIDs(
            previous: [(1, 100)], fresh: [], running: [101], managedHidden: [100, 101]
        ).isEmpty)
    }

    @Test("Moving an app out of hidden sections lets an absent item disappear")
    func revealed() {
        #expect(HiddenItemRetention27.retainedIDs(
            previous: [(1, 100)], fresh: [], running: [100], managedHidden: []
        ).isEmpty)
    }

    @Test("Missing geometry is not mistaken for an on-screen item")
    func missingGeometry() {
        #expect(!ItemDrawing27.isDrawn(itemFrame: .zero, activeDisplayBounds: nil, chevronFrame: nil))
        #expect(!ItemDrawing27.isDrawn(itemFrame: .null, activeDisplayBounds: nil, chevronFrame: nil))
    }
}
