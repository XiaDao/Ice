//
//  ItemClicker27.swift
//  Ice
//

import AppKit
import ApplicationServices
import OSLog

/// Opens a hidden item's menu from the Ice Bar on macOS 27.
///
/// Ice can no longer move an item into view. Its application is allowed for a moment, and
/// the drawn item is clicked where it appears, the way Ice clicks items on earlier macOS,
/// with the pointer put back afterwards. An item that is not drawn, such as one folded
/// behind the overflow button, is pressed through Accessibility. Menus open on the display
/// with the active menu bar, so if that is not the Ice Bar's display, Ice first clicks the
/// empty spot of that display's menu bar where the Ice Bar was opened (measured on
/// macOS 27.0: that click makes the menu bar active). The click comes before the
/// application is shown, while the spot is still empty.
@available(macOS 27.0, *)
@MainActor
enum ItemClicker27 {
    private static let logger = Logger(category: "ItemClicker27")
    private static var activeSession: ItemMenuSession27?
    private static var revealLeases = [String: ItemRevealLease27]()

    static var isInteracting: Bool { activeSession?.isFinished == false }

    static func click(item: MenuBarItem, mouseButton: CGMouseButton, iceBarDisplayID: CGDirectDisplayID?, appState: AppState) async {
        if let activeSession, !activeSession.isFinished {
            activeSession.dismiss()
            if activeSession.tag == item.tag { return }
            try? await Task.sleep(for: .milliseconds(350))
        }
        guard let bundleID = item.sourceApplication?.bundleIdentifier else {
            logger.error("No application for \(item.logString, privacy: .public)")
            return
        }

        if
            ItemClick27.needsMenuBarActivation(activeDisplayID: Bridging.getActiveMenuBarDisplayID(), iceBarDisplayID: iceBarDisplayID),
            let iceBarDisplayID,
            let point = appState.hidEventManager.lastEmptyMenuBarPoint(for: iceBarDisplayID)
        {
            postMenuBarActivationClick(at: point)
            try? await Task.sleep(for: .milliseconds(300))
        }

        let concealer = appState.concealer27
        let lease: ItemRevealLease27
        if let existing = revealLeases[bundleID], !existing.isReleased {
            lease = existing
        } else {
            lease = ItemRevealLease27(
                bundleID: bundleID, ownerPID: item.ownerPID,
                interval: appState.settings.advanced.tempShowInterval, concealer: concealer
            ) {
                revealLeases[bundleID] = nil
            }
            revealLeases[bundleID] = lease
        }
        lease.beginMenu()
        // A shown item is drawn 0.4–0.6 s after its application is allowed (measured).
        try? await Task.sleep(for: .milliseconds(600))

        let fresh = await MenuBarItemProvider27.items().first { $0.tag == item.tag }
        let element = MenuBarItemProvider27.element(forWindowID: fresh?.windowID ?? item.windowID)
        let session = ItemMenuSession27(item: fresh ?? item, element: element) {
            lease.endMenu()
        }
        activeSession = session
        session.start()
        let drawn = fresh.flatMap { $0.isOnScreen ? $0 : nil }
        if let drawn {
            postClick(at: CGPoint(x: drawn.bounds.midX, y: drawn.bounds.midY), mouseButton: mouseButton)
        } else if let element {
            let action = mouseButton == .right ? kAXShowMenuAction : kAXPressAction
            let result = await perform(action, on: element)
            if result != .success {
                logger.notice("\(action, privacy: .public) on \(item.logString, privacy: .public) returned \(result.rawValue, privacy: .public)")
            }
        } else {
            logger.error("\(item.logString, privacy: .public) is neither drawn nor reachable through Accessibility")
            session.dismiss()
            return
        }
        session.activationDidReturn()
    }

    private static func perform(_ action: String, on element: AXUIElement) async -> AXError {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: AXUIElementPerformAction(element, action as CFString))
            }
        }
    }

    private static func postMenuBarActivationClick(at point: CGPoint) {
        postClick(at: point, mouseButton: .left)
    }

    /// Posts a click marked so that Ice's own mouse handlers ignore it, then puts the pointer back.
    private static func postClick(at point: CGPoint, mouseButton: CGMouseButton) {
        let source = CGEventSource(stateID: .hidSystemState)
        let original = CGEvent(source: nil)?.location
        let types: [CGEventType] = mouseButton == .right ? [.rightMouseDown, .rightMouseUp] : [.leftMouseDown, .leftMouseUp]
        for type in types {
            guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: mouseButton) else {
                continue
            }
            event.setIntegerValueField(.eventSourceUserData, value: HIDEventManager.menuBarActivationMarker)
            event.post(tap: .cghidEventTap)
        }
        if let original {
            _ = CGWarpMouseCursorPosition(original)
        }
    }
}
