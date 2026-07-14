import CoreGraphics
import XCTest
@testable import OmniVim

final class HintEngineTests: XCTestCase {
    func testSystemSettingsFixtureDecodes() throws {
#if SWIFT_PACKAGE
        let bundle = Bundle.module
#else
        let bundle = Bundle(for: HintEngineTests.self)
#endif
        let url = try XCTUnwrap(bundle.url(forResource: "system-settings-sidebar", withExtension: "json"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(AXApplicationSnapshot.self, from: Data(contentsOf: url))
        XCTAssertEqual(snapshot.bundleIdentifier, "com.apple.systempreferences")
        XCTAssertEqual(snapshot.nodes.count, 3)
        XCTAssertEqual(snapshot.nodes[1].title, "Wi-Fi")
    }

    func testCodesAreUniqueAndPrefixFree() {
        let codes = HintCodeGenerator().generate(count: 80)
        XCTAssertEqual(Set(codes).count, 80)
        for code in codes {
            XCTAssertFalse(codes.contains { $0 != code && $0.hasPrefix(code) }, "\(code) is a prefix")
        }
    }

    func testCodeGenerationIsDeterministic() {
        let generator = HintCodeGenerator()
        XCTAssertEqual(generator.generate(count: 50), generator.generate(count: 50))
    }

    func testVisibilityClipsToAllAncestors() {
        let input = HintVisibilityInput(
            frame: CGRect(x: 0, y: 0, width: 100, height: 100),
            ancestorClips: [CGRect(x: 10, y: 10, width: 80, height: 80), CGRect(x: 20, y: 20, width: 20, height: 20)],
            hitTestVisible: true
        )
        XCTAssertEqual(HintVisibilityEngine().visibleFrame(for: input), CGRect(x: 20, y: 20, width: 20, height: 20))
    }

    func testVisibilityRejectsFailedHitTest() {
        let input = HintVisibilityInput(
            frame: CGRect(x: 0, y: 0, width: 100, height: 100),
            ancestorClips: [],
            hitTestVisible: false
        )
        XCTAssertNil(HintVisibilityEngine().visibleFrame(for: input))
    }

    func testLayoutIsDeterministicAndSeparatesCollisions() {
        let preferred = Array(repeating: CGRect(x: 50, y: 50, width: 28, height: 24), count: 3)
        let engine = HintLayoutEngine()
        let first = engine.place(preferredFrames: preferred, within: CGRect(x: 0, y: 0, width: 300, height: 300))
        let second = engine.place(preferredFrames: preferred, within: CGRect(x: 0, y: 0, width: 300, height: 300))
        XCTAssertEqual(first, second)
        XCTAssertFalse(first[0].intersects(first[1]))
        XCTAssertFalse(first[1].intersects(first[2]))
    }

    func testDeduplicatorRemovesNestedSidebarCopies() {
        let items = [
            HintDeduplicator.Item(role: "AXRow", title: "General", frame: CGRect(x: 10, y: 10, width: 220, height: 44)),
            HintDeduplicator.Item(role: "AXButton", title: "General", frame: CGRect(x: 18, y: 14, width: 204, height: 36)),
            HintDeduplicator.Item(role: "AXRow", title: "Accessibility", frame: CGRect(x: 10, y: 60, width: 220, height: 44))
        ]

        let result = HintDeduplicator().deduplicate(items)

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.map(\.title), ["General", "Accessibility"])
        XCTAssertEqual(result.first?.role, "AXRow")
    }

}
