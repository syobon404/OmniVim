import XCTest
@testable import OmniVim

final class ElementActivatorStrategyTests: XCTestCase {
    func testAXPressWinsGloballyOverEarlierShowMenuCandidate() throws {
        let selection = try XCTUnwrap(preferredAXActionCandidate([
            ["AXShowMenu", "AXScrollToVisible"],
            ["AXPress"]
        ]))

        XCTAssertEqual(selection.candidateIndex, 1)
        XCTAssertEqual(selection.action, "AXPress")
    }

    func testOriginalCandidateWinsWhenMultipleCandidatesSupportPress() throws {
        let selection = try XCTUnwrap(preferredAXActionCandidate([
            ["AXPress"],
            ["AXPress", "AXShowMenu"]
        ]))

        XCTAssertEqual(selection.candidateIndex, 0)
        XCTAssertEqual(selection.action, "AXPress")
    }

    func testRowsAndCellsUseSelectionInsteadOfPressAction() {
        XCTAssertTrue(shouldSelectAXElement(role: "AXRow"))
        XCTAssertTrue(shouldSelectAXElement(role: "AXCell"))
        XCTAssertFalse(shouldSelectAXElement(role: "AXButton"))
    }
}
