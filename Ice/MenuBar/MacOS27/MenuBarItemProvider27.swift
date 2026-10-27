//
//  MenuBarItemProvider27.swift
//  Ice
//

import ApplicationServices
import Cocoa
import OSLog

/// Reads menu bar items through Accessibility on macOS 27.
///
/// macOS 27 draws status items inside MenuBarAgent instead of giving each one a
/// WindowServer window, so the window list Ice used is empty. Every process still
/// publishes its items under `AXExtrasMenuBar`, with frames, for the display that
/// has the active menu bar.
@available(macOS 27.0, *)
enum MenuBarItemProvider27 {
    /// The bundle identifier of the process that hosts the system items.
    static let menuBarAgentBundleID = "com.apple.MenuBarAgent"

    private struct Entry {
        let element: AXUIElement?
        let bundleID: String
        let identifier: String
        let frame: CGRect
    }

    private struct RawItem {
        let element: AXUIElement
        let bundleID: String
        let pid: pid_t
        let identifier: String
        let title: String?
        let index: Int
        let frame: CGRect
    }

    private static let logger = Logger(category: "MenuBarItemProvider27")

    /// Accessibility calls block, so they run on their own queue, off the Swift
    /// concurrency pool (see `MenuBarItemImageCache.captureQueue`).
    private static let queue = DispatchQueue(label: "com.jordanbaird.Ice.MenuBarItemProvider27", qos: .userInitiated)

    private static let lock = NSLock()
    nonisolated(unsafe) private static var entries = [CGWindowID: Entry]()
    nonisolated(unsafe) private static var lastOverflowButtonFrame: CGRect?
    nonisolated(unsafe) private static var lastSystemItemFrames = [CGRect]()
    /// System item frames per display. MenuBarAgent describes the bars of both displays in its
    /// windows, unlike other applications, whose items only have frames on the active one.
    nonisolated(unsafe) private static var lastSystemFramesByDisplay = [CGDirectDisplayID: [CGRect]]()
    /// Every frame in those windows, per display, system items included. A bar whose menu bar is
    /// not the active one has no other account of what it draws: applications report frames for
    /// the active bar alone.
    nonisolated(unsafe) private static var lastBarFramesByDisplay = [CGDirectDisplayID: [CGRect]]()
    /// How many of each bar's entries belong to applications rather than the system group.
    nonisolated(unsafe) private static var lastApplicationEntriesByDisplay = [CGDirectDisplayID: Int]()
    /// How far left of the clock's own left edge the other system items reach (measured on
    /// macOS 27.0: 122 points on both displays — battery, Wi-Fi and Control Centre).
    private static let systemItemsSpan: CGFloat = 130
    /// The leftmost item drawn on each display, from the last read while that display's
    /// menu bar was active. Hover hit-testing needs it for the display that is not active,
    /// where Accessibility reports no frames at all.
    nonisolated(unsafe) private static var lastLeftEdges = [CGDirectDisplayID: CGFloat]()
    /// Processes whose items are concealed. Accessibility keeps reporting their frames where
    /// they were last drawn, so without this they would pass for drawn items.
    nonisolated(unsafe) private static var concealedPIDs = Set<pid_t>()
    /// Only read and written on `queue`.
    nonisolated(unsafe) private static var scanSchedule = AccessibilityScanSchedule27()
    // Read and written only on the serial scan queue.
    nonisolated(unsafe) private static var savedIdentities = loadIdentities()

    /// Returns the items on the active menu bar, ordered left to right.
    ///
    /// A caller that asks while another read is under way, or in the moment after one
    /// finished, is answered from that read. Ice ran one Accessibility sweep per caller
    /// before, and they arrive in bursts: revealing the hidden items set six of them going
    /// in little over a second (measured 2026-09-16), each asking every running process,
    /// while MenuBarAgent was animating the bar. The window is short on purpose — the
    /// before-and-after reads that decide which items sat still for a capture are further
    /// apart than this, so they still see the bar twice.
    static func items() async -> [MenuBarItem] {
        await withCheckedContinuation { continuation in
            queue.async {
                let fresh: [MenuBarItem]? = lock.withLock {
                    guard
                        let items = lastItems,
                        ProcessInfo.processInfo.systemUptime - lastReadAt < freshInterval
                    else {
                        return nil
                    }
                    return items
                }
                if let fresh {
                    logger.debug("Item scan: answered from the read just finished")
                    continuation.resume(returning: fresh)
                    return
                }
                let items = readItems()
                lock.withLock {
                    lastItems = items
                    lastReadAt = ProcessInfo.processInfo.systemUptime
                }
                continuation.resume(returning: items)
            }
        }
    }

