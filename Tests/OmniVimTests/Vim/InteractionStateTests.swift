import XCTest
import Carbon.HIToolbox
@testable import OmniVim

final class InteractionStateTests: XCTestCase {
    func testTerminalProgramClassifierSelectsShellPrompt() {
        XCTAssertEqual(TerminalProgramClassifier.classify(executable: "/opt/homebrew/bin/fish"), .shellPrompt)
        XCTAssertEqual(TerminalProgramClassifier.normalizedExecutableName("-fish"), "fish")
        XCTAssertEqual(TerminalProgramClassifier.classify(executable: "zsh"), .passThrough)
    }

    func testTerminalProgramClassifierSelectsAgyAdapter() {
        XCTAssertEqual(
            TerminalProgramClassifier.classify(executable: "/Users/test/.local/bin/agy"),
            .adaptedTUI(.readlineTUI)
        )
    }

    func testTerminalProgramClassifierBypassesNativeModalPrograms() {
        for executable in ["nvim", "vim", "vi", "hx", "kakoune"] {
            XCTAssertEqual(TerminalProgramClassifier.classify(executable: executable), .nativeModal)
        }
    }

    func testTerminalProgramClassifierPassesThroughUnknownAndRemotePrograms() {
        XCTAssertEqual(TerminalProgramClassifier.classify(executable: "ssh"), .passThrough)
        XCTAssertEqual(TerminalProgramClassifier.classify(executable: "lazygit"), .passThrough)
    }

    func testKittySnapshotParserFindsFocusedForegroundProgram() throws {
        let snapshot = """
        [{
          "id": 10,
          "tabs": [{
            "id": 20,
            "windows": [{
              "id": 30,
              "foreground_processes": [{
                "pid": 4242,
                "cmdline": ["/Users/test/.local/bin/agy", "--continue"]
              }]
            }]
          }]
        }]
        """

        let context = try KittySessionSnapshotParser.parse(
            data: Data(snapshot.utf8),
            terminalProcessIdentifier: 100
        )

        XCTAssertEqual(context?.identity, TerminalSessionIdentity(
            terminalProcessIdentifier: 100,
            windowIdentifier: "30",
            foregroundProcessIdentifier: 4242
        ))
        XCTAssertEqual(context?.executableName, "agy")
        XCTAssertEqual(context?.behavior, .adaptedTUI(.readlineTUI))
    }

    func testReadlineTUIWordDeleteUsesEmacsBinding() {
        XCTAssertEqual(
            ReadlineTUIExecutionPlan.make(for: .operate(.delete, .wordBackward)),
            ReadlineTUIExecutionPlan(
                strokes: [SyntheticKeyStroke(kVK_ANSI_W, modifiers: [.control])],
                resultingMode: .normal
            )
        )
    }

    func testReadlineTUIWholeLineChangeClearsBothSidesAndEntersInsert() {
        XCTAssertEqual(
            ReadlineTUIExecutionPlan.make(for: .operate(.change, .wholeLine)),
            ReadlineTUIExecutionPlan(
                strokes: [
                    SyntheticKeyStroke(kVK_ANSI_U, modifiers: [.control]),
                    SyntheticKeyStroke(kVK_ANSI_K, modifiers: [.control])
                ],
                resultingMode: .insert
            )
        )
    }

    func testTerminalApplicationPolicyRecognizesKitty() {
        XCTAssertTrue(TerminalApplicationPolicy.isTerminal(bundleIdentifier: "net.kovidgoyal.kitty"))
        XCTAssertFalse(TerminalApplicationPolicy.isTerminal(bundleIdentifier: "com.apple.Notes"))
        XCTAssertFalse(TerminalApplicationPolicy.isTerminal(bundleIdentifier: nil))
    }

    func testTerminalPlanUsesNativeFishWordDeletion() {
        XCTAssertEqual(
            TerminalVimExecutionPlan.make(for: .operate(.delete, .wordForward)),
            TerminalVimExecutionPlan(bridgeCommand: "delete-word-forward", resultingMode: .normal)
        )
    }

    func testTerminalChangeReturnsToInsertMode() {
        XCTAssertEqual(
            TerminalVimExecutionPlan.make(for: .operate(.change, .wholeLine)),
            TerminalVimExecutionPlan(bridgeCommand: "delete-whole-line", resultingMode: .insert)
        )
    }

    func testTerminalCrossLineOperatorsAreExplicitlyUnsupported() {
        XCTAssertNil(TerminalVimExecutionPlan.make(for: .operate(.delete, .lineDown)))
        XCTAssertNil(TerminalVimExecutionPlan.make(for: .operate(.change, .lineUp)))
    }

