import Foundation

final class CapabilityReportCache {
    private let directoryURL: URL
    private var memory: [ApplicationFingerprint: ApplicationCapabilityReport] = [:]

    init(directoryURL: URL = CapabilityReportCache.standardDirectoryURL) {
        self.directoryURL = directoryURL
    }

    func report(for fingerprint: ApplicationFingerprint) -> ApplicationCapabilityReport? {
        if let report = memory[fingerprint] { return report }
        let url = fileURL(for: fingerprint)
        guard let data = try? Data(contentsOf: url),
              let report = try? decoder.decode(ApplicationCapabilityReport.self, from: data),
              report.schemaVersion == ApplicationCapabilityReport.schemaVersion,
              report.fingerprint == fingerprint else { return nil }
        memory[fingerprint] = report
        return report
    }

    func store(_ report: ApplicationCapabilityReport) {
        memory[report.fingerprint] = report
        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            try encoder.encode(report).write(
                to: fileURL(for: report.fingerprint),
                options: .atomic
            )
        } catch {
            diagnosticLog("capability cache write failed error=\(error.localizedDescription)")
        }
    }

    private func fileURL(for fingerprint: ApplicationFingerprint) -> URL {
        directoryURL.appendingPathComponent("\(fingerprint.cacheKey).json")
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    static var standardDirectoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Application Support/OmniVim/Compatibility/Reports",
                isDirectory: true
            )
    }
}
