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

    func testLayoutSeparatesDenseDetectionCluster() {
        let preferred = Array(
            repeating: CGRect(x: 150, y: 150, width: 24, height: 20),
            count: 24
        )

        let placed = HintLayoutEngine().place(
            preferredFrames: preferred,
            within: CGRect(x: 0, y: 0, width: 600, height: 600)
        )

        for index in placed.indices {
            for otherIndex in placed.indices where otherIndex > index {
                XCTAssertFalse(
                    placed[index].insetBy(dx: -2, dy: -2).intersects(placed[otherIndex]),
                    "badges \(index) and \(otherIndex) overlap"
                )
            }
        }
    }

    func testAdaptiveGlassChangesAppearanceIndependentlyFromPlacement() {
        XCTAssertEqual(
            HintOverlayAppearance.adaptiveGlass.displayName,
            "Adaptive: Glass → Keycap"
        )
        XCTAssertEqual(
            HintOverlayAppearance.adaptiveGlass.resolved(isNarrowed: false),
            .liquidGlass
        )
        XCTAssertEqual(
            HintOverlayAppearance.adaptiveGlass.resolved(isNarrowed: true),
            .keycap
        )
        XCTAssertEqual(
            HintOverlayAppearance.liquidGlass.resolved(isNarrowed: false),
            .liquidGlass
        )
        XCTAssertEqual(
            HintOverlayAppearance.liquidGlass.resolved(isNarrowed: true),
            .liquidGlass
        )
        XCTAssertEqual(HintOverlayPlacement.topLeft.displayName, "Inside Top Left")
    }

    @MainActor
    func testFixedLiquidMarkerDoesNotReceiveKeycapPrefixTreatment() {
        let hint = UIElementHint(
            element: AXUIElementCreateApplication(getpid()),
            processIdentifier: getpid(),
            role: "AXButton",
            subrole: "",
            title: "Test",
            frame: CGRect(x: 0, y: 0, width: 100, height: 40)
        )
        let marker = HintMarkerView(
            code: "sa",
            hint: hint,
            appearance: .liquidGlass,
            palette: .amber,
            action: { _ in }
        )

        marker.update(matchingPrefixLength: 1, appearance: .liquidGlass, palette: .mint)

        XCTAssertEqual(marker.renderedAppearance, .liquidGlass)
        XCTAssertEqual(marker.renderedPalette, .mint)
        XCTAssertEqual(marker.layer?.borderWidth, 1)
        XCTAssertEqual(marker.layer?.shadowOpacity, 0.45)

        marker.update(matchingPrefixLength: 1, appearance: .keycap, palette: .violet)

        XCTAssertEqual(marker.renderedAppearance, .keycap)
        XCTAssertEqual(marker.renderedPalette, .violet)
        XCTAssertEqual(marker.layer?.borderWidth, 1.5)
        XCTAssertEqual(marker.layer?.shadowOpacity, 0.7)
    }

    @MainActor
    func testTargetGuideUsesResolvedAppearance() {
        let guide = HintDetectionOutlineView()

        guide.setEmphasized(true, appearance: .liquidGlass, palette: .mint)
        XCTAssertEqual(guide.renderedAppearance, .liquidGlass)
        XCTAssertEqual(guide.renderedPalette, .mint)

        guide.setEmphasized(true, appearance: .keycap, palette: .violet)
        XCTAssertEqual(guide.renderedAppearance, .keycap)
        XCTAssertEqual(guide.renderedPalette, .violet)
    }

    @MainActor
    func testHintOverlayPreferencesDefaultAndPersist() throws {
        let suiteName = "HintOverlayPreferencesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = HintOverlayPreferenceStore(defaults: defaults)
        XCTAssertEqual(first.appearance, .adaptiveGlass)
        XCTAssertEqual(first.palette, .amber)
        XCTAssertEqual(first.placement, .topLeft)
        XCTAssertTrue(first.showsTargetGuides)

        first.appearance = .keycap
        first.palette = .mint
        first.placement = .sideRight
        first.showsTargetGuides = false

        let second = HintOverlayPreferenceStore(defaults: defaults)
        XCTAssertEqual(second.appearance, .keycap)
        XCTAssertEqual(second.palette, .mint)
        XCTAssertEqual(second.placement, .sideRight)
        XCTAssertFalse(second.showsTargetGuides)
    }

    @MainActor
    func testHintOverlayPreferencesMigrateCombinedLegacyStyles() throws {
        let cases: [(String, HintOverlayAppearance, HintColorPalette, HintOverlayPlacement)] = [
            ("adaptiveGlass", .adaptiveGlass, .amber, .dockedEdge),
            ("liquidGlass", .liquidGlass, .amber, .aboveCenter),
            ("precisionKeycap", .keycap, .amber, .topRight),
            ("edgeTab", .keycap, .mint, .sideRight),
            ("chromaticCorner", .keycap, .violet, .bottomRight),
            ("vimiumKeycap", .keycap, .amber, .topLeft),
        ]

        for (legacyStyle, expectedAppearance, expectedPalette, expectedPlacement) in cases {
            let suiteName = "HintOverlayMigrationTests.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
            defer { defaults.removePersistentDomain(forName: suiteName) }
            defaults.set(legacyStyle, forKey: "HintOverlayStyle")

            let store = HintOverlayPreferenceStore(defaults: defaults)

            XCTAssertEqual(store.appearance, expectedAppearance)
            XCTAssertEqual(store.palette, expectedPalette)
            XCTAssertEqual(store.placement, expectedPlacement)
            XCTAssertNil(defaults.object(forKey: "HintOverlayStyle"))
        }
    }

    @MainActor
    func testHintOverlayPreferencesMigrateColorNamedAppearancesToPalettes() throws {
        let cases: [(String, HintColorPalette)] = [
            ("precisionKeycap", .amber),
            ("edgeTab", .mint),
            ("chromaticCorner", .violet),
        ]

        for (legacyAppearance, expectedPalette) in cases {
            let suiteName = "HintOverlayPaletteMigrationTests.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
            defer { defaults.removePersistentDomain(forName: suiteName) }
            defaults.set(legacyAppearance, forKey: "HintOverlayAppearance")

            let store = HintOverlayPreferenceStore(defaults: defaults)

            XCTAssertEqual(store.appearance, .keycap)
            XCTAssertEqual(store.palette, expectedPalette)
        }
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

    func testGPASuppressionKeepsHighestConfidenceOverlappingBox() {
        let detections = [
            GPAGUIElementDetection(
                normalizedFrame: CGRect(x: 0.10, y: 0.10, width: 0.20, height: 0.10),
                confidence: 0.72,
                identifier: "button"
            ),
            GPAGUIElementDetection(
                normalizedFrame: CGRect(x: 0.11, y: 0.10, width: 0.20, height: 0.10),
                confidence: 0.91,
                identifier: "icon"
            ),
            GPAGUIElementDetection(
                normalizedFrame: CGRect(x: 0.60, y: 0.60, width: 0.10, height: 0.10),
                confidence: 0.64,
                identifier: "button"
            ),
        ]

        let result = GPADetectionSuppressor().suppress(detections)

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.map(\.confidence), [0.91, 0.64])
    }

    func testGPASuppressionRemovesNearContainedDuplicateButKeepsNestedControl() {
        let detections = [
            GPAGUIElementDetection(
                normalizedFrame: CGRect(x: 0.10, y: 0.10, width: 0.20, height: 0.20),
                confidence: 0.90,
                identifier: "button"
            ),
            GPAGUIElementDetection(
                normalizedFrame: CGRect(x: 0.11, y: 0.11, width: 0.18, height: 0.18),
                confidence: 0.80,
                identifier: "button"
            ),
            GPAGUIElementDetection(
                normalizedFrame: CGRect(x: 0.15, y: 0.15, width: 0.04, height: 0.04),
                confidence: 0.70,
                identifier: "checkbox"
            ),
        ]

        let result = GPADetectionSuppressor().suppress(detections)

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.map(\.confidence), [0.90, 0.70])
    }

}
