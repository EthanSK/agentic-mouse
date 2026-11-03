import XCTest
@testable import ScimitarKit

final class VSCodeHoldTests: XCTestCase {
    func testDefaultInitializationIsOncePerHoldEvenAfterIntentionalModeOff() throws {
        for source in MouseSource.allCases {
            let state = VSCodeStagePreviewModifierState()
            XCTAssertTrue(state.activateDefaultForReadyStage(source: source, appSpecificModeActive: false))
            XCTAssertFalse(state.activateDefaultForReadyStage(source: source, appSpecificModeActive: false))
            XCTAssertEqual(state.handle(.init(source: source), whileStageRangeActive: true), false)
            XCTAssertFalse(state.activateDefaultForReadyStage(source: source, appSpecificModeActive: false))
            XCTAssertFalse(state.isActive(for: source))
            XCTAssertFalse(state.clear(source: source, reason: .ownerRelease))
            XCTAssertTrue(state.activateDefaultForReadyStage(source: source, appSpecificModeActive: false))
            state.clearAll()
            XCTAssertFalse(state.activateDefaultForReadyStage(source: source, appSpecificModeActive: true))
            XCTAssertTrue(state.activateDefaultForReadyStage(source: source, appSpecificModeActive: false))
        }
    }

    func testAtomicInitialPreviewMetadataCannotEnterAnotherWheelControlOrRelease() throws {
        for control in [WheelChordControl.clipboard, .vsCodeStageRange] {
            for phase in [ModePickerCommand.Phase.press, .release] {
                let command = WheelChordCommand(control: control, source: .corsair, phase: phase, initialPreview: true)
                let data = try JSONEncoder().encode(command)
                if control == .vsCodeStageRange && phase == .press {
                    XCTAssertEqual(try WheelChordCommand.decodeTopLevel(data), command)
                } else { XCTAssertThrowsError(try WheelChordCommand.decodeTopLevel(data)) }
            }
        }
    }

    func testEyesOwnerReleaseDefersRemoteCleanupButCancellationStillSendsOff() {
        for source in MouseSource.allCases {
            let state = VSCodeStagePreviewModifierState()
            let other: MouseSource = source == .corsair ? .razer : .corsair
            state.setActive(true, for: source)
            state.setActive(true, for: other)
            XCTAssertFalse(state.clear(source: source, reason: .ownerRelease))
            XCTAssertFalse(state.isActive(for: source))
            XCTAssertTrue(state.isActive(for: other), "Release is source-owned")
            XCTAssertFalse(state.clear(source: source, reason: .ownerRelease), "Duplicate release is inert")
            XCTAssertTrue(state.clear(source: other), "Focus loss, cancellation and replacement still send mode-off")
            XCTAssertFalse(state.clear(source: other), "Cancellation sends off once")

            state.setActive(true, for: source)
            XCTAssertEqual(state.handle(.init(source: source), whileStageRangeActive: true), false,
                           "An intentional adjacent tap still sends mode-off")
            XCTAssertFalse(state.clear(source: source, reason: .ownerRelease))
        }
    }

