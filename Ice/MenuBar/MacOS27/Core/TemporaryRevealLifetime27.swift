import Foundation

/// A menu lifetime and the configured temporary icon lifetime are independent.
struct TemporaryRevealLifetime27 {
    let interval: TimeInterval
    private(set) var deadline: TimeInterval
    private(set) var openMenus = 0

    init(now: TimeInterval, interval: TimeInterval) {
        self.interval = interval.isFinite ? max(1, interval) : 15
        deadline = now + self.interval
    }

    mutating func beginMenu(at now: TimeInterval) {
        openMenus += 1
        deadline = now + interval
    }

    mutating func endMenu(at now: TimeInterval) {
        openMenus = max(0, openMenus - 1)
        deadline = now + interval
    }

    mutating func renew(at now: TimeInterval) { deadline = now + interval }

    func mayHide(at now: TimeInterval) -> Bool { openMenus == 0 && now >= deadline }
}
