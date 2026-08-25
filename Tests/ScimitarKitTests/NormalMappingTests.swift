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

    func testTopLevelWheelChordsUseHorizontalOnCellOneAndClipboardOnCellFour() {
        let chord = ScimitarNormalMapping.normal.assignment(for: 1)
        XCTAssertEqual(chord?.action, "Horizontal Scroll + Wheel")
        XCTAssertEqual(
            chord?.implementation,
            "Hold the exact-device cell; Agentic Mouse converts each ratchet into one native horizontal step"
        )

        let clipboard = ScimitarNormalMapping.normal.assignment(for: 4)
        XCTAssertEqual(clipboard?.action, "Copy / Paste + Wheel")
        XCTAssertEqual(
            clipboard?.implementation,
            "Hold the exact-device cell; Agentic Mouse sends Paste or Copy for each accepted ratchet"
        )
    }

    func testUtilityIsCellTwelveSwitchAppIsElevenAndLegendExitIsTen() {
        XCTAssertEqual(ScimitarNormalMapping.normal.assignment(for: 12)?.action, "Utility modes")
        XCTAssertEqual(ScimitarNormalMapping.normal.assignment(for: 11)?.action, "Switch App")
        XCTAssertEqual(ScimitarNormalMapping.normal.assignment(for: 10)?.action, "Legend toggle / mode exit")
        XCTAssertEqual(PhysicalCell.defaultMapToggle.printedSide(on: .corsair), 10)
        XCTAssertEqual(PhysicalCell.defaultMapToggle.printedSide(on: .razer), 12)
        XCTAssertEqual(PhysicalCell.switchApp.printedSide(on: .corsair), 11)
        XCTAssertEqual(PhysicalCell.switchApp.printedSide(on: .razer), 11)
    }

    func testForwardAndBackAreFiveAndEight() {
        XCTAssertEqual(ScimitarNormalMapping.normal.assignment(for: 5)?.action, "Forward")
        XCTAssertEqual(ScimitarNormalMapping.normal.assignment(for: 8)?.action, "Back")
    }

    func testSevenPressesEnterThreeTakesScreenshotsAndElevenSwitchesApps() {
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
        XCTAssertEqual(ScimitarNormalMapping.normal.assignment(for: 11)?.action, "Switch App")
        XCTAssertEqual(
            ScimitarNormalMapping.normal.assignment(for: 11)?.implementation,
            "Karabiner action: hold-open-app-switcher outside runtime modes"
        )
    }

    func testTwoOpensTheFrontmostAppSixScrubsYouTubeAndNineOpensKeys() {
        XCTAssertEqual(ScimitarNormalMapping.normal.assignment(for: 2)?.action, "App-specific mode")
        XCTAssertEqual(
            ScimitarNormalMapping.normal.assignment(for: 2)?.implementation,
            "Exact-device Karabiner opens the current frontmost app mode; active cell 10 exits"
        )
        XCTAssertEqual(ScimitarNormalMapping.normal.assignment(for: 6)?.action, "YouTube Scrub + Wheel")
        XCTAssertEqual(
            ScimitarNormalMapping.normal.assignment(for: 6)?.implementation,
            "Hold the exact-device cell; each accepted ratchet asks the VoiceInk YouTube Bridge to seek the selected target by exactly five seconds without focusing Chrome"
        )
        XCTAssertEqual(ScimitarNormalMapping.normal.assignment(for: 9)?.action, "Keys mode")
        XCTAssertEqual(
            ScimitarNormalMapping.normal.assignment(for: 9)?.implementation,
            "Exact-device Karabiner opens the shared native-key mode; active cell 10 exits"
        )
        XCTAssertEqual(PhysicalCell.youtubeBackFiveSeconds.printedSide(on: .corsair), 6)
        XCTAssertEqual(PhysicalCell.youtubeBackFiveSeconds.printedSide(on: .razer), 4)
        XCTAssertEqual(PhysicalCell.youtubeScrubWheelControl, PhysicalCell.youtubeBackFiveSeconds)
        XCTAssertEqual(PhysicalCell.intelligenceOnDemand.printedSide(on: .corsair), 8)
        XCTAssertEqual(PhysicalCell.intelligenceOnDemand.printedSide(on: .razer), 8)
        XCTAssertEqual(PhysicalCell.keysModeEntry.printedSide(on: .corsair), 9)
        XCTAssertEqual(PhysicalCell.keysModeEntry.printedSide(on: .razer), 7)
        XCTAssertEqual(VSCodeModeAction.stageAndNext.cell, PhysicalCell(rawValue: 9))
        XCTAssertEqual(VSCodeMode.cursorHistoryWheelCell, PhysicalCell(rawValue: 6))
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

    func testCellTwelveOwnsUtilityAndCellTenOwnsLegendOutsideModes() {
        for profile in ScimitarNormalMapping.allProfiles {
            let utility = profile.assignment(for: 12)
            XCTAssertEqual(utility?.action, "Utility modes")
            XCTAssertEqual(
                utility?.implementation,
                "One press opens Utility immediately"
            )
            let toggle = profile.assignment(for: 10)
            XCTAssertEqual(toggle?.action, "Legend toggle / mode exit")
            XCTAssertEqual(
                toggle?.implementation,
                "Toggles the persistent Default legend outside modes; universal Exit while a mode is active"
            )
        }
    }

    func testTheLegacyInputToggleRemainsTwelveAndRuntimeExitIsCellTen() {
        XCTAssertEqual(AppConfiguration.default.input.toggleKey, 10)
        XCTAssertEqual(MultiTapKeymap.modesKeypad.exitKey?.rawValue, 10)
        XCTAssertEqual(PhysicalCell.modePickerEntry.rawValue, 12)
        XCTAssertEqual(PhysicalCell.modeExit.rawValue, 10)
    }

    func testModesKeypadUsesTenForExitElevenForSpaceAndTwelveForBackspaceReturn() {
        XCTAssertEqual(MultiTapKeymap.modesKeypad[.k10]?.tapAction, .exitMode)
        XCTAssertEqual(MultiTapKeymap.modesKeypad[.k11]?.caption, "SPACE")
        XCTAssertEqual(MultiTapKeymap.modesKeypad[.k11]?.tapAction, .space)
        XCTAssertNil(MultiTapKeymap.modesKeypad[.k11]?.holdAction)
        XCTAssertEqual(MultiTapKeymap.modesKeypad[.k12]?.caption, "BACKSPACE")
        XCTAssertEqual(MultiTapKeymap.modesKeypad[.k12]?.tapAction, .backspace)
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
