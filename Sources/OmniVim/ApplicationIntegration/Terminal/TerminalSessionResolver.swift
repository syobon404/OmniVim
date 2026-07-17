import Foundation

enum TerminalAdapterKind: String, Equatable, Sendable {
    case readlineTUI
}

enum TerminalProgramBehavior: Equatable, Sendable {
    case shellPrompt
    case adaptedTUI(TerminalAdapterKind)
    case nativeModal
    case passThrough

    var allowsOmniVim: Bool {
        switch self {
        case .shellPrompt, .adaptedTUI: true
        case .nativeModal, .passThrough: false
        }
    }
}

struct TerminalSessionIdentity: Equatable, Sendable {
    let terminalProcessIdentifier: pid_t
    let windowIdentifier: String
    let foregroundProcessIdentifier: pid_t
}

struct TerminalProgramContext: Equatable, Sendable {
    let identity: TerminalSessionIdentity
    let executableName: String
    let behavior: TerminalProgramBehavior
}

enum TerminalProgramClassifier {
    private static let shellsWithCompanions: Set<String> = ["fish"]
    private static let nativeModalPrograms: Set<String> = [
        "hx", "kak", "kakoune", "nvim", "vi", "view", "vim"
    ]
    private static let readlineTUIs: Set<String> = [
        "agy"
    ]
    private static let opaquePrograms: Set<String> = [
        "mosh", "screen", "ssh"
    ]

    static func classify(executable: String) -> TerminalProgramBehavior {
        let name = normalizedExecutableName(executable)
        if shellsWithCompanions.contains(name) { return .shellPrompt }
        if nativeModalPrograms.contains(name) { return .nativeModal }
        if readlineTUIs.contains(name) { return .adaptedTUI(.readlineTUI) }
        if opaquePrograms.contains(name) { return .passThrough }
        return .passThrough
    }

    static func normalizedExecutableName(_ executable: String) -> String {
        var name = URL(fileURLWithPath: executable).lastPathComponent.lowercased()
        while name.first == "-" { name.removeFirst() }
        return name
    }
}

enum KittySessionSnapshotParser {
    static func parse(data: Data, terminalProcessIdentifier: pid_t) throws -> TerminalProgramContext? {
        let root = try JSONSerialization.jsonObject(with: data)
        guard let window = firstWindow(in: root),
              let process = foregroundProcess(in: window),
              let processIdentifier = integer(process["pid"]),
              let executable = commandLine(in: process).first else { return nil }

        let executableName = TerminalProgramClassifier.normalizedExecutableName(executable)
        return TerminalProgramContext(
            identity: TerminalSessionIdentity(
                terminalProcessIdentifier: terminalProcessIdentifier,
                windowIdentifier: string(window["id"]) ?? "unknown",
                foregroundProcessIdentifier: pid_t(processIdentifier)
            ),
            executableName: executableName,
            behavior: TerminalProgramClassifier.classify(executable: executableName)
        )
    }

    private static func firstWindow(in value: Any) -> [String: Any]? {
        if let dictionary = value as? [String: Any] {
            if dictionary["foreground_processes"] != nil { return dictionary }
            for child in dictionary.values {
                if let window = firstWindow(in: child) { return window }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let window = firstWindow(in: child) { return window }
            }
        }
        return nil
    }

    private static func foregroundProcess(in window: [String: Any]) -> [String: Any]? {
        guard let processes = window["foreground_processes"] as? [[String: Any]] else { return nil }
        return processes.first { !commandLine(in: $0).isEmpty }
    }

    private static func commandLine(in process: [String: Any]) -> [String] {
        if let commandLine = process["cmdline"] as? [String] { return commandLine }
        if let commandLine = process["cmdline"] as? String { return [commandLine] }
        return []
    }

    private static func integer(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }

    private static func string(_ value: Any?) -> String? {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return nil
    }
}

actor TerminalSessionResolver {
    private let kittyExecutable = URL(
        fileURLWithPath: "/Applications/kitty.app/Contents/MacOS/kitten"
    )

    func resolve(bundleIdentifier: String?, terminalProcessIdentifier: pid_t) -> TerminalProgramContext? {
        guard bundleIdentifier == "net.kovidgoyal.kitty" else { return nil }
        let socket = "unix:/tmp/omnivim-kitty-\(terminalProcessIdentifier)"
        let process = Process()
        let output = Pipe()
        process.executableURL = kittyExecutable
        process.arguments = [
            "@", "--to", socket,
            "ls", "--match", "state:focused"
        ]
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return try KittySessionSnapshotParser.parse(
                data: data,
                terminalProcessIdentifier: terminalProcessIdentifier
            )
        } catch {
            return nil
        }
    }
}