    /// How long a finished read stands in for the next one.
    private static let freshInterval: TimeInterval = 0.12
    nonisolated(unsafe) private static var lastItems: [MenuBarItem]?
    nonisolated(unsafe) private static var lastReadAt: TimeInterval = 0

    /// Returns the current frame of the item with the given synthetic identifier.
    ///
    /// Ice's own items are answered from the last read: asking our own process
    /// from the main thread would wait for the main thread itself.
    static func currentBounds(for windowID: CGWindowID) -> CGRect? {
        guard let entry = lock.withLock({ entries[windowID] }) else {
            return nil
        }
        if entry.bundleID == Constants.bundleIdentifier {
            return entry.frame
        }
        // App-local AX frames become stale after MenuBarAgent rearranges items.
        return entry.frame
    }

    /// Frames of the system items hosted by MenuBarAgent, from the last read.
    static func systemItemFrames() -> [CGRect] {
        lock.withLock { lastSystemItemFrames }
    }

    /// The Accessibility element of the system item drawn at the given point, from the last
    /// read. Control Centre opens from a press on it without lifting concealment.
    static func systemItem(at point: CGPoint) -> (element: AXUIElement, identifier: String)? {
        lock.withLock {
            entries.values
                .first { $0.bundleID == menuBarAgentBundleID && $0.frame.insetBy(dx: -1, dy: -1).contains(point) }
                .flatMap { entry in entry.element.map { ($0, entry.identifier) } }
        }
    }

    /// The Accessibility element of the system item with the given identifier, from the last read.
    ///
    /// Control Centre's is `com.apple.menuextra.controlcenter` (measured on macOS 27.0, alongside
    /// `…battery`, `…wifi` and `…clock`).
    static func systemItem(withIdentifier identifier: String) -> AXUIElement? {
        lock.withLock {
            entries.values
                .first { $0.bundleID == menuBarAgentBundleID && $0.identifier == identifier }?
                .element
        }
    }

    /// Tells the provider which processes are concealed right now.
    static func setConcealedPIDs(_ pids: Set<pid_t>) {
        lock.withLock { concealedPIDs = pids }
    }

    /// The leftmost item drawn on the given display, from the last read while its menu bar
    /// was active.
    static func leftEdge(for displayID: CGDirectDisplayID) -> CGFloat? {
        lock.withLock { lastLeftEdges[displayID] }
    }

    /// Frames of the system items drawn on the given display, from the last read.
    ///
    /// A click on the clock of the display whose menu bar is not active has to be recognised
    /// too, or it reaches MenuBarAgent while the assertion still stands and is ignored — which
    /// is why that clock used to need two or three clicks.
    static func systemItemFrames(for displayID: CGDirectDisplayID) -> [CGRect] {
        lock.withLock { lastSystemFramesByDisplay[displayID] ?? [] }
    }

    /// Frames of everything MenuBarAgent draws on the given display, from the last read.
    static func barFrames(for displayID: CGDirectDisplayID) -> [CGRect] {
        lock.withLock { lastBarFramesByDisplay[displayID] ?? [] }
    }

    /// How many items of applications the given display's bar lists, from the last read, or `nil`
    /// if that bar was not read. Items folded away beside the notch are listed by neither display.
    static func applicationEntryCount(for displayID: CGDirectDisplayID) -> Int? {
        lock.withLock { lastApplicationEntriesByDisplay[displayID] }
    }

    /// Frame of the system overflow button ("<<" / ">>"), from the last read.
    static func overflowButtonFrame() -> CGRect? {
        lock.withLock { lastOverflowButtonFrame }
    }

    /// The Accessibility element of the item with the given synthetic identifier, from the
    /// last read. Items drawn on another display are included (see `ItemDrawing27`).
    static func element(forWindowID windowID: CGWindowID) -> AXUIElement? {
        lock.withLock { entries[windowID]?.element }
    }

    // MARK: Reading

