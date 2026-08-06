import XCTest
@testable import ScimitarKit

/// Locks in the corrected side-button mapping.
///
/// These assertions exist because the mapping has been revised several times,
/// and prose in a README drifts silently while a failing test does not. iCUE
/// owns the real assignments; this is the helper's record of them, and the
/// place to correct when they change.
final class NormalMappingTests: XCTestCase {

    // MARK: - Normal profile

    func testSpeechToTextIsOnSideButtonFour() {
        let assignment = ScimitarNormalMapping.normal.assignment(for: 4)
        XCTAssertEqual(assignment?.action, "VoiceInk++ speech-to-text toggle")
        XCTAssertEqual(
            assignment?.implementation,
            "direct iCUE macro: LeftShift+LeftCtrl+LeftAlt press, then the reverse release sequence",
            "the working direct macro, not an F-key bridge or a Karabiner rule"
        )
    }

    func testForwardAndBackAreFiveAndEight() {
        XCTAssertEqual(ScimitarNormalMapping.normal.assignment(for: 5)?.action, "Forward")
        XCTAssertEqual(ScimitarNormalMapping.normal.assignment(for: 8)?.action, "Back")
    }

    func testHorizontalScrollIsTheSevenTenPair() {
        XCTAssertEqual(ScimitarNormalMapping.normal.assignment(for: 7)?.action, "Horizontal scroll left")
        XCTAssertEqual(ScimitarNormalMapping.normal.assignment(for: 10)?.action, "Horizontal scroll right")
    }

    func testTrackSkippingIsSixForwardAndNineBack() {
        XCTAssertEqual(ScimitarNormalMapping.normal.assignment(for: 6)?.action, "Next Track")
        XCTAssertEqual(
            ScimitarNormalMapping.normal.assignment(for: 9)?.action,
            "Previous Track",
            "9 rewinds; it is the mirror of 6"
        )
    }

    func testEveryDpiStageIsTheLogitechValue() {
        XCTAssertEqual(ScimitarNormalMapping.unifiedDPI, 2750)
    }

    func testTheDpiToggleButtonIsDisabledAndHasNoSpeechRole() throws {
        let entry = try XCTUnwrap(
            ScimitarNormalMapping.untouchedControls.first { $0.contains("DPI Toggle") },
            "the DPI Toggle button must be listed among the controls this helper never touches"
        )
        XCTAssertTrue(entry.contains("disabled"))
        XCTAssertTrue(
            entry.lowercased().contains("never trigger speech"),
            "the DPI button must not be the speech-to-text route"
        )
    }

    func testNoNormalAssignmentClaimsToBeAKarabinerOrFunctionKeyBridge() {
        for profile in ScimitarNormalMapping.allProfiles {
            for assignment in profile.assignments {
                let text = ((assignment.implementation ?? "") + assignment.action).lowercased()
                XCTAssertFalse(text.contains("karabiner"), "the Karabiner interception was removed")
                XCTAssertFalse(text.contains("f20"), "the F20 speech bridge no longer exists")
            }
        }
    }

    // MARK: - VS Code profile

    func testVsCodeProfileIsLinkedToTheApplication() {
        XCTAssertEqual(
            ScimitarNormalMapping.vsCode.linkedApplicationPath,
            "/Applications/Visual Studio Code.app"
        )
        XCTAssertEqual(ScimitarNormalMapping.vsCode.profileName, "VS Code")
    }

    func testVsCodeOverridesOnlySevenEightAndTen() {
        let normal = ScimitarNormalMapping.normal
        let vsCode = ScimitarNormalMapping.vsCode

        let overridden = vsCode.assignments.filter { assignment in
            normal.assignment(for: assignment.button)?.action != assignment.action
        }
        XCTAssertEqual(
            Set(overridden.map(\.button)),
            [7, 8, 10],
            "4, 5, 6, 9 and 12 must behave identically inside and outside VS Code"
        )
    }

    func testVsCodeBetterGitBindings() {
        let vsCode = ScimitarNormalMapping.vsCode

        // 8 goes "up" to the previous change, 7 goes "down" to the next one,
        // and 10 — right beside them — stages the file.
        XCTAssertEqual(vsCode.assignment(for: 7)?.action, "Better Git: next change")
        XCTAssertEqual(vsCode.assignment(for: 8)?.action, "Better Git: previous change")
        XCTAssertEqual(vsCode.assignment(for: 10)?.action, "Better Git: stage current file")

        XCTAssertEqual(
            vsCode.assignment(for: 7)?.implementation,
            "F13 → better-git-vscode.next-scm-change"
        )
        XCTAssertEqual(
            vsCode.assignment(for: 8)?.implementation,
            "F17 → better-git-vscode.previous-scm-change"
        )
        XCTAssertEqual(
            vsCode.assignment(for: 10)?.implementation,
            "F18 → better-git-vscode.stage-current-file"
        )
    }

    func testForwardIsNeverSpeciallyInterceptedAnywhere() {
        // The old "smart" Back/Forward source-control interception is gone.
        // Button 5 is plain Forward in every profile; the diff navigation lives
        // on 7 and 8 instead, where it does not shadow ordinary navigation.
        for profile in ScimitarNormalMapping.allProfiles {
            XCTAssertEqual(profile.assignment(for: 5)?.action, "Forward")
        }
    }

    // MARK: - Interaction with multi-tap

    func testTheMultiTapToggleDisplacesNoAppliedAction() {
        for profile in ScimitarNormalMapping.allProfiles {
            let toggle = profile.assignment(for: 12)
            XCTAssertEqual(toggle?.action, "Multi-tap mode toggle")
            XCTAssertEqual(
                toggle?.implementation,
                "no iCUE assignment; the helper listens for the raw CMKI_12 macro-key event",
                "button 12 was chosen precisely because it costs nothing"
            )
        }
    }

    func testTheToggleButtonMatchesTheDefaultConfiguration() {
        XCTAssertEqual(AppConfiguration.default.input.toggleKey, 12)
        XCTAssertEqual(MultiTapKeymap.classic.exitKey?.rawValue, 12)
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

    func testWheelAndMainClicksAreDocumentedAsUntouched() {
        let joined = ScimitarNormalMapping.untouchedControls.joined(separator: " ").lowercased()
        for expected in ["left click", "right click", "wheel", "pointer movement"] {
            XCTAssertTrue(joined.contains(expected), "\(expected) must be documented as never intercepted")
        }
    }

    // MARK: - Description

    func testDescribeIsStableAndMentionsEveryButton() {
        let text = ScimitarNormalMapping.normal.describe()
        for assignment in ScimitarNormalMapping.normal.assignments {
            XCTAssertTrue(text.contains(assignment.action), "describe() dropped button \(assignment.button)")
        }
        XCTAssertTrue(ScimitarNormalMapping.vsCode.describe().contains("/Applications/Visual Studio Code.app"))
    }

    func testDescribeSortsByButtonNumber() {
        let lines = ScimitarNormalMapping.vsCode.describe()
            .split(separator: "\n")
            .filter { $0.hasPrefix("  ") }
        let numbers = lines.compactMap { Int($0.trimmingCharacters(in: .whitespaces).prefix(2).trimmingCharacters(in: .whitespaces)) }
        XCTAssertEqual(numbers, numbers.sorted())
    }
}
