import XCTest
@testable import ScimitarKit

/// Locks in the corrected side-button mapping.
///
/// These assertions exist because the mapping has been revised several times,
/// and prose in a README drifts silently while a failing test does not. iCUE
/// owns neutral Corsair transports, Karabiner owns enabled semantics, and this
/// is the helper's readable record of the intended behavior.
final class NormalMappingTests: XCTestCase {

    // MARK: - Normal profile

    func testHorizontalScrollIsTheOneFourPair() {
        let left = ScimitarNormalMapping.normal.assignment(for: 1)
        XCTAssertEqual(left?.action, "Horizontal scroll left")
        XCTAssertEqual(
            left?.implementation,
            "Karabiner action: scroll-horizontally-left"
        )

        let right = ScimitarNormalMapping.normal.assignment(for: 4)
        XCTAssertEqual(right?.action, "Horizontal scroll right")
        XCTAssertEqual(
            right?.implementation,
            "Karabiner action: scroll-horizontally-right"
        )
    }

    func testSwitchAppIsOnSideButtonTwo() {
        let assignment = ScimitarNormalMapping.normal.assignment(for: 2)
        XCTAssertEqual(assignment?.action, "Switch App")
        XCTAssertEqual(assignment?.implementation, "Karabiner action: hold-open-app-switcher")
    }

    func testForwardAndBackAreFiveAndEight() {
        XCTAssertEqual(ScimitarNormalMapping.normal.assignment(for: 5)?.action, "Forward")
        XCTAssertEqual(ScimitarNormalMapping.normal.assignment(for: 8)?.action, "Back")
    }

    func testSevenPressesEnterThreeTakesScreenshotsAndTenShowsTheLegend() {
        XCTAssertEqual(ScimitarNormalMapping.normal.assignment(for: 7)?.action, "Enter")
        XCTAssertEqual(
            ScimitarNormalMapping.normal.assignment(for: 7)?.implementation,
            "Karabiner action: press-enter outside runtime modes"
        )
        XCTAssertEqual(
            ScimitarNormalMapping.normal.assignment(for: 3)?.action,
            "Screenshot"
        )
        XCTAssertEqual(
            ScimitarNormalMapping.normal.assignment(for: 3)?.implementation,
            "Agentic Mouse toggles the native selected-area screenshot session"
        )
        XCTAssertEqual(ScimitarNormalMapping.normal.assignment(for: 10)?.action, "Legend toggle")
        XCTAssertEqual(
            ScimitarNormalMapping.normal.assignment(for: 10)?.implementation,
            "Agentic Mouse persistent Default mode legend toggle; active modes use the same cell to exit"
        )
    }

    func testSixIsTheAppShortcutAndNineOpensKeysMode() {
        XCTAssertEqual(ScimitarNormalMapping.normal.assignment(for: 6)?.action, "App shortcut")
        XCTAssertEqual(
            ScimitarNormalMapping.normal.assignment(for: 6)?.implementation,
            "Karabiner suppresses the neutral transport by default; VS Code emits F18 Stage + Next"
        )
        XCTAssertEqual(ScimitarNormalMapping.normal.assignment(for: 9)?.action, "Keys mode")
        XCTAssertEqual(
            ScimitarNormalMapping.normal.assignment(for: 9)?.implementation,
            "Exact-device Karabiner opens the shared native arrow-key mode; active cell 10 exits"
        )
    }

    func testCellElevenOpensTheCurrentFrontmostAppModeDirectly() {
        let assignment = ScimitarNormalMapping.normal.assignment(for: 11)
        XCTAssertEqual(assignment?.action, "App-specific mode")
        XCTAssertEqual(
            assignment?.implementation,
            "Exact-device Karabiner opens the current frontmost app mode; active cell 10 exits"
        )
    }

    func testEveryDpiStageIsTheLogitechValue() {
        XCTAssertEqual(ScimitarNormalMapping.unifiedDPI, 2750)
    }

    func testTheDpiToggleButtonOwnsSpeechWithoutChangingDpi() throws {
        let entry = try XCTUnwrap(
            ScimitarNormalMapping.untouchedControls.first { $0.contains("DPI Toggle") },
            "the DPI Toggle button must be listed among the controls this helper never touches"
        )
        XCTAssertTrue(entry.contains("VoiceInk++ speech-to-text"))
        XCTAssertTrue(entry.contains("does not change DPI"))
    }

