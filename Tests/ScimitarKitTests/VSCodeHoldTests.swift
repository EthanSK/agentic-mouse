import XCTest
@testable import ScimitarKit

final class VSCodeHoldTests: XCTestCase {
    func testButtonDownNavigatesImmediatelyAndShortReleaseOnlyCancelsStage() {
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
                XCTAssertEqual(commands, [action == .nextChange ? .beginNextChangeHold : .beginPreviousChangeHold, .cancelNavigationHoldAtomically])
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
            XCTAssertEqual(commands, finish == "release" ? [.beginNextChangeHold, .finishNextChangeHold] : finish == "undo" ? [.beginNextChangeHold, .cancelNavigationHoldAtomically] : [.beginNextChangeHold])
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

    func testChildTransportClosesAdjacentCancelWithOneSourceTaggedF16() {
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
                .cancelNavigationHoldAtomically,
                .stageHoldClear,
            ])
        }
    }

    private static let longHoldDuration: TimeInterval = 0.6
}
