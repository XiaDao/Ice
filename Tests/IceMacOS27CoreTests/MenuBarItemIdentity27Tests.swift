import Foundation
import Testing
@testable import IceMacOS27Core

@Suite("Persistent hidden item identities")
struct MenuBarItemIdentity27Tests {
    let app = MenuBarItemIdentity27(bundleID: "com.example.app", identifier: "Item-0", index: 0)

    @Test("A glyph cache restores its identity on a cold start")
    func migration() throws {
        let restored = try #require(MenuBarItemIdentity27(imageCacheKey: app.key))
        #expect(restored == app)
        #expect(restored.windowID == app.windowID)
        let pulse = try #require(MenuBarItemIdentity27(imageCacheKey: "local.codexpulse.app:local.codexpulse.app.status"))
        #expect(pulse.identifier == "local.codexpulse.app.status")
    }

    @Test("Serialization contains no process or geometry state")
    func roundTrip() throws {
        let data = try JSONEncoder().encode([app])
        #expect(try JSONDecoder().decode([MenuBarItemIdentity27].self, from: data) == [app])
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        #expect(Set(object[0].keys) == ["bundleID", "identifier", "index"])
    }

    @Test("A running hidden app returns even if AX omitted it during a temporary reveal")
    func missing() {
        #expect(MenuBarItemIdentity27.missing(
            saved: [app], freshKeys: [], runningBundles: [app.bundleID], hiddenBundles: [app.bundleID]
        ) == [app])
    }

    @Test("A fresh observation wins over any cached ordinal without duplication")
    func duplicate() {
        let old = MenuBarItemIdentity27(bundleID: app.bundleID, identifier: app.identifier, index: 2)
        #expect(MenuBarItemIdentity27.missing(
            saved: [old, app], freshKeys: [app.key], runningBundles: [app.bundleID], hiddenBundles: [app.bundleID]
        ).isEmpty)
        #expect(MenuBarItemIdentity27.missing(
            saved: [old, app], freshKeys: [], runningBundles: [app.bundleID], hiddenBundles: [app.bundleID]
        ).count == 1)
    }

    @Test("Terminated apps and apps moved to Visible do not return from cache")
    func exclusions() {
        #expect(MenuBarItemIdentity27.missing(
            saved: [app], freshKeys: [], runningBundles: [], hiddenBundles: [app.bundleID]
        ).isEmpty)
        #expect(MenuBarItemIdentity27.missing(
            saved: [app], freshKeys: [], runningBundles: [app.bundleID], hiddenBundles: []
        ).isEmpty)
    }

    @Test("Malformed old keys do not become phantom items")
    func malformed() {
        #expect(MenuBarItemIdentity27(imageCacheKey: "") == nil)
        #expect(MenuBarItemIdentity27(imageCacheKey: ":Item-0") == nil)
        #expect(MenuBarItemIdentity27(imageCacheKey: "com.example:") == nil)
    }
}