    private static func readItems(retryIfMenuBarMoves: Bool = true) -> [MenuBarItem] {
        // Timed: a scan that runs while MenuBarAgent is animating the bar is a suspect for
        // the stutter of that animation.
        let started = ProcessInfo.processInfo.systemUptime
        logger.debug("Item scan: started")
        defer {
            let milliseconds = (ProcessInfo.processInfo.systemUptime - started) * 1000
            logger.debug("Item scan: took \(milliseconds, privacy: .public) ms")
        }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        var rawItems = [RawItem]()
        var agentFramesByOwner = [pid_t: [CGRect]]()
        var chevronFrame: CGRect?
        // A read that races a change of the active menu bar can mix displays, so it
        // is repeated once when the menu bar moves during the read.
        let activeDisplayID = Bridging.getActiveMenuBarDisplayID()
        let activeDisplayBounds = activeDisplayID.map(CGDisplayBounds)

        // MenuBarAgent comes first, and its frames are published before the other
        // processes are asked: a click on the clock needs them, and right after launch
        // the whole read can take seconds (measured 12.7 s).
        let runningApplications = NSWorkspace.shared.runningApplications
        let applications = runningApplications.filter { $0.bundleIdentifier == menuBarAgentBundleID }
            + runningApplications.filter { $0.bundleIdentifier != menuBarAgentBundleID }
        let now = ProcessInfo.processInfo.systemUptime
        scanSchedule.retain(running: Set(applications.map(\.processIdentifier)))

        for app in applications {
            guard let bundleID = app.bundleIdentifier else {
                continue
            }
            let pid = app.processIdentifier
            let timeout: Float
            if pid == ownPID {
                timeout = 0.25
            } else if let scheduled = scanSchedule.timeout(for: pid, now: now) {
                timeout = scheduled
            } else {
                continue
            }
            let application = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(application, timeout)
            var barValue: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(application, kAXExtrasMenuBarAttribute as CFString, &barValue)
            if pid != ownPID {
                scanSchedule.record(pid: pid, timedOut: result == .cannotComplete, now: now)
            }
            guard
                result == .success,
                let barValue,
                CFGetTypeID(barValue) == AXUIElementGetTypeID(),
                let children = elements(barValue as! AXUIElement, kAXChildrenAttribute) // swiftlint:disable:this force_cast
            else {
                continue
            }
            if pid != ownPID, !children.isEmpty {
                scanSchedule.recordItems(pid: pid)
            }
            for (index, child) in children.enumerated() {
                if bundleID == menuBarAgentBundleID, string(child, kAXRoleAttribute) == kAXButtonRole {
                    // The system overflow control ("<<" / ">>").
                    chevronFrame = frame(of: child)
                    continue
                }
                // MenuBarAgent wraps each system item in a hosting group; the identifier
                // and the drawn frame belong to the item inside it.
                let element: AXUIElement
                if bundleID == menuBarAgentBundleID {
                    let candidates = [child] + (elements(child, kAXChildrenAttribute) ?? [])
                    guard let systemElement = candidates.first(where: {
                        string($0, kAXIdentifierAttribute).map(ClockBridgeZone27.isSystemIdentifier) ?? false
                    }) else { continue }
                    element = systemElement
                } else {
                    element = child
                }
                // Items whose frames are on another display stay in the list, marked as not
                // drawn, so a concealed item keeps its section (see `ItemDrawing27`).
                // Concealed/overflow items can publish their identity without a
                // frame. They still belong in the layout and the Ice Bar.
                let frame = frame(of: element) ?? .zero
                rawItems.append(RawItem(
                    element: element,
                    bundleID: bundleID,
                    pid: pid,
                    identifier: string(element, kAXIdentifierAttribute) ?? "",
                    title: string(element, kAXDescriptionAttribute) ?? string(element, kAXTitleAttribute),
                    index: index,
                    frame: frame
                ))
            }
            if bundleID == menuBarAgentBundleID {
                // MenuBarAgent's window on the display whose bar is not active holds every item
                // drawn there, not only the system ones, so taking them all made Ice treat any
                // click as a click on a system item and lift concealment for it. The system
                // items are the rightmost group, and the clock is the widest of them: keep the
                // items within the span they occupy (measured on macOS 27.0: 237 points from the
                // leftmost of them to the clock's right edge).
                // Each window is one display's bar, and what it lists belongs to that bar: an
                // item's frame where it is drawn, and an entry with no geometry on the other
                // display. So the windows are read one at a time, and a display is taken from the
                // window's own frame — an entry with no geometry would otherwise be filed under
                // whichever display happens to contain the origin.
                var framesByDisplay = [CGDirectDisplayID: [CGRect]]()
                var entriesByDisplay = [CGDirectDisplayID: Int]()
                for window in elements(application, kAXWindowsAttribute) ?? [] {
                    guard let windowFrame = frame(of: window) else {
                        continue
                    }
                    // Only real menu bar windows may supply item geometry. A popup
                    // published by this process must never become a hit-test zone.
                    guard windowFrame.height > 0, windowFrame.height <= 64 else { continue }
                    if activeDisplayBounds?.intersects(windowFrame) ?? false {
                        for child in elements(window, kAXChildrenAttribute) ?? [] {
                            guard let container = frame(of: child), !container.isEmpty else { continue }
                            var childPID: pid_t = 0
                            AXUIElementGetPid(child, &childPID)
                            if string(child, kAXRoleAttribute) == kAXButtonRole, childPID == pid {
                                chevronFrame = container
                                continue
                            }
                            let owner = (elements(child, kAXChildrenAttribute) ?? []).compactMap { nested -> pid_t? in
                                var nestedPID: pid_t = 0
                                AXUIElementGetPid(nested, &nestedPID)
                                return nestedPID > 0 && nestedPID != pid ? nestedPID : nil
                            }.first ?? childPID
                            if owner > 0, owner != pid {
                                agentFramesByOwner[owner, default: []].append(container)
                            }
                        }
                    }
                    var display = CGDirectDisplayID(0)
                    var matches: UInt32 = 0
                    CGGetDisplaysWithPoint(CGPoint(x: windowFrame.midX, y: windowFrame.minY + 1), 1, &display, &matches)
                    guard matches > 0 else {
                        continue
                    }
                    // An entry the bar lists without geometry answers no position at all, so a
                    // missing frame is kept as an empty one: the entry is what counts.
                    let childFrames = (elements(window, kAXChildrenAttribute) ?? []).map { child in
                        frame(of: elements(child, kAXChildrenAttribute)?.first ?? child) ?? .zero
                    }
                    // Added to, not replaced: one window per display is what macOS 27.0 has, but
                    // a second one would otherwise take the first one's entries away with it.
                    framesByDisplay[display, default: []].append(contentsOf: childFrames)
                    guard let clock = childFrames.max(by: { $0.width < $1.width }), clock.width > 80 else {
                        continue
                    }
                    let systemFrames = childFrames.filter { $0.width > 1 && $0.minX >= clock.minX - systemItemsSpan }
                    entriesByDisplay[display, default: 0] += StuckOverflow27.applicationEntryCount(
                        childFrames: childFrames,
                        systemItemFrames: systemFrames
                    )
                }
                let perDisplay = framesByDisplay.compactMapValues { frames -> [CGRect]? in
                    guard let clock = frames.max(by: { $0.width < $1.width }), clock.width > 80 else {
                        return nil
                    }
                    return frames.filter { $0.width > 1 && $0.minX >= clock.minX - systemItemsSpan }
                }
                lock.withLock {
                    lastSystemFramesByDisplay = perDisplay
                    lastBarFramesByDisplay = framesByDisplay
                    lastApplicationEntriesByDisplay = entriesByDisplay
                }
                let systemFrames = rawItems
                    .filter { $0.bundleID == menuBarAgentBundleID && (activeDisplayBounds?.intersects($0.frame) ?? true) }
                    .map(\.frame)
                lock.withLock {
                    lastSystemItemFrames = systemFrames
                    lastOverflowButtonFrame = chevronFrame
                }
            }
        }

        if retryIfMenuBarMoves, Bridging.getActiveMenuBarDisplayID() != activeDisplayID {
            return readItems(retryIfMenuBarMoves: false)
        }
        var newEntries = [CGWindowID: Entry]()
        var items = [MenuBarItem]()
        let identitiesBefore = savedIdentities
        for owner in agentFramesByOwner.keys {
            agentFramesByOwner[owner]?.sort { $0.minX < $1.minX }
        }
        var nextIndexByOwner = [pid_t: Int]()
        for raw in rawItems.sorted(by: { $0.pid == $1.pid ? $0.index < $1.index : $0.pid < $1.pid }) {
            guard let tag = tag(for: raw, ownPID: ownPID) else {
                continue
            }
            let windowID = SyntheticWindowID27.make(bundleID: raw.bundleID, identifier: tag.title, index: raw.index)
            if !tag.isControlItem, raw.bundleID != menuBarAgentBundleID {
                let identity = MenuBarItemIdentity27(bundleID: raw.bundleID, identifier: tag.title, index: raw.index)
                savedIdentities[identity.key] = identity
            }
            var bounds = raw.frame
            var isOnScreen = ItemDrawing27.isDrawn(itemFrame: bounds, activeDisplayBounds: activeDisplayBounds, chevronFrame: chevronFrame)
            if raw.bundleID != menuBarAgentBundleID {
                let index = nextIndexByOwner[raw.pid, default: 0]
                nextIndexByOwner[raw.pid] = index + 1
                if let frames = agentFramesByOwner[raw.pid], frames.indices.contains(index) {
                    let container = frames[index]
                    let height = min(container.height, max(22, raw.frame.height))
                    bounds = CGRect(x: container.minX, y: container.midY - height / 2, width: container.width, height: height)
                    isOnScreen = ItemDrawing27.isDrawn(itemFrame: bounds, activeDisplayBounds: activeDisplayBounds, chevronFrame: chevronFrame)
                } else {
                    // An unverified app-local frame is not a safe mouse target.
                    isOnScreen = false
                }
            }
            newEntries[windowID] = Entry(element: raw.element, bundleID: raw.bundleID, identifier: raw.identifier, frame: bounds)
            items.append(MenuBarItem(
                tag: tag,
                syntheticWindowID: windowID,
                ownerPID: raw.pid,
                bounds: bounds,
                title: raw.title,
                isOnScreen: isOnScreen
            ))
        }
        // Some applications temporarily withdraw AXExtrasMenuBar altogether
        // while concealed. Keep their known identities, never a terminated
        // process. Temporary reveals must not evict an application's identities.
        let prior = lock.withLock { (lastItems ?? [], entries) }
        let layout = Defaults.dictionary(forKey: .macOS27Layout) as? [String: Int] ?? [:]
        let hiddenBundles = Set(layout.compactMap { $0.value > 0 ? $0.key : nil })
        let managedHidden = Set(runningApplications.compactMap { app -> pid_t? in
            guard let bundleID = app.bundleIdentifier, hiddenBundles.contains(bundleID) else { return nil }
            return app.processIdentifier
        })
        let freshTags = Set(items.map(\.tag))
        let retained = HiddenItemRetention27.retainedIDs(
            previous: prior.0.map { (id: $0.windowID, pid: $0.ownerPID) },
            fresh: Set(newEntries.keys),
            running: Set(runningApplications.map(\.processIdentifier)),
            managedHidden: managedHidden
        )
        for previous in prior.0 where retained.contains(previous.windowID) && !freshTags.contains(previous.tag) {
            guard let entry = prior.1[previous.windowID] else { continue }
            newEntries[previous.windowID] = entry
            items.append(MenuBarItem(
                tag: previous.tag,
                syntheticWindowID: previous.windowID,
                ownerPID: previous.ownerPID,
                bounds: previous.bounds,
                title: previous.title,
                isOnScreen: false
            ))
        }
        let runningByBundle = Dictionary(
            runningApplications.compactMap { app in app.bundleIdentifier.map { ($0, app) } },
            uniquingKeysWith: { first, _ in first }
        )
        for identity in MenuBarItemIdentity27.missing(
            saved: Array(savedIdentities.values), freshKeys: Set(items.map { $0.tag.description }),
            runningBundles: Set(runningByBundle.keys), hiddenBundles: hiddenBundles
        ) {
            guard let app = runningByBundle[identity.bundleID] else { continue }
            let tag = MenuBarItemTag(namespace: .string(identity.bundleID), title: identity.identifier)
            newEntries[identity.windowID] = Entry(element: nil, bundleID: identity.bundleID, identifier: identity.identifier, frame: .zero)
            items.append(MenuBarItem(
                tag: tag, syntheticWindowID: identity.windowID, ownerPID: app.processIdentifier,
                bounds: .zero, title: app.localizedName, isOnScreen: false
            ))
        }
        if savedIdentities != identitiesBefore || !FileManager.default.fileExists(atPath: identityFile.path) {
            persistIdentities()
        }
        // Where the items' own run of the bar begins, for hover hit-testing. Only what is
        // drawn counts: a concealed item keeps a stale frame further left, which would make
        // Ice treat the freed part of the bar as occupied.
        let concealed = lock.withLock { concealedPIDs }
        let leftEdge = items
            .filter { item in
                guard !concealed.contains(item.ownerPID) else {
                    return false
                }
                // Ice's own items are collapsed to nothing on macOS 27 and report a frame at
                // the origin, which would drag the edge to the left of the whole bar and make
                // every spot count as occupied, so hovering would never reveal anything again.
                return item.isOnScreen && item.ownerPID != ownPID && !item.isControlItem && item.bounds.width > 4
            }
            .map(\.bounds.minX)
            .min()
        lock.withLock {
            entries = newEntries
            lastOverflowButtonFrame = chevronFrame
            lastSystemItemFrames = newEntries.values
                .filter { $0.bundleID == menuBarAgentBundleID && (activeDisplayBounds?.intersects($0.frame) ?? true) }
                .map(\.frame)
            if let activeDisplayID, let leftEdge {
                lastLeftEdges[activeDisplayID] = leftEdge
            }
        }
        return items
    }

