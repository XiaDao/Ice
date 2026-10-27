import CoreGraphics

/// Item order is independent of the application-level hiding assignment.
enum SectionOrder27 {
    /// An incomplete scan must not discard the position of an absent item.
    static func merging(observed: [String], saved: [String]) -> [String] {
        var seen = Set<String>()
        return (saved + observed).filter { seen.insert($0).inserted }
    }

    /// Move only the dragged identity; preserve absent neighbours and siblings.
    static func moving(_ item: String, in saved: [String], displayed: [String]) -> [String] {
        let combined = merging(observed: displayed, saved: saved)
        guard let index = displayed.firstIndex(of: item) else { return combined }
        var result = combined.filter { $0 != item }
        if let next = displayed.dropFirst(index + 1).first,
           let target = result.firstIndex(of: next) {
            result.insert(item, at: target)
        } else if let previous = displayed.prefix(index).last,
                  let target = result.firstIndex(of: previous) {
            result.insert(item, at: target + 1)
        } else {
            result.append(item)
        }
        return result
    }

    /// Only same-display, genuinely drawn status-item geometry can drive a drag.
    static func canDrag(from source: CGRect, to target: CGRect, display: CGRect) -> Bool {
        let strip = CGRect(x: display.minX, y: display.minY, width: display.width, height: 64)
        return [source, target].allSatisfy {
            !$0.isEmpty && !$0.isNull && !$0.isInfinite && $0.height <= 64 && strip.contains($0)
        } && abs(source.midY - target.midY) < min(source.height, target.height) / 2
    }

    static func isAdjacent(_ item: String, to target: String, before: Bool, order: [String]) -> Bool {
        guard let a = order.firstIndex(of: item), let b = order.firstIndex(of: target) else { return false }
        return a == b + (before ? -1 : 1)
    }
}