    func testDefaultPreviewCommandRequiresItsOwnNamespaceAndSource() throws {
        let command = VSCodeStagePreviewCommand(source: .razer, direction: .previous)
        XCTAssertEqual(try VSCodeStagePreviewCommand.decode(JSONEncoder().encode(command)), command)
        XCTAssertThrowsError(try VSCodeStagePreviewCommand.decode(
            Data(#"{"command":"other","source":"razer","direction":"previous"}"#.utf8)
        ))
    }
    func testDefaultPreviewStartsActiveAndAdjacentTogglesPerSource() throws {
        let state = VSCodeStagePreviewModifierState()
        let corsairToggle = VSCodeStagePreviewModifierCommand(source: .corsair)
        let razerToggle = VSCodeStagePreviewModifierCommand(source: .razer)
        XCTAssertEqual(
            try VSCodeStagePreviewModifierCommand.decode(JSONEncoder().encode(corsairToggle)),
            corsairToggle
        )
        XCTAssertThrowsError(try VSCodeStagePreviewModifierCommand.decode(
            Data(#"{"command":"other","source":"corsair","event":"toggle"}"#.utf8)
        ))

        XCTAssertTrue(state.setActive(true, for: .corsair), "A ready stage hold starts in Eyes mode")
        XCTAssertTrue(state.isActive(for: .corsair))
        XCTAssertTrue(state.setActive(true, for: .razer), "Each source owns its Eyes state")
        XCTAssertTrue(state.isActive(for: .razer))

        // Releasing the adjacent physical button sends no toggle command.
        XCTAssertTrue(state.isActive(for: .corsair))
        XCTAssertEqual(state.handle(corsairToggle, whileStageRangeActive: true), false)
        XCTAssertFalse(state.isActive(for: .corsair))
        XCTAssertTrue(state.isActive(for: .razer))

        XCTAssertEqual(state.handle(razerToggle, whileStageRangeActive: true), false)
        XCTAssertFalse(state.isActive(for: .razer))
        XCTAssertNil(state.handle(corsairToggle, whileStageRangeActive: false))
        XCTAssertFalse(state.isActive(for: .corsair), "A pre-ready tap must not override default Eyes")

        XCTAssertTrue(state.setActive(true, for: .corsair))
        XCTAssertTrue(state.isActive(for: .corsair))
        state.clear(source: .corsair)
        XCTAssertFalse(state.isActive(for: .corsair))
        XCTAssertFalse(state.isActive(for: .razer))
        state.clearAll()
        XCTAssertFalse(state.isActive(for: .razer))

        XCTAssertNil(state.handle(corsairToggle, whileStageRangeActive: false))
        XCTAssertFalse(state.isActive(for: .corsair))
        XCTAssertTrue(state.setActive(true, for: .corsair))
        XCTAssertTrue(state.isActive(for: .corsair))
    }
    func testAdjacentPreviewIsMomentaryAndKeepsStageHoldAndWheelSelection() {
        for (action, partner, direction) in [
            (VSCodeModeAction.nextChange, 9, VSCodeStagePreviewDirection.next),
            (.previousChange, 6, .previous),
        ] {
            let scheduler = ManualTickScheduler()
            let subject = VSCodeModeGestureClassifier(clock: ManualClock(), scheduler: scheduler)
            var commands: [VSCodeModeCommand] = []
            let cell = PhysicalCell(rawValue: partner)!
            subject.handleNavigation(action: action, phase: .press, inputTime: 0) { commands.append($0) }
            let early = subject.handleAdjacentPreviewChord(cell: cell, phase: .press)
            XCTAssertTrue(early.handled)
            XCTAssertNil(early.direction)
            XCTAssertFalse(subject.isStageRangeNavigationActive)
            XCTAssertTrue(subject.handleAdjacentPreviewChord(cell: cell, phase: .release).handled)
            scheduler.fire()
            XCTAssertFalse(subject.isStageRangeNavigationActive) // Early press ended with its release.
            let first = subject.handleAdjacentPreviewChord(cell: cell, phase: .press)
            XCTAssertTrue(first.handled)
            XCTAssertEqual(first.direction, direction)
            XCTAssertTrue(subject.isStageRangeNavigationActive)
            XCTAssertNil(subject.handleAdjacentPreviewChord(cell: cell, phase: .press).direction)
            XCTAssertTrue(subject.isStageRangeNavigationActive)
            XCTAssertTrue(subject.handleAdjacentPreviewChord(cell: cell, phase: .release).handled)
            XCTAssertFalse(subject.isStageRangeNavigationActive)
            XCTAssertFalse(subject.handleAdjacentPreviewChord(cell: cell, phase: .release).handled)
            let second = subject.handleAdjacentPreviewChord(cell: cell, phase: .press)
            XCTAssertEqual(second.direction, direction)
            XCTAssertTrue(subject.isStageRangeNavigationActive)
            XCTAssertTrue(subject.handleAdjacentPreviewChord(cell: cell, phase: .release).handled)
            XCTAssertFalse(subject.isStageRangeNavigationActive)
            subject.handleNavigation(action: action, phase: .release, inputTime: 0.5) { commands.append($0) }
            XCTAssertEqual(commands, [
                action == .nextChange ? .beginNextChangeHold : .beginPreviousChangeHold,
                action == .nextChange ? .finishNextChangeHold : .finishPreviousChangeHold,
            ])
        }
    }

    func testButtonDownCapturesOriginAndShortReleaseNavigatesOnce() {
        for action in [VSCodeModeAction.nextChange, .previousChange] {
            let clock = ManualClock()
            let scheduler = ManualTickScheduler()
            let subject = VSCodeModeGestureClassifier(clock: clock, scheduler: scheduler)
            var commands: [VSCodeModeCommand] = []
            subject.handleNavigation(action: action, phase: .press, inputTime: 0) { commands.append($0) }
            XCTAssertEqual(commands, [action == .nextChange ? .beginNextChangeHold : .beginPreviousChangeHold])
            XCTAssertTrue(scheduler.isRunning)
            clock.advance(by: 4) // Delayed main-thread handling must not count as time spent physically holding.
            subject.handleNavigation(action: action, phase: .release, inputTime: 0.06) { commands.append($0) }
            XCTAssertEqual(commands, [action == .nextChange ? .beginNextChangeHold : .beginPreviousChangeHold, .cancelNavigationHold])
            XCTAssertFalse(scheduler.isRunning)
        }
    }

    func testEveryLongReleaseStagesEvenWhenHoldsAreConsecutive() {
        for action in [VSCodeModeAction.nextChange, .previousChange] {
            let subject = VSCodeModeGestureClassifier(clock: ManualClock(), scheduler: ManualTickScheduler())
            var commands: [VSCodeModeCommand] = []
            for index in 0..<4 {
                let start = Double(index)
                subject.handleNavigation(action: action, phase: .press, inputTime: start) { commands.append($0) }
                subject.handleNavigation(action: action, phase: .press, inputTime: start + 0.2) { commands.append($0) }
                XCTAssertEqual(commands.count, index * 2 + 1)
                subject.handleNavigation(action: action, phase: .release, inputTime: start + 0.6) { commands.append($0) }
                subject.handleNavigation(action: action, phase: .release, inputTime: start + 0.7) { commands.append($0) }
            }
            XCTAssertEqual(commands, (0..<4).flatMap { _ in [action == .nextChange ? .beginNextChangeHold : .beginPreviousChangeHold, action == .nextChange ? .finishNextChangeHold : .finishPreviousChangeHold] })
        }
    }

    func testUndoChordConsumesShortAndAlreadyLongHoldsWithoutExtraStage() {
        for action in [VSCodeModeAction.nextChange, .previousChange] {
            for duration in [0.08, 2.0] {
                let subject = VSCodeModeGestureClassifier(clock: ManualClock(), scheduler: ManualTickScheduler())
                var commands: [VSCodeModeCommand] = []
                let partner = PhysicalCell(rawValue: action == .nextChange ? 7 : 4)!
                subject.handleNavigation(action: action, phase: .press, inputTime: 0) { commands.append($0) }
                XCTAssertTrue(subject.handleUndoChord(cell: partner) { commands.append($0) })
                XCTAssertTrue(subject.handleUndoChord(cell: partner) { commands.append($0) })
                subject.handleNavigation(action: action, phase: .release, inputTime: duration) { commands.append($0) }
                XCTAssertEqual(commands, [action == .nextChange ? .beginNextChangeHold : .beginPreviousChangeHold, .cancelNavigationHold, .undoLastStageAndAdvance])
                XCTAssertFalse(subject.handleUndoChord(cell: partner) { commands.append($0) })
            }
        }
    }

    func testCancelledHoldCannotStageOnReturnAndFirstNewClickHasNoWait() {
        let subject = VSCodeModeGestureClassifier(clock: ManualClock(), scheduler: ManualTickScheduler())
        var commands: [VSCodeModeCommand] = []
        subject.handleNavigation(action: .nextChange, phase: .press, inputTime: 0) { commands.append($0) }
        subject.cancel()
        subject.handleNavigation(action: .nextChange, phase: .release, inputTime: 8) { commands.append($0) }
        subject.handleNavigation(action: .nextChange, phase: .press, inputTime: 9) { commands.append($0) }
        subject.handleNavigation(action: .nextChange, phase: .release, inputTime: 9.06) { commands.append($0) }
        XCTAssertEqual(commands, [.beginNextChangeHold, .beginNextChangeHold, .cancelNavigationHold])
    }

    func testRapidClicksStayShortWhenDeliveryLagsAndSourcesStayIndependent() {
        let clock = ManualClock()
        let first = VSCodeModeGestureClassifier(clock: clock, scheduler: ManualTickScheduler())
        let second = VSCodeModeGestureClassifier(clock: clock, scheduler: ManualTickScheduler())
        var commands: [VSCodeModeCommand] = []
        for index in 0..<20 {
            first.handleNavigation(action: .nextChange, phase: .press, inputTime: Double(index)) { commands.append($0) }
            clock.advance(by: 2)
            XCTAssertFalse(second.handleUndoChord(cell: PhysicalCell(rawValue: 7)!) { commands.append($0) })
            first.handleNavigation(action: .nextChange, phase: .release, inputTime: Double(index) + 0.07) { commands.append($0) }
        }
        XCTAssertEqual(commands, (0..<20).flatMap { _ in [VSCodeModeCommand.beginNextChangeHold, .cancelNavigationHold] })
    }

    func testExactThresholdAndMirroredUndoHint() {
        let subject = VSCodeModeGestureClassifier(clock: ManualClock(), scheduler: ManualTickScheduler())
        var commands: [VSCodeModeCommand] = []
        subject.handleNavigation(action: .nextChange, phase: .press, inputTime: 0) { commands.append($0) }
        subject.handleNavigation(action: .nextChange, phase: .release, inputTime: 0.20) { commands.append($0) }
        XCTAssertEqual(commands, [.beginNextChangeHold, .finishNextChangeHold])
        XCTAssertEqual(VSCodeMode.undoHint(source: .corsair), "Undo: hold 5 + 4 or 8 + 7")
        XCTAssertEqual(VSCodeMode.undoHint(source: .razer), "Undo: hold 5 + 6 or 8 + 9")
    }

    func testReadyFeedbackDoesNotStageAndClearsOnReleaseUndoOrCancel() {
        for finish in ["release", "undo", "cancel"] {
            let clock = ManualClock()
            let scheduler = ManualTickScheduler()
            let subject = VSCodeModeGestureClassifier(clock: clock, scheduler: scheduler)
            var feedback: [Bool] = []
            var commands: [VSCodeModeCommand] = []
            subject.onStageHoldReadyChange = { feedback.append($0) }
            subject.handleNavigation(action: .nextChange, phase: .press, inputTime: 0) { commands.append($0) }
            XCTAssertEqual(scheduler.interval, 0.20)
            clock.advance(by: 0.20)
            scheduler.fire(times: 2)
            XCTAssertEqual(feedback, [true])
            XCTAssertEqual(commands, [.beginNextChangeHold])
            if finish == "undo" {
                XCTAssertTrue(subject.handleUndoChord(cell: PhysicalCell(rawValue: 7)!) { commands.append($0) })
            } else if finish == "cancel" {
                subject.cancel()
            }
            subject.handleNavigation(action: .nextChange, phase: .release, inputTime: 0.6) { commands.append($0) }
            scheduler.fire()
            XCTAssertEqual(feedback, [true, false])
            XCTAssertEqual(commands, finish == "release" ? [.beginNextChangeHold, .finishNextChangeHold] : finish == "undo" ? [.beginNextChangeHold, .cancelNavigationHold, .undoLastStageAndAdvance] : [.beginNextChangeHold])
        }
    }

    func testLateFeedbackTimerCannotStageAShortOriginalClick() {
        let scheduler = ManualTickScheduler()
        let subject = VSCodeModeGestureClassifier(clock: ManualClock(), scheduler: scheduler)
        var feedback: [Bool] = []
        var commands: [VSCodeModeCommand] = []
        subject.onStageHoldReadyChange = { feedback.append($0) }
        subject.handleNavigation(action: .previousChange, phase: .press, inputTime: 0) { commands.append($0) }
        scheduler.fire()
        subject.handleNavigation(action: .previousChange, phase: .release, inputTime: 0.05) { commands.append($0) }
        XCTAssertEqual(feedback, [true, false])
        XCTAssertEqual(commands, [.beginPreviousChangeHold, .cancelNavigationHold])
    }

    func testChildTransportClosesEveryReleaseAfterItsDecision() {
        for action in [VSCodeModeAction.nextChange, .previousChange] {
            let shortSubject = VSCodeModeGestureClassifier(clock: ManualClock(), scheduler: ManualTickScheduler())
            var shortCommands: [VSCodeModeCommand] = []
            shortSubject.onStageHoldReadyChange = { ready in
                shortCommands.append(ready ? .stageHoldReady : .stageHoldClear)
            }
            shortSubject.handleNavigation(action: action, phase: .press, inputTime: 0) { shortCommands.append($0) }
            shortSubject.handleNavigation(action: action, phase: .release, inputTime: 0.05) { shortCommands.append($0) }
            XCTAssertEqual(shortCommands, [
                action == .nextChange ? .beginNextChangeHold : .beginPreviousChangeHold,
                .cancelNavigationHold,
                .stageHoldClear,
            ])

            let scheduler = ManualTickScheduler()
            let longSubject = VSCodeModeGestureClassifier(clock: ManualClock(), scheduler: scheduler)
            var longCommands: [VSCodeModeCommand] = []
            longSubject.onStageHoldReadyChange = { ready in
                longCommands.append(ready ? .stageHoldReady : .stageHoldClear)
            }
            longSubject.handleNavigation(action: action, phase: .press, inputTime: 0) { longCommands.append($0) }
            scheduler.fire()
            longSubject.handleNavigation(action: action, phase: .release, inputTime: Self.longHoldDuration) { longCommands.append($0) }
            XCTAssertEqual(longCommands, [
                action == .nextChange ? .beginNextChangeHold : .beginPreviousChangeHold,
                .stageHoldReady,
                action == .nextChange ? .finishNextChangeHold : .finishPreviousChangeHold,
                .stageHoldClear,
            ])
        }
    }

    func testChildTransportClosesAdjacentCancelAfterF14AndF16() {
        for action in [VSCodeModeAction.nextChange, .previousChange] {
            let subject = VSCodeModeGestureClassifier(clock: ManualClock(), scheduler: ManualTickScheduler())
            var commands: [VSCodeModeCommand] = []
            subject.onStageHoldReadyChange = { ready in
                commands.append(ready ? .stageHoldReady : .stageHoldClear)
            }
            subject.handleNavigation(action: action, phase: .press, inputTime: 0) { commands.append($0) }
            let partner = PhysicalCell(rawValue: action == .nextChange ? 7 : 4)!
            XCTAssertTrue(subject.handleUndoChord(cell: partner) { commands.append($0) })
            subject.handleNavigation(action: action, phase: .release, inputTime: Self.longHoldDuration) { commands.append($0) }
            XCTAssertEqual(commands, [
                action == .nextChange ? .beginNextChangeHold : .beginPreviousChangeHold,
                .cancelNavigationHold,
                .undoLastStageAndAdvance,
                .stageHoldClear,
            ])
        }
    }

    func testStageRangeWheelArmsOnlyAtReadinessAndDisarmsBeforeReleaseDecision() {
        let clock = ManualClock()
        let scheduler = ManualTickScheduler()
        let subject = VSCodeModeGestureClassifier(
            clock: clock,
            scheduler: scheduler,
            stageRangePreviewNavigationEnabled: true
        )
        var events: [String] = []
        subject.onStageHoldReadyChange = { ready in
            events.append(ready ? "feedback-ready" : "feedback-clear")
        }
        subject.onStageRangeWheelReadyChange = { ready in
            events.append(ready ? "wheel-arm" : "wheel-release")
        }

        subject.handleNavigation(action: .nextChange, phase: .press, inputTime: 0) {
            events.append($0.rawValue)
        }
        XCTAssertEqual(events, [VSCodeModeCommand.beginNextChangeHold.rawValue])
        clock.advance(by: 0.20)
        scheduler.fire()
        XCTAssertEqual(events, [
            VSCodeModeCommand.beginNextChangeHold.rawValue,
            "feedback-ready",
            "wheel-arm",
        ])
        subject.handleNavigation(action: .nextChange, phase: .release, inputTime: 0.5) {
            events.append($0.rawValue)
        }
        XCTAssertEqual(events, [
            VSCodeModeCommand.beginNextChangeHold.rawValue,
            "feedback-ready",
            "wheel-arm",
            "wheel-release",
            VSCodeModeCommand.finishNextChangeHold.rawValue,
            "feedback-clear",
        ])
    }

    func testStageButtonTemporarilyEnablesReadyRangeWithoutFiringItsOwnAction() {
        let clock = ManualClock()
        let scheduler = ManualTickScheduler()
        let subject = VSCodeModeGestureClassifier(
            clock: clock,
            scheduler: scheduler,
            stageRangePreviewNavigationEnabled: true
        )
        var commands: [VSCodeModeCommand] = []

        subject.handleNavigation(action: .nextChange, phase: .press, inputTime: 0) {
            commands.append($0)
        }
        XCTAssertFalse(subject.handleStageRangeNavigationChord(
            action: .find,
            phase: .press
        ))
        XCTAssertTrue(subject.handleStageRangeNavigationChord(
            action: .stageAndNext,
            phase: .press
        ))
        XCTAssertFalse(subject.isStageRangeNavigationActive)

        clock.advance(by: Self.stageHoldDuration)
        scheduler.fire()
        XCTAssertTrue(subject.isStageRangeNavigationActive)
        XCTAssertEqual(commands, [.beginNextChangeHold])

        XCTAssertTrue(subject.handleStageRangeNavigationChord(
            action: .stageAndNext,
            phase: .release
        ))
        XCTAssertFalse(subject.isStageRangeNavigationActive)
        XCTAssertTrue(subject.handleStageRangeNavigationChord(action: .stageAndNext, phase: .press))
        XCTAssertTrue(subject.isStageRangeNavigationActive)
        XCTAssertTrue(subject.handleStageRangeNavigationChord(action: .stageAndNext, phase: .release))
        XCTAssertFalse(subject.isStageRangeNavigationActive)
        subject.handleNavigation(
            action: .nextChange,
            phase: .release,
            inputTime: Self.longHoldDuration
        ) { commands.append($0) }
        XCTAssertEqual(commands, [.beginNextChangeHold, .finishNextChangeHold])
    }

    func testStageRangeNavigationModifierClearsWhenTheOwningHoldEndsFirst() {
        let scheduler = ManualTickScheduler()
        let subject = VSCodeModeGestureClassifier(
            clock: ManualClock(),
            scheduler: scheduler,
            stageRangePreviewNavigationEnabled: true
        )
        subject.handleNavigation(action: .nextChange, phase: .press, inputTime: 0) { _ in }
        XCTAssertTrue(subject.handleStageRangeNavigationChord(
            action: .stageAndNext,
            phase: .press
        ))
        scheduler.fire()
        XCTAssertTrue(subject.isStageRangeNavigationActive)
        subject.handleNavigation(action: .nextChange, phase: .release, inputTime: 0.6) { _ in }
        XCTAssertFalse(subject.isStageRangeNavigationActive)
        XCTAssertFalse(subject.handleStageRangeNavigationChord(
            action: .stageAndNext,
            phase: .release
        ))
    }

    func testAdjacentPreviewModifierIsEnabledByDefaultAndClearsOnHoldRelease() {
        let scheduler = ManualTickScheduler()
        let subject = VSCodeModeGestureClassifier(clock: ManualClock(), scheduler: scheduler)
        subject.handleNavigation(action: .nextChange, phase: .press, inputTime: 0) { _ in }
        scheduler.fire()

        XCTAssertTrue(VSCodeModeFeatureFlags.stageRangePreviewNavigation)
        XCTAssertEqual(subject.handleAdjacentPreviewChord(
            cell: PhysicalCell(rawValue: 9)!, phase: .press
        ).direction, .next)
        XCTAssertTrue(subject.isStageRangeNavigationActive)
        subject.handleNavigation(action: .nextChange, phase: .release, inputTime: 0.6) { _ in }
        XCTAssertFalse(subject.isStageRangeNavigationActive)
    }

    func testMomentaryPreviewClearsOnEarlyReleaseUndoCancelAndNewHold() {
        for finish in ["release", "undo", "cancel"] {
            for ready in [false, true] {
                let scheduler = ManualTickScheduler()
                let subject = VSCodeModeGestureClassifier(clock: ManualClock(), scheduler: scheduler)
                var changes: [Bool] = []
                subject.onStageRangeNavigationChange = { changes.append($0) }
                subject.handleNavigation(action: .nextChange, phase: .press, inputTime: 0) { _ in }
                if ready { scheduler.fire() }
                XCTAssertTrue(subject.handleAdjacentPreviewChord(
                    cell: PhysicalCell(rawValue: 9)!, phase: .press
                ).handled)
                XCTAssertTrue(subject.handleAdjacentPreviewChord(
                    cell: PhysicalCell(rawValue: 9)!, phase: .release
                ).handled)
                XCTAssertFalse(subject.isStageRangeNavigationActive)
                if finish == "undo" {
                    XCTAssertTrue(subject.handleUndoChord(cell: PhysicalCell(rawValue: 7)!) { _ in })
                } else if finish == "cancel" {
                    subject.cancel()
                }
                subject.handleNavigation(action: .nextChange, phase: .release, inputTime: ready ? 0.5 : 0.05) { _ in }
                XCTAssertFalse(subject.isStageRangeNavigationActive)
                XCTAssertEqual(changes, ready ? [true, false] : [])
                subject.handleNavigation(action: .nextChange, phase: .press, inputTime: 1) { _ in }
                scheduler.fire()
                XCTAssertFalse(subject.isStageRangeNavigationActive)
            }
        }
    }

    func testUnrelatedStageButtonDoesNotModifyPreviousHoldWheel() {
        let scheduler = ManualTickScheduler()
        let subject = VSCodeModeGestureClassifier(clock: ManualClock(), scheduler: scheduler)
        subject.handleNavigation(action: .previousChange, phase: .press, inputTime: 0) { _ in }
        scheduler.fire()
        XCTAssertFalse(subject.handleStageRangeNavigationChord(
            action: .stageAndNext, phase: .press
        ))
        XCTAssertFalse(subject.isStageRangeNavigationActive)
    }

    private static let stageHoldDuration: TimeInterval = 0.20
    private static let longHoldDuration: TimeInterval = 0.6
}
