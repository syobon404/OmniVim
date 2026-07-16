import AppKit
import Carbon.HIToolbox

struct SyntheticKeyStroke: Equatable {
    let keyCode: CGKeyCode
    let modifiers: NSEvent.ModifierFlags

    init(_ keyCode: Int, modifiers: NSEvent.ModifierFlags = []) {
        self.keyCode = CGKeyCode(keyCode)
        self.modifiers = modifiers
    }
}

struct SyntheticVimExecutionPlan: Equatable {
    let strokes: [SyntheticKeyStroke]
    let resultingMode: BaseVimMode

    static func make(for command: VimCommand) -> SyntheticVimExecutionPlan? {
        switch command {
        case .enterInsert:
            return SyntheticVimExecutionPlan(strokes: [], resultingMode: .insert)
        case let .move(motion):
            guard let stroke = movementStroke(for: motion) else { return nil }
            return SyntheticVimExecutionPlan(strokes: [stroke], resultingMode: .normal)
        case let .operate(vimOperator, motion):
            guard var strokes = selectionStrokes(for: motion, operator: vimOperator) else {
                return nil
            }
            strokes.append(SyntheticKeyStroke(kVK_Delete))
            return SyntheticVimExecutionPlan(
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
        case .wordForward: SyntheticKeyStroke(kVK_RightArrow, modifiers: [.option])
        case .wordBackward: SyntheticKeyStroke(kVK_LeftArrow, modifiers: [.option])
        case .lineStart: SyntheticKeyStroke(kVK_LeftArrow, modifiers: [.command])
        case .lineEnd: SyntheticKeyStroke(kVK_RightArrow, modifiers: [.command])
        case .wholeLine: nil
        }
    }

    private static func selectionStrokes(
        for motion: VimMotion,
        operator vimOperator: VimOperator
    ) -> [SyntheticKeyStroke]? {
        switch motion {
        case .characterLeft:
            return [SyntheticKeyStroke(kVK_LeftArrow, modifiers: [.shift])]
        case .characterRight:
            return [SyntheticKeyStroke(kVK_RightArrow, modifiers: [.shift])]
        case .lineDown:
            return [SyntheticKeyStroke(kVK_DownArrow, modifiers: [.shift])]
        case .lineUp:
            return [SyntheticKeyStroke(kVK_UpArrow, modifiers: [.shift])]
        case .wordForward:
            return [SyntheticKeyStroke(kVK_RightArrow, modifiers: [.option, .shift])]
        case .wordBackward:
            return [SyntheticKeyStroke(kVK_LeftArrow, modifiers: [.option, .shift])]
        case .lineStart:
            return [SyntheticKeyStroke(kVK_LeftArrow, modifiers: [.command, .shift])]
        case .lineEnd:
            return [SyntheticKeyStroke(kVK_RightArrow, modifiers: [.command, .shift])]
        case .wholeLine:
            var strokes = [
                SyntheticKeyStroke(kVK_LeftArrow, modifiers: [.command]),
                SyntheticKeyStroke(kVK_RightArrow, modifiers: [.command, .shift])
            ]
            if vimOperator == .delete {
                strokes.append(SyntheticKeyStroke(kVK_RightArrow, modifiers: [.shift]))
            }
            return strokes
        }
    }
}

@MainActor
final class SyntheticVimCommandExecutor {
    private let input: InputSynthesizer

    init(input: InputSynthesizer) {
        self.input = input
    }

    @discardableResult
    func execute(_ command: VimCommand) -> BaseVimMode? {
        guard let plan = SyntheticVimExecutionPlan.make(for: command) else { return nil }
        for stroke in plan.strokes {
            input.sendKey(stroke.keyCode, modifiers: stroke.modifiers)
        }
        return plan.resultingMode
    }
}
