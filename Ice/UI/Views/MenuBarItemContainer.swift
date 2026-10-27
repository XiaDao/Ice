//
//  MenuBarItemContainer.swift
//  Ice
//

import SwiftUI

/// A view that is drawn in the style of the menu bar.
///
/// - Important: This view performs drawing on layers above and
///   below the content view. The resulting view will probably look
///   incorrect if the content view's background is not transparent.
struct MenuBarItemContainer<Content: View>: View {
    enum ColorInfoAccessor {
        case automatic
        case manual(MenuBarAverageColorInfo?)
    }

    @ObservedObject private var appState: AppState
    @ObservedObject private var appearanceManager: MenuBarAppearanceManager
    @ObservedObject private var menuBarManager: MenuBarManager

    private let accessor: ColorInfoAccessor
    private let content: Content

    private var colorInfo: MenuBarAverageColorInfo? {
        switch accessor {
        case .automatic:
            menuBarManager.averageColorInfo
        case .manual(let colorInfo):
            colorInfo
        }
    }

    private var foreground: Color {
        if #available(macOS 27.0, *), case .automatic = accessor { return .primary }
        return colorInfo?.isBright == true ? .black : .white
    }

    private var configuration: MenuBarAppearancePartialConfiguration {
        appearanceManager.configuration.current
    }

    init(appState: AppState, accessor: ColorInfoAccessor, @ViewBuilder content: () -> Content) {
        self.appState = appState
        self.appearanceManager = appState.appearanceManager
        self.menuBarManager = appState.menuBarManager
        self.accessor = accessor
        self.content = content()
    }

    var body: some View {
        content
            .foregroundStyle(foreground)
            .background {
                contentBackground
            }
            .overlay {
                contentOverlay
                    .opacity(0.2)
                    .allowsHitTesting(false)
            }
    }

    @ViewBuilder
    private var contentBackground: some View {
        if #available(macOS 27.0, *), case .automatic = accessor {
            // Layout belongs to the settings appearance. A sampled CGColor
            // lags a system theme transition and can briefly hide every glyph.
            Color(nsColor: .windowBackgroundColor)
        } else if appState.activeSpace.isFullscreen {
            Color.black
        } else if #available(macOS 27.0, *), case .manual = accessor {
            // Ice Bar: preserve the backdrop through a real visual-effect
            // material, tinted from the menu bar rather than solid window white.
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
            if let colorInfo {
                Color(cgColor: colorInfo.color).opacity(0.55)
            }
        } else if let colorInfo {
            Color(cgColor: colorInfo.color)
        } else {
            Color.defaultLayoutBar
        }
    }

    @ViewBuilder
    private var contentOverlay: some View {
        if !appState.activeSpace.isFullscreen {
            if case .solid = configuration.tintKind {
                Color(cgColor: configuration.tintColor)
            } else if
                case .gradient = configuration.tintKind,
                let color = configuration.tintGradient.averageColor()
            {
                Color(cgColor: color)
            }
        }
    }
}

extension View {
    /// Draws the view in the style of the menu bar.
    ///
    /// - Important: This modifier performs drawing on layers above and
    ///   below the current view. The resulting view will probably look
    ///   incorrect if the current view's background is not transparent.
    ///
    /// - Parameter appState: The shared ``AppState`` object.
    func menuBarItemContainer(appState: AppState) -> some View {
        MenuBarItemContainer(appState: appState, accessor: .automatic) { self }
    }

    /// Draws the view in the style of the menu bar.
    ///
    /// This modifier ignores the ``MenuBarManager/averageColorInfo``
    /// property, and instead uses the provided color information.
    ///
    /// - Important: This modifier performs drawing on layers above and
    ///   below the current view. The resulting view will probably look
    ///   incorrect if the current view's background is not transparent.
    ///
    /// - Parameters:
    ///   - appState: The shared ``AppState`` object.
    ///   - colorInfo: Information for the average color of the menu bar.
    func menuBarItemContainer(appState: AppState, colorInfo: MenuBarAverageColorInfo?) -> some View {
        MenuBarItemContainer(appState: appState, accessor: .manual(colorInfo)) { self }
    }
}
