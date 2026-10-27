import CoreGraphics
import Testing
@testable import IceMacOS27Core

@Suite("Native menu interaction")
struct ItemMenuPolicy27Tests {
    let parent = CGRect(x: 100, y: 30, width: 200, height: 400)
    let submenu = CGRect(x: 300, y: 90, width: 180, height: 100)

    @Test("Both app-hosted and MenuBarAgent-hosted popups keep the reveal alive")
    func owners() {
        let windows: [ItemMenuPolicy27.Window] = [
            .init(number: 1, ownerPID: 10, layer: 101, bounds: parent),
            .init(number: 2, ownerPID: 20, layer: 101, bounds: submenu),
            .init(number: 3, ownerPID: 30, layer: 101, bounds: parent),
            .init(number: 4, ownerPID: 10, layer: 0, bounds: parent),
            .init(number: 5, ownerPID: 10, layer: 101, bounds: parent),
            .init(number: 6, ownerPID: 20, layer: 25, bounds: CGRect(x: 0, y: 0, width: 1800, height: 30)),
        ]
        #expect(ItemMenuPolicy27.menuWindows(windows, owners: [10, 20], baseline: [5]).map(\.number) == [1, 2])
    }

    @Test("Selecting a parent entry or submenu is not intercepted")
    func inside() {
        #expect(!ItemMenuPolicy27.dismissesMenu(click: CGPoint(x: 150, y: 80), menuFrames: [parent, submenu]))
        #expect(!ItemMenuPolicy27.dismissesMenu(click: CGPoint(x: 350, y: 100), menuFrames: [parent, submenu]))
    }

    @Test("Outside clicks and a second click on the status icon dismiss")
    func outside() {
        #expect(ItemMenuPolicy27.dismissesMenu(click: CGPoint(x: 20, y: 500), menuFrames: [parent, submenu]))
        #expect(ItemMenuPolicy27.dismissesMenu(click: CGPoint(x: 150, y: 15), menuFrames: [parent, submenu]))
    }

    @Test("An outside click while AX is still opening a menu can cancel it")
    func opening() {
        #expect(ItemMenuPolicy27.dismissesMenu(click: CGPoint(x: 20, y: 500), menuFrames: []))
    }
}
