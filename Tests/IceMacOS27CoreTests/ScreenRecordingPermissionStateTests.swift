import Testing
@testable import IceMacOS27Core

@Suite("Screen recording permission refresh")
struct ScreenRecordingPermissionStateTests {
    @Test("A pending check coalesces concurrent callers")
    func pending() {
        var state = ScreenRecordingPermissionState(granted: false)
        let refresh1 = state.beginRefresh(at: 0)
        #expect(refresh1)
        let refresh2 = state.beginRefresh(at: 20)
        #expect(!refresh2)
        #expect(!state.granted)
    }

    @Test("Initial denial can become a grant without restarting")
    func grantAfterDenial() {
        var state = ScreenRecordingPermissionState(granted: false)
        let refresh3 = state.beginRefresh(at: 0)
        #expect(refresh3)
        state.complete(granted: false, at: 0.5)
        let refresh4 = state.beginRefresh(at: 1)
        #expect(!refresh4)
        let refresh5 = state.beginRefresh(at: 1.5)
        #expect(refresh5)
        state.complete(granted: true, at: 2)
        #expect(state.granted)
        let refresh6 = state.beginRefresh(at: 31.9)
        #expect(!refresh6)
        let refresh7 = state.beginRefresh(at: 32)
        #expect(refresh7)
    }

    @Test("A revoked grant is retried at the denied interval")
    func revocation() {
        var state = ScreenRecordingPermissionState(granted: true)
        let refresh8 = state.beginRefresh(at: 0)
        #expect(refresh8)
        state.complete(granted: false, at: 1)
        #expect(!state.granted)
        let refresh9 = state.beginRefresh(at: 2)
        #expect(refresh9)
    }
}
