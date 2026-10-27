import Testing
@testable import IceMacOS27Core

@Suite("Temporary icon visibility")
struct TemporaryRevealLifetime27Tests {
    @Test("A second click closing the menu does not immediately withdraw the icon")
    func closesMenu() {
        var state = TemporaryRevealLifetime27(now: 0, interval: 15)
        state.beginMenu(at: 0)
        state.endMenu(at: 1)
        #expect(!state.mayHide(at: 1))
        #expect(!state.mayHide(at: 15.9))
        #expect(state.mayHide(at: 16))
    }

    @Test("The icon remains visible throughout a long menu interaction")
    func longMenu() {
        var state = TemporaryRevealLifetime27(now: 0, interval: 15)
        state.beginMenu(at: 0)
        #expect(!state.mayHide(at: 100))
        state.endMenu(at: 100)
        #expect(!state.mayHide(at: 114))
        #expect(state.mayHide(at: 115))
    }

    @Test("Repeated native or Ice Bar interactions renew the configured interval")
    func repeated() {
        var state = TemporaryRevealLifetime27(now: 0, interval: 8)
        state.beginMenu(at: 0)
        state.endMenu(at: 1)
        state.beginMenu(at: 7)
        state.endMenu(at: 8)
        #expect(!state.mayHide(at: 15))
        #expect(state.mayHide(at: 16))
    }

    @Test("Overlapping operations must both end before the icon can hide")
    func overlapping() {
        var state = TemporaryRevealLifetime27(now: 0, interval: 15)
        state.beginMenu(at: 0)
        state.beginMenu(at: 1)
        state.endMenu(at: 2)
        #expect(!state.mayHide(at: 100))
        state.endMenu(at: 101)
        #expect(state.mayHide(at: 116))
    }
}