    func testHintStateRemembersInsertReturnMode() {
        let state = InteractionState.hint(returnTo: .insert)

        XCTAssertEqual(state.baseMode, .insert)
        XCTAssertEqual(state.label, "HINT")
    }

    func testBaseModeLabels() {
        XCTAssertEqual(InteractionState.inactive.label, "INACTIVE")
        XCTAssertEqual(InteractionState.normal.label, "NORMAL")
        XCTAssertEqual(InteractionState.insert.label, "INSERT")
    }

    func testInactiveHintReturnHasNoBaseMode() {
        XCTAssertNil(InteractionState.inactive.baseMode)
        XCTAssertNil(InteractionState.hint(returnTo: nil).baseMode)
    }

    func testDefaultModeStartsInInsert() {
        XCTAssertEqual(ModeConfiguration().initialMode, .insert)
    }

    func testOnlyHintConsumesPhysicalEscape() {
        XCTAssertFalse(InteractionState.insert.consumesEscape)
        XCTAssertFalse(InteractionState.normal.consumesEscape)
        XCTAssertFalse(InteractionState.inactive.consumesEscape)
        XCTAssertTrue(InteractionState.hint(returnTo: .insert).consumesEscape)
    }

    func testOrderedChordTriggersWhileFirstKeyIsHeld() {
        var chord = makeChord()

        XCTAssertEqual(chord.handle(key(kVK_ANSI_J, phase: .down), enabled: true), .consume)
        XCTAssertEqual(chord.handle(key(kVK_ANSI_K, phase: .down), enabled: true), .trigger)
        XCTAssertEqual(chord.handle(key(kVK_ANSI_K, phase: .up), enabled: false), .consume)
        XCTAssertEqual(chord.handle(key(kVK_ANSI_J, phase: .up), enabled: false), .consume)
    }

    func testOrderedChordReplaysJWhenReleasedBeforeK() {
        var chord = makeChord()

        XCTAssertEqual(chord.handle(key(kVK_ANSI_J, phase: .down), enabled: true), .consume)
        XCTAssertEqual(chord.handle(key(kVK_ANSI_J, phase: .up), enabled: true), .replayFirst)
        XCTAssertEqual(chord.handle(key(kVK_ANSI_K, phase: .down), enabled: true), .passThrough)
    }

    func testOrderedChordReplaysJBeforeAnotherPressedKey() {
        var chord = makeChord()

        XCTAssertEqual(chord.handle(key(kVK_ANSI_J, phase: .down), enabled: true), .consume)
        XCTAssertEqual(chord.handle(key(kVK_ANSI_A, phase: .down), enabled: true), .replayFirstAndCurrent)
    }

    func testOrderedChordIgnoresModifiedOrRepeatedJ() {
        var chord = makeChord()
        let commandJ = KeyPress(
            keyCode: CGKeyCode(kVK_ANSI_J),
            character: "j",
            flags: .maskCommand
        )
        let repeatedJ = KeyPress(
            keyCode: CGKeyCode(kVK_ANSI_J),
            character: "j",
            flags: [],
            isRepeat: true
        )

        XCTAssertEqual(chord.handle(commandJ, enabled: true), .passThrough)
        XCTAssertEqual(chord.handle(repeatedJ, enabled: true), .passThrough)
    }

    func testOrderedChordKeysCanBeCustomized() {
        var chord = OrderedKeyChord(definition: OrderedKeyChordDefinition(
            first: CGKeyCode(kVK_ANSI_S),
            second: CGKeyCode(kVK_ANSI_D)
        ))

        XCTAssertEqual(chord.handle(key(kVK_ANSI_J, phase: .down), enabled: true), .passThrough)
        XCTAssertEqual(chord.handle(key(kVK_ANSI_S, phase: .down), enabled: true), .consume)
        XCTAssertEqual(chord.handle(key(kVK_ANSI_D, phase: .down), enabled: true), .trigger)
    }

    func testModeIndicatorFitsInsideLargeEditor() {
        let frame = ModeIndicatorLayout.frame(
            anchorFrame: CGRect(x: 100, y: 100, width: 500, height: 300),
            indicatorSize: CGSize(width: 104, height: 26),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_000, height: 800)
        )

