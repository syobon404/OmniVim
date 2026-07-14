import AppKit

struct AXRectSnapshot: Codable, Equatable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    init(_ frame: CGRect) {
        x = frame.origin.x
        y = frame.origin.y
        width = frame.width
        height = frame.height
    }
}

struct AXNodeSnapshot: Codable, Identifiable, Equatable {
    let id: Int
    let parentID: Int?
    let depth: Int
    let role: String
    let subrole: String
    let title: String
    let description: String
    let value: String
    let identifier: String
    let actions: [String]
    let frame: AXRectSnapshot?
    let enabled: Bool?
    let focused: Bool?
}

struct AXApplicationSnapshot: Codable, Equatable {
    let capturedAt: Date
    let processIdentifier: Int32
    let bundleIdentifier: String
    let applicationName: String
    let nodes: [AXNodeSnapshot]
}

@MainActor
final class AXSnapshotRecorder {
    private let maximumNodes = 5_000
    private let maximumDepth = 30

    func captureFrontmost() -> AXApplicationSnapshot? {
        guard AXIsProcessTrusted(), let app = NSWorkspace.shared.frontmostApplication else { return nil }
        return capture(processIdentifier: app.processIdentifier)
    }

    func capture(processIdentifier: pid_t) -> AXApplicationSnapshot? {
        guard AXIsProcessTrusted(), let app = NSRunningApplication(processIdentifier: processIdentifier) else { return nil }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        var queue: [(element: AXUIElement, parentID: Int?, depth: Int)] = [(root, nil, 0)]
        var cursor = 0
        var nodes: [AXNodeSnapshot] = []

        while cursor < queue.count, nodes.count < maximumNodes {
            let item = queue[cursor]
            cursor += 1
            let id = nodes.count
            nodes.append(snapshot(of: item.element, id: id, parentID: item.parentID, depth: item.depth))
            guard item.depth < maximumDepth else { continue }
            for child in children(of: item.element) {
                queue.append((child, id, item.depth + 1))
            }
        }

        return AXApplicationSnapshot(
            capturedAt: Date(),
            processIdentifier: app.processIdentifier,
            bundleIdentifier: app.bundleIdentifier ?? "",
            applicationName: app.localizedName ?? "Unknown",
            nodes: nodes
        )
    }

    func encode(_ snapshot: AXApplicationSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(snapshot)
    }

    func save(_ snapshot: AXApplicationSnapshot) throws -> URL {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/OmniVim/Snapshots", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let safeBundle = snapshot.bundleIdentifier.isEmpty ? "unknown" : snapshot.bundleIdentifier
        let url = directory.appendingPathComponent("\(safeBundle)-\(formatter.string(from: snapshot.capturedAt)).json")
        try encode(snapshot).write(to: url, options: .atomic)
        diagnosticLog("AX snapshot saved path=\(url.path) nodes=\(snapshot.nodes.count)")
        return url
    }

    private func snapshot(of element: AXUIElement, id: Int, parentID: Int?, depth: Int) -> AXNodeSnapshot {
        AXNodeSnapshot(
            id: id,
            parentID: parentID,
            depth: depth,
            role: string(kAXRoleAttribute, from: element),
            subrole: string(kAXSubroleAttribute, from: element),
            title: string(kAXTitleAttribute, from: element),
            description: string(kAXDescriptionAttribute, from: element),
            value: string(kAXValueAttribute, from: element),
            identifier: string(kAXIdentifierAttribute, from: element),
            actions: actions(of: element),
            frame: frame(of: element).map(AXRectSnapshot.init),
            enabled: boolean(kAXEnabledAttribute, from: element),
            focused: boolean(kAXFocusedAttribute, from: element)
        )
    }

    private func children(of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success else { return [] }
        return (value as? [AXUIElement]) ?? []
    }

    private func actions(of element: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyActionNames(element, &names) == .success else { return [] }
        return (names as? [String]) ?? []
    }

    private func string(_ attribute: String, from element: AXUIElement) -> String {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return "" }
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return ""
    }

    private func boolean(_ attribute: String, from element: AXUIElement) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return (value as? NSNumber)?.boolValue
    }

    private func frame(of element: AXUIElement) -> CGRect? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let positionRef, let sizeRef,
              CFGetTypeID(positionRef) == AXValueGetTypeID(),
              CFGetTypeID(sizeRef) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionRef as! AXValue, .cgPoint, &point),
              AXValueGetValue(sizeRef as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: point, size: size)
    }
}