    private static func tag(for raw: RawItem, ownPID: pid_t) -> MenuBarItemTag? {
        if raw.pid == ownPID {
            // Only Ice's control items, identified by `ControlItem`.
            return MenuBarItemTag.controlItems.first { $0.title == raw.identifier }
        }
        let title = raw.identifier.isEmpty ? "Item-\(raw.index)" : raw.identifier
        return MenuBarItemTag(namespace: .string(raw.bundleID), title: title)
    }

    private static var identityFile: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Ice/ItemIdentities27.json")
    }

    private static func loadIdentities() -> [String: MenuBarItemIdentity27] {
        var result = [String: MenuBarItemIdentity27]()
        struct CachedImage: Decodable { }
        let cacheFile = identityFile.deletingLastPathComponent().appendingPathComponent("ItemImages/index.json")
        if let data = try? Data(contentsOf: cacheFile),
           let cached = try? JSONDecoder().decode([String: CachedImage].self, from: data) {
            for key in cached.keys {
                if let identity = MenuBarItemIdentity27(imageCacheKey: key) { result[identity.key] = identity }
            }
        }
        if let data = try? Data(contentsOf: identityFile),
           let saved = try? JSONDecoder().decode([MenuBarItemIdentity27].self, from: data) {
            for identity in saved { result[identity.key] = identity }
        }
        return result
    }

    private static func persistIdentities() {
        do {
            let data = try JSONEncoder().encode(savedIdentities.values.sorted { $0.key < $1.key })
            try FileManager.default.createDirectory(at: identityFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: identityFile, options: .atomic)
        } catch {
            logger.error("Could not save menu item identities: \(error, privacy: .public)")
        }
    }

    // MARK: Accessibility Helpers

    private static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        guard let string = value(element, attribute) as? String, !string.isEmpty else {
            return nil
        }
        return string
    }

    private static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = value(element, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return (value as! AXUIElement) // swiftlint:disable:this force_cast
    }

    private static func elements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement]? {
        value(element, attribute) as? [AXUIElement]
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        guard
            let positionValue = value(element, kAXPositionAttribute),
            CFGetTypeID(positionValue) == AXValueGetTypeID(),
            let sizeValue = value(element, kAXSizeAttribute),
            CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else {
            return nil
        }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard
            AXValueGetValue(positionValue as! AXValue, .cgPoint, &position), // swiftlint:disable:this force_cast
            AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) // swiftlint:disable:this force_cast
        else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }
}

@available(macOS 27.0, *)
extension MenuBarItem {
    /// Creates an item read through Accessibility on macOS 27.
    init(
        tag: MenuBarItemTag,
        syntheticWindowID: CGWindowID,
        ownerPID: pid_t,
        bounds: CGRect,
        title: String?,
        isOnScreen: Bool
    ) {
        self.tag = tag
        self.windowID = syntheticWindowID
        self.ownerPID = ownerPID
        self.sourcePID = ownerPID
        self.bounds = bounds
        self.title = title
        self.isOnScreen = isOnScreen
    }
}
