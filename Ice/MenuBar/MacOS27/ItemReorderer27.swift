import AppKit
import OSLog
import Semaphore

/// Explicit Layout drops only. Never continuously rearrange the user's bar.
@available(macOS 27.0, *)
@MainActor
enum ItemReorderer27 {
    private static let semaphore = AsyncSemaphore(value: 1)
    private static let logger = Logger(category: "ItemReorderer27")

    enum Failure: LocalizedError {
        case geometry, inputBusy, notMoved

        var errorDescription: String? {
            switch self {
            case .geometry: "Ice could not locate both icons on the active menu bar."
            case .inputBusy: "The menu bar changed displays or another mouse operation is still active."
            case .notMoved: "macOS did not apply the requested icon order."
            }
        }

        var recoverySuggestion: String? {
            "The previous layout has been kept. Try again with both icons visible on the same display."
        }
    }

    static func move(item: MenuBarItem, section: MacOS27Section, displayed: [MenuBarItem], appState: AppState) async throws {
        try await semaphore.waitUnlessCancelled()
        defer { semaphore.signal() }
        guard !item.isControlItem, let bundleID = item.sourceApplication?.bundleIdentifier else { return }

        if section != .visible {
            // Hidden order is virtual: the Ice Bar and Layout share this model.
            appState.concealer27.saveOrder(moving: item.tag, section: section, displayed: displayed.map(\.tag))
            appState.concealer27.setSection(section, for: bundleID)
            await appState.itemManager.cacheItemsRegardless()
            return
        }
        guard !ItemClicker27.isInteracting else { throw Failure.inputBusy }
        let members = displayed.filter { !$0.isControlItem }
        guard let index = members.firstIndex(where: { $0.tag == item.tag }) else { throw Failure.geometry }
        let target: MenuBarItem?
        let before: Bool
        if members.indices.contains(index + 1) {
            target = members[index + 1]
            before = true
        } else {
            target = index > 0 ? members[index - 1] : nil
            before = false
        }
        let revealed = Set(([item] + (target.map { [$0] } ?? [])).compactMap { $0.sourceApplication?.bundleIdentifier })
        let concealer = appState.concealer27
        await concealer.beginReordering(revealing: revealed)
        // Always release the visibility pin, including failed verification.
        defer { concealer.endReordering(revealing: revealed) }
        try await Task.sleep(for: .milliseconds(500))
        if let target {
            try await applyNativeMove(item: item, target: target, before: before, appState: appState)
        }
        concealer.saveOrder(moving: item.tag, section: section, displayed: displayed.map(\.tag))
        concealer.setSection(section, for: bundleID)
        logger.notice("Verified Layout drop: \(item.tag.description, privacy: .public), section \(section.rawValue, privacy: .public)")
    }

