import Foundation

/// Coalesces asynchronous checks. A denied or pending permission is retried
/// promptly; a successful check is reused for longer to avoid needless work.
struct ScreenRecordingPermissionState {
    private(set) var granted: Bool
    private var refreshing = false
    private var lastRefresh: TimeInterval?

    init(granted: Bool) {
        self.granted = granted
    }

    mutating func beginRefresh(at now: TimeInterval) -> Bool {
        guard !refreshing else { return false }
        let interval: TimeInterval = granted ? 30 : 1
        guard lastRefresh.map({ now - $0 >= interval }) ?? true else { return false }
        refreshing = true
        return true
    }

    mutating func complete(granted: Bool, at now: TimeInterval) {
        self.granted = granted
        lastRefresh = now
        refreshing = false
    }
}