        XCTAssertEqual(frame.origin, CGPoint(x: 488, y: 108))
    }

    func testModeIndicatorSitsBelowCompactField() {
        let frame = ModeIndicatorLayout.frame(
            anchorFrame: CGRect(x: 200, y: 300, width: 320, height: 32),
            indicatorSize: CGSize(width: 104, height: 26),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_000, height: 800)
        )

        XCTAssertEqual(frame.origin, CGPoint(x: 416, y: 268))
    }

    func testModeIndicatorFlipsAboveFieldNearScreenBottom() {
        let frame = ModeIndicatorLayout.frame(
            anchorFrame: CGRect(x: 20, y: 8, width: 180, height: 32),
            indicatorSize: CGSize(width: 104, height: 26),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_000, height: 800)
        )

        XCTAssertEqual(frame.origin, CGPoint(x: 96, y: 46))
    }

    func testInsertIndicatorAutoHidesForRegularApps() {
        XCTAssertTrue(ModeIndicatorPresentationPolicy.shouldAutoHideInsert(
            state: .insert,
            persistentInsert: false
        ))
    }

    func testInsertIndicatorPersistsForFloatingApps() {
        XCTAssertFalse(ModeIndicatorPresentationPolicy.shouldAutoHideInsert(
            state: .insert,
            persistentInsert: true
        ))
    }

    func testNormalIndicatorNeverAutoHides() {
        XCTAssertFalse(ModeIndicatorPresentationPolicy.shouldAutoHideInsert(
            state: .normal,
            persistentInsert: false
        ))
    }

    func testDeleteWaitsForMotionThenExecutesWordForward() {
        var engine = VimEngine()

        XCTAssertEqual(engine.handle(character: "d"), .pending(.delete))
        XCTAssertEqual(engine.pendingOperator, .delete)
        XCTAssertEqual(
            engine.handle(character: "w"),
            .execute(.operate(.delete, .wordForward))
        )
        XCTAssertNil(engine.pendingOperator)
    }

    func testRepeatedOperatorTargetsWholeLine() {
        var engine = VimEngine()

        XCTAssertEqual(engine.handle(character: "c"), .pending(.change))
        XCTAssertEqual(
            engine.handle(character: "c"),
            .execute(.operate(.change, .wholeLine))
        )
    }

    func testInvalidOperatorMotionCancelsPendingCommand() {
        var engine = VimEngine()

        XCTAssertEqual(engine.handle(character: "d"), .pending(.delete))
        XCTAssertEqual(engine.handle(character: "q"), .consume)
        XCTAssertNil(engine.pendingOperator)
    }

    func testPendingOperatorCanBeCancelled() {
        var engine = VimEngine()

        _ = engine.handle(character: "d")
        XCTAssertTrue(engine.cancelPending())
        XCTAssertFalse(engine.cancelPending())
    }

    func testDeleteWordFallbackSelectsThenDeletes() {
        let plan = SyntheticVimExecutionPlan.make(
            for: .operate(.delete, .wordForward)
        )

        XCTAssertEqual(plan?.resultingMode, .normal)
        XCTAssertEqual(plan?.strokes, [
            SyntheticKeyStroke(kVK_RightArrow, modifiers: [.option, .shift]),
            SyntheticKeyStroke(kVK_Delete)
        ])
    }

    func testChangeToLineEndFallbackEntersInsert() {
        let plan = SyntheticVimExecutionPlan.make(
            for: .operate(.change, .lineEnd)
        )

        XCTAssertEqual(plan?.resultingMode, .insert)
        XCTAssertEqual(plan?.strokes, [
            SyntheticKeyStroke(kVK_RightArrow, modifiers: [.command, .shift]),
            SyntheticKeyStroke(kVK_Delete)
        ])
    }

    func testDeleteWholeLineFallbackIncludesNewline() {
        let plan = SyntheticVimExecutionPlan.make(
            for: .operate(.delete, .wholeLine)
        )

        XCTAssertEqual(plan?.strokes, [
            SyntheticKeyStroke(kVK_LeftArrow, modifiers: [.command]),
            SyntheticKeyStroke(kVK_RightArrow, modifiers: [.command, .shift]),
            SyntheticKeyStroke(kVK_RightArrow, modifiers: [.shift]),
            SyntheticKeyStroke(kVK_Delete)
        ])
    }

    func testZeroUsesRealLineStartFallback() {
        let plan = SyntheticVimExecutionPlan.make(for: .move(.lineStart))

        XCTAssertEqual(plan?.strokes, [
            SyntheticKeyStroke(kVK_LeftArrow, modifiers: [.command])
        ])
    }

    private func makeChord() -> OrderedKeyChord {
        OrderedKeyChord(definition: OrderedKeyChordDefinition(
            first: CGKeyCode(kVK_ANSI_J),
            second: CGKeyCode(kVK_ANSI_K)
        ))
    }

    private func key(_ code: Int, phase: KeyEventPhase) -> KeyPress {
        KeyPress(
            keyCode: CGKeyCode(code),
            character: nil,
            flags: [],
            phase: phase
        )
    }
}
