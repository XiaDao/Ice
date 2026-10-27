import AppKit

/// Keeps one application visible for the configured interval after menu use.
@available(macOS 27.0, *)
@MainActor
final class ItemRevealLease27 {
    private let bundleID: String
    private let ownerPID: pid_t
    private weak var concealer: Concealer27?
    private let onRelease: () -> Void
    private var lifetime: TemporaryRevealLifetime27
    private var expiry: Task<Void, Never>?
    private(set) var isReleased = false

    init(bundleID: String, ownerPID: pid_t, interval: TimeInterval, concealer: Concealer27, onRelease: @escaping () -> Void) {
        self.bundleID = bundleID
        self.ownerPID = ownerPID
        self.concealer = concealer
        self.onRelease = onRelease
        lifetime = TemporaryRevealLifetime27(now: ProcessInfo.processInfo.systemUptime, interval: interval)
        concealer.showTemporarily(bundleID: bundleID)
    }

    func beginMenu() {
        lifetime.beginMenu(at: ProcessInfo.processInfo.systemUptime)
        expiry?.cancel()
        expiry = nil
    }

    func endMenu() {
        lifetime.endMenu(at: ProcessInfo.processInfo.systemUptime)
        scheduleExpiry()
    }

    private func scheduleExpiry() {
        expiry?.cancel()
        guard !isReleased, lifetime.openMenus == 0 else { return }
        let delay = max(0, lifetime.deadline - ProcessInfo.processInfo.systemUptime)
        expiry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, !isReleased else { return }
            // The user can reopen the real status icon without going through Ice.
            // Never withdraw it from underneath a native menu opened that way.
            var sawNativeMenu = false
            while nativeMenuIsOpen() {
                sawNativeMenu = true
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
            }
            if sawNativeMenu {
                lifetime.renew(at: ProcessInfo.processInfo.systemUptime)
                scheduleExpiry()
            } else if lifetime.mayHide(at: ProcessInfo.processInfo.systemUptime) {
                isReleased = true
                concealer?.endTemporaryShow(bundleID: bundleID)
                onRelease()
            }
        }
    }

    private func nativeMenuIsOpen() -> Bool {
        let owners = Set([ownerPID] + NSRunningApplication.runningApplications(
            withBundleIdentifier: MenuBarItemProvider27.menuBarAgentBundleID
        ).map(\.processIdentifier))
        return !ItemMenuPolicy27.menuWindows(WindowInfo.createWindows(option: .onScreen).map {
            .init(number: $0.windowID, ownerPID: $0.ownerPID, layer: $0.layer, bounds: $0.bounds)
        }, owners: owners, baseline: []).isEmpty
    }
}
