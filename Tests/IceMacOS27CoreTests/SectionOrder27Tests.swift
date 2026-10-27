import CoreGraphics
import Testing
@testable import IceMacOS27Core

@Suite("Saved section order and native drag geometry")
struct SectionOrder27Tests {
    @Test("Missing AX identities retain their slots")
    func incompleteScan() {
        #expect(SectionOrder27.merging(observed: ["c", "a", "new"], saved: ["a", "absent", "c"]) == ["a", "absent", "c", "new"])
    }

    @Test("A hidden drag persists its destination even with absent neighbours")
    func explicitMove() {
        #expect(SectionOrder27.moving("c", in: ["a", "absent", "b", "c"], displayed: ["c", "a", "b"]) == ["c", "a", "absent", "b"])
        #expect(SectionOrder27.moving("a", in: ["a", "absent", "b", "c"], displayed: ["b", "c", "a"]) == ["absent", "b", "c", "a"])
    }

    @Test("Cross-section insertions do not duplicate an identity")
    func insertion() {
        #expect(SectionOrder27.moving("new", in: ["a", "b"], displayed: ["a", "new", "b"]) == ["a", "new", "b"])
        #expect(SectionOrder27.moving("a", in: ["a", "a", "b"], displayed: ["b", "a"]) == ["b", "a"])
    }

    @Test("A cancelled drop cannot delete a saved identity")
    func absentSource() {
        #expect(SectionOrder27.moving("a", in: ["a", "b"], displayed: ["b"]) == ["a", "b"])
    }

    @Test("Same-display menu geometry permits native movement")
    func sameDisplay() {
        let display = CGRect(x: -3008, y: -458, width: 3008, height: 1692)
        #expect(SectionOrder27.canDrag(from: CGRect(x: -400, y: -458, width: 30, height: 24), to: CGRect(x: -300, y: -458, width: 30, height: 24), display: display))
    }

    @Test("Stale, popup and cross-display frames cannot drive native input")
    func rejectBadGeometry() {
        let display = CGRect(x: 0, y: 0, width: 1800, height: 1169)
        let target = CGRect(x: 1500, y: 0, width: 30, height: 38)
        for bad in [CGRect.zero, .null, .infinite, CGRect(x: -400, y: -458, width: 30, height: 24), CGRect(x: 1500, y: 60, width: 30, height: 38), CGRect(x: 1400, y: 0, width: 300, height: 500)] {
            #expect(!SectionOrder27.canDrag(from: bad, to: target, display: display))
        }
    }

    @Test("Verification requires the requested adjacency, not just direction")
    func verifiedOrder() {
        #expect(SectionOrder27.isAdjacent("pulse", to: "shottr", before: true, order: ["pulse", "shottr", "clash"]))
        #expect(!SectionOrder27.isAdjacent("pulse", to: "shottr", before: true, order: ["pulse", "clash", "shottr"]))
        #expect(!SectionOrder27.isAdjacent("pulse", to: "shottr", before: true, order: ["shottr"]))
        #expect(SectionOrder27.isAdjacent("pulse", to: "shottr", before: false, order: ["shottr", "pulse"]))
    }
}