    func testNoSideGridAssignmentDuplicatesSpeechToText() {
        XCTAssertFalse(
            ScimitarNormalMapping.normal.assignments.contains {
                $0.action.lowercased().contains("speech")
            }
        )
    }

    // MARK: - Application scope

    func testOneBaseProfileAppliesToEveryApplication() {
        XCTAssertEqual(ScimitarNormalMapping.allProfiles, [.normal])
        XCTAssertNil(ScimitarNormalMapping.normal.linkedApplicationPath)
    }

    func testNormalProfileKeepsForwardAndBackAsItsBaseSemantics() {
        // Karabiner owns the narrow VS Code override; this helper records the
        // ordinary default-map semantics rather than a second app profile.
        for profile in ScimitarNormalMapping.allProfiles {
            XCTAssertEqual(profile.assignment(for: 5)?.action, "Forward")
            XCTAssertEqual(profile.assignment(for: 8)?.action, "Back")
        }
    }

    // MARK: - Interaction with Modes and Keypad

    func testCellTwelveOwnsTheUtilityModesEntry() {
        for profile in ScimitarNormalMapping.allProfiles {
            let toggle = profile.assignment(for: 12)
            XCTAssertEqual(toggle?.action, "Utility modes")
            XCTAssertEqual(
                toggle?.implementation,
                "Exact-device Karabiner opens the shared Agentic Mouse Modes lease; active cell 10 exits"
            )
        }
    }

    func testTheLegacyInputToggleRemainsTwelveAndRuntimeExitIsCellTen() {
        XCTAssertEqual(AppConfiguration.default.input.toggleKey, 10)
        XCTAssertEqual(MultiTapKeymap.modesKeypad.exitKey?.rawValue, 10)
        XCTAssertEqual(PhysicalCell.modePickerEntry.rawValue, 12)
        XCTAssertEqual(PhysicalCell.modeExit.rawValue, 10)
    }

    func testModesKeypadUsesTenForExitElevenForShiftAndTwelveForSpaceReturn() {
        XCTAssertEqual(MultiTapKeymap.modesKeypad[.k10]?.tapAction, .exitMode)
        XCTAssertEqual(MultiTapKeymap.modesKeypad[.k11]?.caption, "SHIFT")
        XCTAssertEqual(MultiTapKeymap.modesKeypad[.k11]?.tapAction, .shiftCycle)
        XCTAssertNil(MultiTapKeymap.modesKeypad[.k11]?.holdAction)
        XCTAssertEqual(MultiTapKeymap.modesKeypad[.k12]?.tapAction, .space)
        XCTAssertEqual(MultiTapKeymap.modesKeypad[.k12]?.holdAction, .newline)
    }

    func testEveryAssignedButtonIsInsideTheInterceptedGrid() {
        // If an assignment ever moved outside 1…12 it would keep firing during
        // multi-tap mode, because only the twelve macro keys are intercepted.
        let grid = Set(AppConfiguration.default.input.gridMacroKeys)
        for profile in ScimitarNormalMapping.allProfiles {
            for assignment in profile.assignments {
                XCTAssertTrue(
                    grid.contains(assignment.button),
                    "button \(assignment.button) in '\(profile.profileName)' is outside the intercepted grid"
                )
            }
        }
    }

    func testWheelAndMainClicksRemainOutsideMultiTapInterception() {
        let joined = ScimitarNormalMapping.untouchedControls.joined(separator: " ").lowercased()
        for expected in ["left click", "right click", "wheel", "pointer movement"] {
            XCTAssertTrue(joined.contains(expected), "\(expected) must be documented as never intercepted")
        }
        XCTAssertTrue(joined.contains("karabiner play/pause"))
    }

    // MARK: - Description

    func testDescribeIsStableAndMentionsEveryButton() {
        let text = ScimitarNormalMapping.normal.describe()
        for assignment in ScimitarNormalMapping.normal.assignments {
            XCTAssertTrue(text.contains(assignment.action), "describe() dropped button \(assignment.button)")
        }
        XCTAssertFalse(text.contains("Linked to:"))
    }

    func testDescribeSortsByButtonNumber() {
        let lines = ScimitarNormalMapping.normal.describe()
            .split(separator: "\n")
            .filter { $0.hasPrefix("  ") }
        let numbers = lines.compactMap { Int($0.trimmingCharacters(in: .whitespaces).prefix(2).trimmingCharacters(in: .whitespaces)) }
        XCTAssertEqual(numbers, numbers.sorted())
    }
}
