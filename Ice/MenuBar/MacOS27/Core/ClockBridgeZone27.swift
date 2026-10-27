//
//  ClockBridgeZone27.swift
//  Ice
//

import CoreGraphics

/// Decides whether a click must be let through to a system item.
///
/// While an assessment-mode assertion is live, MenuBarAgent ignores clicks on
/// the clock (measured on macOS 27.0), so such clicks lift the assertion first.
enum ClockBridgeZone27 {
    static func shouldBridge(click: CGPoint, systemItemFrames: [CGRect], isConcealing: Bool, menuBarBounds: CGRect? = nil) -> Bool {
        guard isConcealing else {
            return false
        }
        if let menuBarBounds, !menuBarBounds.contains(click) { return false }
        return systemItemFrames.contains { frame in
            // A proxy may report the whole popup/window as an item's frame.
            // Never let that turn arbitrary application clicks into system clicks.
            guard !frame.isEmpty, frame.height <= (menuBarBounds?.height ?? 64) + 2 else { return false }
            return frame.insetBy(dx: -1, dy: -1).contains(click)
        }
    }

    static func isSystemIdentifier(_ identifier: String) -> Bool {
        ["com.apple.menuextra.clock", "com.apple.menuextra.battery", "com.apple.menuextra.wifi",
         "com.apple.menuextra.controlcenter", "com.apple.menuextra.audiovideo"].contains(identifier)
    }
}
