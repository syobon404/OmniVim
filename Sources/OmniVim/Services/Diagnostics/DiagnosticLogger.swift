import Foundation

func diagnosticLog(_ message: String) {
    DiagnosticLogger.shared.log(message)
}

final class DiagnosticLogger: @unchecked Sendable {
    static let shared = DiagnosticLogger()

    private let queue = DispatchQueue(label: "com.omnivim.diagnostics", qos: .utility)
    private let fileManager = FileManager.default
    private let maximumFileSize: UInt64 = 2 * 1_024 * 1_024
    private let logURL: URL
    private var handle: FileHandle?

    private init() {
        logURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/OmniVim.log")
    }

    func log(_ message: String) {
        let line = "\(Date().ISO8601Format()) \(message)\n"
        queue.async { [weak self] in
            self?.write(Data(line.utf8))
        }
    }

    private func write(_ data: Data) {
        rotateIfNeeded(adding: UInt64(data.count))
        guard let handle = openHandleIfNeeded() else { return }
        do {
            try handle.write(contentsOf: data)
        } catch {
            try? handle.close()
            self.handle = nil
        }
    }

    private func openHandleIfNeeded() -> FileHandle? {
        if let handle { return handle }
        if !fileManager.fileExists(atPath: logURL.path) {
            _ = fileManager.createFile(atPath: logURL.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: logURL) else { return nil }
        _ = try? handle.seekToEnd()
        self.handle = handle
        return handle
    }

    private func rotateIfNeeded(adding incomingSize: UInt64) {
        let attributes = try? fileManager.attributesOfItem(atPath: logURL.path)
        let existingSize = (attributes?[.size] as? NSNumber)?.uint64Value ?? 0
        guard existingSize + incomingSize > maximumFileSize else { return }

        try? handle?.close()
        handle = nil
        let archivedURL = logURL.appendingPathExtension("1")
        try? fileManager.removeItem(at: archivedURL)
        if fileManager.fileExists(atPath: logURL.path) {
            try? fileManager.moveItem(at: logURL, to: archivedURL)
        }
    }
}
