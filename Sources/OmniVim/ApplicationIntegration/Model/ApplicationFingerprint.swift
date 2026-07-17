import AppKit

enum ApplicationRuntimeMarker: String, Codable, Hashable, CaseIterable {
    case chromium
    case electron
    case unknown
}

struct ApplicationFingerprint: Codable, Hashable {
    static let schemaVersion = 1

    let bundleIdentifier: String
    let version: String?
    let buildVersion: String?
    let executableName: String?
    let runtimeMarkers: Set<ApplicationRuntimeMarker>

    var cacheKey: String {
        let marker = runtimeMarkers.map(\.rawValue).sorted().joined(separator: "-")
        return [bundleIdentifier, version, buildVersion, marker]
            .compactMap { $0 }
            .joined(separator: "-")
            .map { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" ? $0 : "_" }
            .reduce(into: "") { $0.append($1) }
    }

    static func make(
        runningApplication: NSRunningApplication?,
        fallbackBundleIdentifier: String?
    ) -> ApplicationFingerprint {
        let bundleURL = runningApplication?.bundleURL
        let bundle = bundleURL.flatMap(Bundle.init(url:))
        return ApplicationFingerprint(
            bundleIdentifier: runningApplication?.bundleIdentifier
                ?? fallbackBundleIdentifier
                ?? "unknown",
            version: bundle?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            buildVersion: bundle?.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
            executableName: bundle?.object(forInfoDictionaryKey: "CFBundleExecutable") as? String,
            runtimeMarkers: runtimeMarkers(in: bundleURL)
        )
    }

    private static func runtimeMarkers(in bundleURL: URL?) -> Set<ApplicationRuntimeMarker> {
        guard let frameworksURL = bundleURL?
            .appendingPathComponent("Contents/Frameworks", isDirectory: true),
              let names = try? FileManager.default.contentsOfDirectory(
                  at: frameworksURL,
                  includingPropertiesForKeys: nil
              ).map({ $0.lastPathComponent.lowercased() }) else { return [.unknown] }

        var markers: Set<ApplicationRuntimeMarker> = []
        if names.contains(where: { $0.contains("electron framework") }) {
            markers.formUnion([.electron, .chromium])
        } else if names.contains(where: { $0.contains("chromium") }) {
            markers.insert(.chromium)
        }
        return markers.isEmpty ? [.unknown] : markers
    }
}
