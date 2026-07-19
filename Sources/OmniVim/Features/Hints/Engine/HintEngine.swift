import CoreGraphics
import Foundation

struct HintDeduplicator {
    struct Item: Equatable {
        let role: String
        let title: String
        let frame: CGRect
    }

    func deduplicate(_ items: [Item]) -> [Item] {
        var result: [Item] = []
        for item in items {
            let normalizedTitle = normalize(item.title)
            guard !normalizedTitle.isEmpty else {
                result.append(item)
                continue
            }

            if let index = result.firstIndex(where: {
                normalize($0.title) == normalizedTitle && isVisualDuplicate($0, item)
            }) {
                if priority(item.role) > priority(result[index].role) {
                    result[index] = item
                }
            } else {
                result.append(item)
            }
        }
        return result
    }

    private func normalize(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func priority(_ role: String) -> Int {
        switch role {
        case "AXRow": return 3
        case "AXCell": return 2
        default: return 1
        }
    }

    private func isVisualDuplicate(_ lhs: Item, _ rhs: Item) -> Bool {
        let smallerArea = min(lhs.frame.width * lhs.frame.height, rhs.frame.width * rhs.frame.height)
        guard smallerArea > 0 else { return false }
        let overlap = lhs.frame.intersection(rhs.frame)
        let overlapRatio = max(0, overlap.width * overlap.height) / smallerArea
        let verticalDistance = abs(lhs.frame.midY - rhs.frame.midY)
        return overlapRatio >= 0.55 || (verticalDistance <= max(lhs.frame.height, rhs.frame.height) * 0.6
            && abs(lhs.frame.midX - rhs.frame.midX) <= max(lhs.frame.width, rhs.frame.width) * 0.35)
    }
}

struct HintCodeGenerator {
    var characters = Array("sadfjklewcmpgh")

    func generate(count: Int) -> [String] {
        guard count > 0, characters.count > 1 else { return [] }
        var candidates = [""]
        var offset = 0
        while candidates.count - offset < count || candidates.count == 1 {
            let suffix = candidates[offset]
            offset += 1
            for character in characters {
                candidates.append(String(character) + suffix)
            }
        }
        return candidates[offset..<(offset + count)]
            .sorted()
            .map { String($0.reversed()) }
    }
}

struct HintVisibilityInput: Equatable {
    let frame: CGRect
    let ancestorClips: [CGRect]
    let hitTestVisible: Bool
}

struct HintVisibilityEngine {
    func visibleFrame(for input: HintVisibilityInput) -> CGRect? {
        guard input.hitTestVisible, input.frame.width > 8, input.frame.height > 8 else { return nil }
        let clipped = input.ancestorClips.reduce(input.frame) { $0.intersection($1) }
        guard !clipped.isNull, clipped.width > 8, clipped.height > 8 else { return nil }
        return clipped
    }
}

struct HintLayoutEngine {
    let spacing: CGFloat

    init(spacing: CGFloat = 3) {
        self.spacing = spacing
    }

    func place(preferredFrames: [CGRect], within bounds: CGRect) -> [CGRect] {
        var occupied: [CGRect] = []
        return preferredFrames.map { preferred in
            let resolved = resolve(preferred, within: bounds, occupied: occupied)
            occupied.append(resolved)
            return resolved
        }
    }

    private func resolve(_ desired: CGRect, within bounds: CGRect, occupied: [CGRect]) -> CGRect {
        let xStep = desired.width + spacing
        let yStep = desired.height + spacing
        var offsets: [CGPoint] = [
            .zero,
            CGPoint(x: xStep, y: 0),
            CGPoint(x: 0, y: -yStep),
            CGPoint(x: -xStep, y: 0),
            CGPoint(x: 0, y: yStep),
            CGPoint(x: xStep, y: -yStep),
            CGPoint(x: -xStep, y: -yStep)
        ]
        for radius in 2...5 {
            for y in -radius...radius {
                for x in -radius...radius where max(abs(x), abs(y)) == radius {
                    offsets.append(CGPoint(
                        x: CGFloat(x) * xStep,
                        y: CGFloat(y) * yStep
                    ))
                }
            }
        }

        for offset in offsets {
            var frame = desired.offsetBy(dx: offset.x, dy: offset.y)
            frame.origin.x = min(max(frame.minX, bounds.minX), bounds.maxX - frame.width)
            frame.origin.y = min(max(frame.minY, bounds.minY), bounds.maxY - frame.height)
            if !occupied.contains(where: { $0.insetBy(dx: -2, dy: -2).intersects(frame) }) {
                return frame
            }
        }
        return desired
    }
}
