//
//  ScreenCapture.swift
//  Ice
//

import CoreGraphics
import Foundation
import ScreenCaptureKit

/// A namespace for screen capture operations.
enum ScreenCapture {

    // MARK: Permissions

    /// Returns a Boolean value that indicates whether the app has screen
    /// capture permissions.
    static func checkPermissions() -> Bool {
        if #available(macOS 26.0, *) {
            return ModernScreenRecordingPermission.check()
        }
        for windowID in Bridging.getMenuBarWindowList(option: [.itemsOnly, .activeSpace]) {
            guard
                let window = WindowInfo(windowID: windowID),
                window.owningApplication != .current // Skip windows we own.
            else {
                continue
            }
            return window.title != nil
        }
        // CGPreflightScreenCaptureAccess() only returns an initial value,
        // but we can use it as a fallback.
        return CGPreflightScreenCaptureAccess()
    }

    /// Returns a Boolean value that indicates whether the app has screen
    /// capture permissions.
    ///
    /// This function caches its initial result and returns it on subsequent
    /// calls. Pass `true` to the `reset` parameter to replace the cached
    /// result with a newly computed value.
    static func cachedCheckPermissions(reset: Bool = false) -> Bool {
        if #available(macOS 26.0, *) {
            // The asynchronous first check may still be pending. Do not freeze
            // its initial false result for the lifetime of the app.
            return checkPermissions()
        }
        enum Context {
            static var cachedResult: Bool?
        }
        if !reset, let result = Context.cachedResult {
            return result
        }
        let result = checkPermissions()
        Context.cachedResult = result
        return result
    }

    /// Requests screen capture permissions.
    static func requestPermissions() {
        if #available(macOS 15.0, *) {
            // CGRequestScreenCaptureAccess() is broken on macOS 15. We can
            // try accessing SCShareableContent to trigger a request if the
            // user doesn't have permissions.
            // TODO: Find out if we still need this as of macOS 26.
            SCShareableContent.getWithCompletionHandler { _, _ in }
        } else {
            CGRequestScreenCaptureAccess()
        }
    }

    // MARK: Capture Window(s)

    /// Captures a composite image of an array of windows.
    ///
    /// The windows are composited from front to back, according to the order
    /// of the `windowIDs` parameter.
    ///
    /// - Parameters:
    ///   - windowIDs: The identifiers of the windows to capture.
    ///   - screenBounds: The bounds to capture, specified in screen coordinates.
    ///     Pass `nil` to capture the minimum rectangle that encloses the windows.
    ///   - option: Options that specify which parts of the windows are captured.
    static func captureWindows(with windowIDs: [CGWindowID], screenBounds: CGRect? = nil, option: CGWindowImageOption = []) -> CGImage? {
        guard let array = Bridging.createCGWindowArray(with: windowIDs) else {
            return nil
        }
        let bounds = screenBounds ?? .null
        // ScreenCaptureKit doesn't support capturing images of offscreen menu bar
        // items, so we unfortunately have to use the deprecated CGWindowList API.
        return CGImage(windowListFromArrayScreenBounds: bounds, windowArray: array, imageOption: option)
    }

    /// Captures an image of a window.
    ///
    /// - Parameters:
    ///   - windowID: The identifier of the window to capture.
    ///   - screenBounds: The bounds to capture, specified in screen coordinates.
    ///     Pass `nil` to capture the minimum rectangle that encloses the window.
    ///   - option: Options that specify which parts of the window are captured.
    static func captureWindow(with windowID: CGWindowID, screenBounds: CGRect? = nil, option: CGWindowImageOption = []) -> CGImage? {
        captureWindows(with: [windowID], screenBounds: screenBounds, option: option)
    }
}

/// Status items no longer expose usable window titles on modern macOS.
/// Query ScreenCaptureKit off the main thread, coalescing callers and keeping
/// successful checks fresh without enumerating every window on every UI update.
@available(macOS 26.0, *)
private enum ModernScreenRecordingPermission {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var state = ScreenRecordingPermissionState(
        granted: CGPreflightScreenCaptureAccess()
    )

    static func check() -> Bool {
        let (granted, refresh) = lock.withLock {
            let refresh = state.beginRefresh(at: ProcessInfo.processInfo.systemUptime)
            return (state.granted, refresh)
        }
        if refresh {
            SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { content, error in
                lock.withLock {
                    state.complete(
                        granted: content != nil && error == nil,
                        at: ProcessInfo.processInfo.systemUptime
                    )
                }
            }
        }
        return granted
    }
}
