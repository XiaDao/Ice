import Foundation

/// Persistent identity only: never persist a PID, AX element, or screen position.
struct MenuBarItemIdentity27: Codable, Hashable {
    let bundleID: String
    let identifier: String
    let index: Int

    var key: String { "\(bundleID):\(identifier)" }
    var windowID: UInt32 {
        SyntheticWindowID27.make(bundleID: bundleID, identifier: identifier, index: index)
    }

    init(bundleID: String, identifier: String, index: Int) {
        self.bundleID = bundleID
        self.identifier = identifier
        self.index = index
    }

    /// Migrates identities already represented by the on-disk glyph cache.
    init?(imageCacheKey: String) {
        let parts = imageCacheKey.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
        let identifier = String(parts[1])
        let index = identifier.hasPrefix("Item-") ? Int(identifier.dropFirst(5)) : 0
        guard let index, index >= 0 else { return nil }
        self.init(bundleID: String(parts[0]), identifier: identifier, index: index)
    }

    static func missing(
        saved: [Self], freshKeys: Set<String>, runningBundles: Set<String>, hiddenBundles: Set<String>
    ) -> [Self] {
        var seen = freshKeys
        return saved.filter {
            runningBundles.contains($0.bundleID) && hiddenBundles.contains($0.bundleID) && seen.insert($0.key).inserted
        }
    }
}
