import AppKit
import ApplicationServices
import OSLog

/// Owns one temporary reveal, including the time an AX press spends tracking a
/// menu. Outside input is observed, never consumed or replayed.
@available(macOS 27.0, *)
@MainActor
final class ItemMenuSession27 {
    let tag: MenuBarItemTag
    private let ownerPID: pid_t
    private let roots: [AXUIElement]
    private let baseline: Set<CGWindowID>
    private let owners: Set<pid_t>
    private let onFinish: () -> Void
    private var monitor: EventMonitor?
    private var watchTask: Task<Void, Never>?
    private var activationReturned = false
    private var closing = false
    private let logger = Logger(category: "ItemMenuSession27")
    private(set) var isFinished = false

    init(item: MenuBarItem, element: AXUIElement?, onFinish: @escaping () -> Void) {
        tag = item.tag
        ownerPID = item.ownerPID
        roots = element.map { [$0] } ?? []
        baseline = Set(WindowInfo.createWindows(option: .onScreen).map(\.windowID))
        owners = Set([item.ownerPID] + NSRunningApplication.runningApplications(
            withBundleIdentifier: MenuBarItemProvider27.menuBarAgentBundleID
        ).map(\.processIdentifier))
        self.onFinish = onFinish
    }

    func start() {
        logger.notice("Opening item menu: \(self.tag.description, privacy: .public)")
        monitor = .universal(for: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self, !isFinished else { return event }
            if event.cgEvent?.getIntegerValueField(.eventSourceUserData) == HIDEventManager.menuBarActivationMarker {
                return event
            }
            if event.type == .keyDown {
                if event.keyCode == 53 { dismiss() }
            } else if let point = event.cgEvent?.location ?? MouseHelpers.locationCoreGraphics,
                      ItemMenuPolicy27.dismissesMenu(click: point, menuFrames: menuWindows().map(\.bounds)) {
                dismiss()
            }
            return event
        }
        monitor?.start()
        watchTask = Task { [weak self] in
            // Allow the real click/AX press to start tracking before interpreting absence.
            try? await Task.sleep(for: .milliseconds(1200))
            var misses = 0
            var observed = false
            for _ in 0..<240 {
                guard !Task.isCancelled, let self, !isFinished else { return }
                if !menuWindows().isEmpty {
                    if !observed {
                        logger.notice("Observed native menu: \(self.tag.description, privacy: .public)")
                        observed = true
                    }
                    misses = 0
                } else if activationReturned {
                    misses += 1
                    if misses >= 3 { finish(); return }
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
            self?.dismiss()
        }
    }

    func activationDidReturn() { activationReturned = true }

    func dismiss() {
        guard !closing, !isFinished else { return }
        logger.notice("Dismissing item menu: \(self.tag.description, privacy: .public)")
        closing = true
        Task { [weak self] in
            guard let self else { return }
            // AXPress can be synchronous for the entire menu lifetime. Cancellation
            // runs independently so an outside click can release that call as well.
            for _ in 0..<3 {
                await Self.cancelMenus(roots: roots, ownerPID: ownerPID)
                try? await Task.sleep(for: .milliseconds(100))
                if menuWindows().isEmpty { break }
            }
            logger.notice("Menu windows remaining after dismissal: \(self.menuWindows().count, privacy: .public)")
            finish()
        }
    }

    private func finish() {
        guard !isFinished else { return }
        isFinished = true
        logger.notice("Released item menu reveal: \(self.tag.description, privacy: .public)")
        monitor?.stop()
        monitor = nil
        watchTask?.cancel()
        watchTask = nil
        onFinish()
    }

    private func menuWindows() -> [ItemMenuPolicy27.Window] {
        ItemMenuPolicy27.menuWindows(WindowInfo.createWindows(option: .onScreen).map {
            .init(number: $0.windowID, ownerPID: $0.ownerPID, layer: $0.layer, bounds: $0.bounds)
        }, owners: owners, baseline: baseline)
    }

    private static func cancelMenus(roots: [AXUIElement], ownerPID: pid_t) async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
                    var result: CFTypeRef?
                    guard AXUIElementCopyAttributeValue(element, key as CFString, &result) == .success else { return nil }
                    return result
                }
                func cancel(_ element: AXUIElement, depth: Int) {
                    AXUIElementSetMessagingTimeout(element, 0.2)
                    if attribute(element, kAXRoleAttribute) as? String == kAXMenuRole {
                        _ = AXUIElementPerformAction(element, kAXCancelAction as CFString)
                        return
                    }
                    guard depth > 0 else { return }
                    for child in attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
                        cancel(child, depth: depth - 1)
                    }
                }
                var targets = roots
                let app = AXUIElementCreateApplication(ownerPID)
                AXUIElementSetMessagingTimeout(app, 0.2)
                if let extras = attribute(app, kAXExtrasMenuBarAttribute), CFGetTypeID(extras) == AXUIElementGetTypeID() {
                    targets.append(extras as! AXUIElement) // swiftlint:disable:this force_cast
                }
                for root in targets { cancel(root, depth: 4) }
                continuation.resume()
            }
        }
    }
}
