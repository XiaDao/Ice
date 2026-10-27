import CoreGraphics

enum ItemMenuPolicy27 {
    struct Window {
        let number: UInt32
        let ownerPID: Int32
        let layer: Int
        let bounds: CGRect
    }

    /// macOS may host the app's menu in MenuBarAgent instead of the source app.
    static func menuWindows(_ windows: [Window], owners: Set<Int32>, baseline: Set<UInt32>) -> [Window] {
        windows.filter {
            owners.contains($0.ownerPID) && !baseline.contains($0.number) &&
            $0.layer >= 20 && $0.bounds.height > 30 && !$0.bounds.isEmpty
        }
    }

    /// All submenu rectangles participate; selecting an entry must be left to AppKit.
    static func dismissesMenu(click: CGPoint, menuFrames: [CGRect]) -> Bool {
        !menuFrames.contains { $0.contains(click) }
    }
}
