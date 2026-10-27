//
//  IceBarColorManager.swift
//  Ice
//

import Combine
import ScreenCaptureKit
import SwiftUI

final class IceBarColorManager: ObservableObject {
    @Published private(set) var colorInfo: MenuBarAverageColorInfo?

    private weak var iceBarPanel: IceBarPanel?

    private var windowImage: CGImage?
    private var colorTask27: Task<Void, Never>?

    private var cancellables = Set<AnyCancellable>()

    func performSetup(with iceBarPanel: IceBarPanel) {
        self.iceBarPanel = iceBarPanel
        configureCancellables()
    }

    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        if let iceBarPanel {
            iceBarPanel.publisher(for: \.screen)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] screen in
                    guard
                        let self,
                        let screen,
                        screen == .main
                    else {
                        return
                    }
                    updateWindowImage(for: screen)
                }
                .store(in: &c)

            iceBarPanel.publisher(for: \.isVisible)
                .receive(on: DispatchQueue.main)
                .sink { [weak self, weak iceBarPanel] isVisible in
                    guard
                        let self,
                        let iceBarPanel,
                        let screen = iceBarPanel.screen,
                        isVisible,
                        screen == .main
                    else {
                        return
                    }
                    updateColorInfo(with: iceBarPanel.frame, screen: screen)
                }
                .store(in: &c)

            iceBarPanel.publisher(for: \.frame)
                .throttle(for: 0.1, scheduler: DispatchQueue.main, latest: true)
                .sink { [weak self, weak iceBarPanel] frame in
                    guard
                        let self,
                        let iceBarPanel,
                        let screen = iceBarPanel.screen,
                        iceBarPanel.isVisible,
                        screen == .main
                    else {
                        return
                    }
                    withAnimation(.interactiveSpring) {
                        self.updateColorInfo(with: frame, screen: screen)
                    }
                }
                .store(in: &c)

            Publishers.Merge4(
                NSWorkspace.shared.notificationCenter
                    .publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
                    .replace(with: ()),
                NotificationCenter.default
                    .publisher(for: NSApplication.didChangeScreenParametersNotification)
                    .replace(with: ()),
                DistributedNotificationCenter.default()
                    .publisher(for: DistributedNotificationCenter.interfaceThemeChangedNotification)
                    .replace(with: ()),
                Timer.publish(every: 5, on: .main, in: .default)
                    .autoconnect()
                    .replace(with: ())
            )
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak iceBarPanel] in
                guard
                    let self,
                    let iceBarPanel,
                    let screen = iceBarPanel.screen,
                    screen == .main
                else {
                    return
                }
                updateWindowImage(for: screen)
                if iceBarPanel.isVisible {
                    withAnimation {
                        self.updateColorInfo(with: iceBarPanel.frame, screen: screen)
                    }
                }
            }
            .store(in: &c)
        }

        cancellables = c
    }

    private func updateWindowImage(for screen: NSScreen) {
        if #available(macOS 27.0, *) {
            return
        }
        let windows = WindowInfo.createWindows(option: .onScreen)
        let displayID = screen.displayID

        guard
            let menuBarWindow = WindowInfo.menuBarWindow(from: windows, for: displayID),
            let wallpaperWindow = WindowInfo.wallpaperWindow(from: windows, for: displayID)
        else {
            return
        }

        guard let image = ScreenCapture.captureWindows(
            with: [menuBarWindow.windowID, wallpaperWindow.windowID],
            screenBounds: withMutableCopy(of: wallpaperWindow.bounds) { $0.size.height = 1 },
            option: .nominalResolution
        ) else {
            return
        }

        windowImage = image
    }

    private func updateColorInfo(with frame: CGRect, screen: NSScreen) {
        if #available(macOS 27.0, *) {
            updateColorInfo27(with: frame, screen: screen)
            return
        }
        guard let image = windowImage else {
            return
        }

        let imageBounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)

        let insetScreenFrame = screen.frame.insetBy(dx: frame.width / 2, dy: 0)
        let percentage = ((frame.midX - insetScreenFrame.minX) / insetScreenFrame.width).clamped(to: 0...1)

        let cropRect = CGRect(x: imageBounds.width * percentage, y: 0, width: 0, height: 1)
            .insetBy(dx: -150, dy: 0)
            .intersection(imageBounds)

        guard
            let croppedImage = image.cropping(to: cropRect),
            let averageColor = croppedImage.averageColor()
        else {
            return
        }

        // Just use `menuBarWindow` as the source for now, regardless
        // of whether its image contributed to the average.
        colorInfo = MenuBarAverageColorInfo(color: averageColor, source: .menuBarWindow)
    }

    func updateAllProperties(with frame: CGRect, screen: NSScreen) {
        updateWindowImage(for: screen)
        updateColorInfo(with: frame, screen: screen)
    }

    /// The layout editor keeps an opaque neutral surface for its original
    /// bitmap previews; the floating Ice Bar uses the sampled material instead.
    static func layoutColor27() -> CGColor {
        var color = NSColor.windowBackgroundColor
        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
            color = NSColor.windowBackgroundColor.usingColorSpace(.sRGB) ?? color
        }
        return color.cgColor
    }

    /// Samples only a narrow background strip at the top of the correct display.
    /// No per-item WindowServer windows or opaque system-appearance colour needed.
    @available(macOS 27.0, *)
    private func updateColorInfo27(with frame: CGRect, screen: NSScreen) {
        colorTask27?.cancel()
        colorTask27 = Task { @MainActor [weak self] in
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let display = content.displays.first(where: { $0.displayID == screen.displayID }) else { return }
                let ownPID = ProcessInfo.processInfo.processIdentifier
                let ownWindows = content.windows.filter { $0.owningApplication?.processID == ownPID }
                let filter = SCContentFilter(display: display, excludingWindows: ownWindows)
                let width = min(screen.frame.width, 180)
                let x = (frame.midX - screen.frame.minX - width / 2).clamped(to: 0...(screen.frame.width - width))
                let configuration = SCStreamConfiguration()
                configuration.sourceRect = CGRect(x: x, y: 1, width: width, height: 2)
                configuration.width = Int(width * CGFloat(filter.pointPixelScale))
                configuration.height = max(1, Int(2 * CGFloat(filter.pointPixelScale)))
                configuration.showsCursor = false
                let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
                guard !Task.isCancelled, let color = image.averageColor() else { return }
                self?.colorInfo = MenuBarAverageColorInfo(color: color, source: .menuBarWindow)
            } catch {
                // Keep the last usable tint if a display changes during capture.
            }
        }
    }
}
