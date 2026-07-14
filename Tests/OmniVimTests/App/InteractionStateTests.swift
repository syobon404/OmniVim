import XCTest
@testable import OmniVim

final class InteractionStateTests: XCTestCase {
    func testHintStateRemembersInsertReturnMode() {
        let state = InteractionState.hint(returnTo: .insert)

        XCTAssertEqual(state.baseMode, .insert)
        XCTAssertEqual(state.label, "HINT")
    }

    func testBaseModeLabels() {
        XCTAssertEqual(InteractionState.normal.label, "NORMAL")
        XCTAssertEqual(InteractionState.insert.label, "INSERT")
    }
}