    private static func applyNativeMove(item: MenuBarItem, target: MenuBarItem, before: Bool, appState: AppState) async throws {
        let displayID = Bridging.getActiveMenuBarDisplayID()
        let snapshot = await MenuBarItemProvider27.items()
        guard let displayID, Bridging.getActiveMenuBarDisplayID() == displayID,
              let source = snapshot.first(where: { $0.tag == item.tag && $0.isOnScreen }),
              let destination = snapshot.first(where: { $0.tag == target.tag && $0.isOnScreen }),
              SectionOrder27.canDrag(from: source.bounds, to: destination.bounds, display: CGDisplayBounds(displayID)) else {
            throw Failure.geometry
        }
        let physical = snapshot.filter { $0.isOnScreen && !$0.isControlItem }.sorted { $0.bounds.minX < $1.bounds.minX }
        if SectionOrder27.isAdjacent(item.tag.description, to: target.tag.description, before: before, order: physical.map { $0.tag.description }) {
            return
        }

        // Let the Layout drag finish and avoid borrowing a physically held modifier.
        var quiet = false
        for _ in 0..<20 {
            if !CGEventSource.buttonState(.combinedSessionState, button: .left),
               CGEventSource.flagsState(.combinedSessionState).intersection([.maskCommand, .maskShift, .maskControl, .maskAlternate]).isEmpty {
                quiet = true
                break
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        guard quiet, Bridging.getActiveMenuBarDisplayID() == displayID else { throw Failure.inputBusy }
        appState.hidEventManager.stopAll()
        defer { appState.hidEventManager.startAll() }
        try await commandDrag(from: source.bounds, to: destination.bounds, before: before, display: CGDisplayBounds(displayID))

        var verified = 0
        for _ in 0..<8 {
            try await Task.sleep(for: .milliseconds(160))
            guard Bridging.getActiveMenuBarDisplayID() == displayID else { throw Failure.inputBusy }
            let current = await MenuBarItemProvider27.items()
            let onBar = current.filter {
                $0.isOnScreen && !$0.isControlItem &&
                SectionOrder27.canDrag(from: $0.bounds, to: $0.bounds, display: CGDisplayBounds(displayID))
            }.sorted { $0.bounds.minX < $1.bounds.minX }
            if SectionOrder27.isAdjacent(item.tag.description, to: target.tag.description, before: before, order: onBar.map { $0.tag.description }) {
                verified += 1
                if verified == 2 { return }
            } else {
                verified = 0
            }
        }
        throw Failure.notMoved
    }

    /// Native Command-drag sequence adapted from the GPL implementation in
    /// jordanbaird/Ice PR #997. Every exit releases both synthetic inputs.
    private static func commandDrag(from sourceFrame: CGRect, to targetFrame: CGRect, before: Bool, display: CGRect) async throws {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let commandDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true),
              let commandUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false) else { throw Failure.inputBusy }
        let suppressionStates: [CGEventSuppressionState] = [.eventSuppressionStateRemoteMouseDrag, .eventSuppressionStateSuppressionInterval]
        for state in suppressionStates {
            source.setLocalEventsFilterDuringSuppressionState([.permitLocalMouseEvents, .permitSystemDefinedEvents], state: state)
        }
        source.localEventsSuppressionInterval = 0.25
        let start = CGPoint(x: sourceFrame.midX, y: sourceFrame.midY)
        let endX = min(display.maxX - 1, max(display.minX + 1, before ? targetFrame.minX - 3 : targetFrame.maxX + 3))
        let end = CGPoint(x: endX, y: targetFrame.midY)
        let original = CGEvent(source: nil)?.location
        commandDown.flags = .maskCommand
        commandUp.flags = []
        func event(_ type: CGEventType, at point: CGPoint) throws -> CGEvent {
            guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else { throw Failure.inputBusy }
            event.flags = [.maskCommand, .maskNonCoalesced]
            event.setIntegerValueField(.eventSourceUserData, value: HIDEventManager.menuBarActivationMarker)
            return event
        }
        let mouseUp = try event(.leftMouseUp, at: end)
        var pressed = false
        defer {
            if pressed { mouseUp.post(tap: .cghidEventTap) }
            commandUp.post(tap: .cghidEventTap)
            source.localEventsSuppressionInterval = 0
            for state in suppressionStates {
                source.setLocalEventsFilterDuringSuppressionState([.permitLocalMouseEvents, .permitLocalKeyboardEvents, .permitSystemDefinedEvents], state: state)
            }
            if let original { _ = CGWarpMouseCursorPosition(original) }
        }
        try Task.checkCancellation()
        commandDown.post(tap: .cghidEventTap)
        try await Task.sleep(for: .milliseconds(24))
        try event(.leftMouseDown, at: start).post(tap: .cghidEventTap)
        pressed = true
        // Once pressed, finish the gesture even if its task is cancelled.
        try? await Task.sleep(for: .milliseconds(55))
        let steps = max(12, min(42, Int(ceil(abs(end.x - start.x) / 6))))
        for index in 1...steps {
            let progress = CGFloat(index) / CGFloat(steps)
            let point = CGPoint(x: start.x + (end.x - start.x) * progress, y: start.y + (end.y - start.y) * progress)
            try event(.leftMouseDragged, at: point).post(tap: .cghidEventTap)
            try? await Task.sleep(for: .milliseconds(5))
        }
        try? await Task.sleep(for: .milliseconds(28))
        mouseUp.post(tap: .cghidEventTap)
        pressed = false
    }
}
