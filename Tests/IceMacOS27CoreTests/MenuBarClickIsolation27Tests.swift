import CoreGraphics
import Testing
@testable import IceMacOS27Core

@Suite("Menu bar input isolation")
struct MenuBarClickIsolation27Tests {
    let bar = CGRect(x: 0, y: 0, width: 1800, height: 30)

    @Test("A malformed full-window system frame cannot intercept a popover button")
    func popupInput() {
        let badFrame = CGRect(x: 0, y: 0, width: 1800, height: 1000)
        #expect(!ClockBridgeZone27.shouldBridge(
            click: CGPoint(x: 500, y: 300), systemItemFrames: [badFrame], isConcealing: true, menuBarBounds: bar
        ))
        #expect(!ClockBridgeZone27.shouldBridge(
            click: CGPoint(x: 500, y: 15), systemItemFrames: [badFrame], isConcealing: true, menuBarBounds: bar
        ))
    }

    @Test("Body input cannot be intercepted even when stale geometry covers it")
    func outsideBar() {
        #expect(!ClockBridgeZone27.shouldBridge(
            click: CGPoint(x: 1780, y: 90), systemItemFrames: [CGRect(x: 1750, y: 80, width: 50, height: 30)],
            isConcealing: true, menuBarBounds: bar
        ))
    }

    @Test("Only identified system items qualify for click bridging")
    func identifiers() {
        #expect(ClockBridgeZone27.isSystemIdentifier("com.apple.menuextra.clock"))
        #expect(!ClockBridgeZone27.isSystemIdentifier("local.codexpulse.app.status"))
        #expect(!ClockBridgeZone27.isSystemIdentifier("Item-0"))
    }
}
