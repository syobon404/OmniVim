import AppKit
import Carbon.HIToolbox

struct ReadlineTUIExecutionPlan: Equatable {
    let strokes: [SyntheticKeyStroke]
    let resultingMode: BaseVimMode

    static func make(for command: VimCommand) -> ReadlineTUIExecutionPlan? {
        switch command {
        case .enterInsert:
            return ReadlineTUIExecutionPlan(strokes: [], resultingMode: .insert)
        case let .move(motion):
            guard let stroke = movementStroke(for: motion) else { return nil }
            return ReadlineTUIExecutionPlan(strokes: [stroke], resultingMode: .normal)
        case let .operate(vimOperator, motion):
            guard let strokes = deletionStrokes(for: motion) else { return nil }
            return ReadlineTUIExecutionPlan(
                strokes: strokes,
                resultingMode: vimOperator == .change ? .insert : .normal
            )
        }
    }

    private static func movementStroke(for motion: VimMotion) -> SyntheticKeyStroke? {
        switch motion {
        case .characterLeft: SyntheticKeyStroke(kVK_LeftArrow)
        case .characterRight: SyntheticKeyStroke(kVK_RightArrow)
        case .lineDown: SyntheticKeyStroke(kVK_DownArrow)
        case .lineUp: SyntheticKeyStroke(kVK_UpArrow)
        case .wordForward: SyntheticKeyStroke(kVK_ANSI_F, modifiers: [.option])
        case .wordBackward: SyntheticKeyStroke(kVK_ANSI_B, modifiers: [.option])
        case .lineStart: SyntheticKeyStroke(kVK_ANSI_A, modifiers: [.control])
        case .lineEnd: SyntheticKeyStroke(kVK_ANSI_E, modifiers: [.control])
        case .wholeLine: nil
        }
    }

    private static func deletionStrokes(for motion: VimMotion) -> [SyntheticKeyStroke]? {
        switch motion {
        case .characterLeft:
            [SyntheticKeyStroke(kVK_Delete)]
        case .characterRight:
            [SyntheticKeyStroke(kVK_ForwardDelete)]
        case .wordForward:
            [SyntheticKeyStroke(kVK_ANSI_D, modifiers: [.option])]
        case .wordBackward:
            [SyntheticKeyStroke(kVK_ANSI_W, modifiers: [.control])]
        case .lineStart:
            [SyntheticKeyStroke(kVK_ANSI_U, modifiers: [.control])]
        case .lineEnd:
            [SyntheticKeyStroke(kVK_ANSI_K, modifiers: [.control])]
        case .wholeLine:
            [
                SyntheticKeyStroke(kVK_ANSI_U, modifiers: [.control]),
                SyntheticKeyStroke(kVK_ANSI_K, modifiers: [.control])
            ]
        case .lineDown, .lineUp:
            nil
        }
    }
}

@MainActor
final class ReadlineTUIVimCommandExecutor {
    private let input: InputSynthesizer

    init(input: InputSynthesizer) {
        self.input = input
    }

    @discardableResult
    func execute(_ command: VimCommand) -> BaseVimMode? {
        guard let plan = ReadlineTUIExecutionPlan.make(for: command) else { return nil }
        for stroke in plan.strokes {
            input.sendKey(stroke.keyCode, modifiers: stroke.modifiers)
        }
        return plan.resultingMode
    }
}
