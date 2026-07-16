import AppKit
import Carbon.HIToolbox

enum TerminalApplicationPolicy {
    private static let bundleIdentifiers: Set<String> = [
        "com.apple.Terminal",
        "com.github.wez.wezterm",
        "com.googlecode.iterm2",
        "net.kovidgoyal.kitty"
    ]

    static func isTerminal(bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else { return false }
        return bundleIdentifiers.contains(bundleIdentifier)
    }
}

struct TerminalVimExecutionPlan: Equatable {
    let bridgeCommand: String?
    let resultingMode: BaseVimMode

    static func make(for command: VimCommand) -> TerminalVimExecutionPlan? {
        switch command {
        case .enterInsert:
            return TerminalVimExecutionPlan(bridgeCommand: nil, resultingMode: .insert)
        case let .move(motion):
            guard let bridgeCommand = movementCommand(for: motion) else { return nil }
            return TerminalVimExecutionPlan(
                bridgeCommand: bridgeCommand,
                resultingMode: .normal
            )
        case let .operate(vimOperator, motion):
            guard let bridgeCommand = operatorCommand(for: motion) else { return nil }
            return TerminalVimExecutionPlan(
                bridgeCommand: bridgeCommand,
                resultingMode: vimOperator == .change ? .insert : .normal
            )
        }
    }

    private static func movementCommand(for motion: VimMotion) -> String? {
        switch motion {
        case .characterLeft: "move-character-left"
        case .characterRight: "move-character-right"
        case .lineDown: "move-line-down"
        case .lineUp: "move-line-up"
        case .wordForward: "move-word-forward"
        case .wordBackward: "move-word-backward"
        case .lineStart: "move-line-start"
        case .lineEnd: "move-line-end"
        case .wholeLine: nil
        }
    }

    private static func operatorCommand(for motion: VimMotion) -> String? {
        switch motion {
        case .characterLeft: "delete-character-left"
        case .characterRight: "delete-character-right"
        case .wordForward: "delete-word-forward"
        case .wordBackward: "delete-word-backward"
        case .lineStart: "delete-line-start"
        case .lineEnd: "delete-line-end"
        case .wholeLine: "delete-whole-line"
        case .lineDown, .lineUp: nil
        }
    }
}

struct TerminalBridgePaths {
    let commandFile: URL
    let companionMarker: URL

    static var standard: TerminalBridgePaths {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/OmniVim", isDirectory: true)
        return TerminalBridgePaths(
            commandFile: directory.appendingPathComponent("terminal-command"),
            companionMarker: directory.appendingPathComponent("fish-companion-ready")
        )
    }
}

@MainActor
final class TerminalVimCommandExecutor {
    private let input: InputSynthesizer
    private let paths: TerminalBridgePaths
    private let fileManager: FileManager

    init(
        input: InputSynthesizer,
        paths: TerminalBridgePaths = .standard,
        fileManager: FileManager = .default
    ) {
        self.input = input
        self.paths = paths
        self.fileManager = fileManager
    }

    var isCompanionAvailable: Bool {
        fileManager.fileExists(atPath: paths.companionMarker.path)
    }

    func cancelPendingCommand() {
        guard fileManager.fileExists(atPath: paths.commandFile.path) else { return }
        do {
            try fileManager.removeItem(at: paths.commandFile)
            diagnosticLog("terminal bridge pending command cancelled")
        } catch {
            diagnosticLog("terminal bridge cleanup failed error=\(error.localizedDescription)")
        }
    }

    @discardableResult
    func execute(_ command: VimCommand) -> BaseVimMode? {
        guard let plan = TerminalVimExecutionPlan.make(for: command) else {
            diagnosticLog("terminal vim command unsupported=\(command)")
            return nil
        }
        guard let bridgeCommand = plan.bridgeCommand else { return plan.resultingMode }
        guard isCompanionAvailable, enqueue(bridgeCommand) else {
            diagnosticLog("terminal companion unavailable command=\(bridgeCommand)")
            return nil
        }

        input.sendKey(CGKeyCode(kVK_F20))
        diagnosticLog("terminal vim command=\(bridgeCommand) trigger=F20")
        return plan.resultingMode
    }

    private func enqueue(_ command: String) -> Bool {
        let directory = paths.commandFile.deletingLastPathComponent()
        do {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try Data("\(command)\n".utf8).write(to: paths.commandFile, options: .atomic)
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: paths.commandFile.path
            )
            return true
        } catch {
            diagnosticLog("terminal bridge write failed error=\(error.localizedDescription)")
            return false
        }
    }
}
