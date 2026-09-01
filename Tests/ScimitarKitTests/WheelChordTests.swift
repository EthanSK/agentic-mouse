import XCTest
@testable import ScimitarKit

final class WheelChordTests: XCTestCase {
    func testOneRatchetedEventProducesOneStepRegardlessOfDeltaMagnitude() {
        let state = WheelChordStateMachine()
        state.setActive(.brightness, for: .corsair)

        XCTAssertEqual(
            state.route(verticalDelta: 4, isContinuous: false),
            .consume(.init(
                source: .corsair,
                control: .brightness,
                direction: .up,
                detentCount: 1
            ))
        )
        XCTAssertEqual(
            state.route(verticalDelta: -7, isContinuous: false),
            .consume(.init(
                source: .corsair,
                control: .brightness,
                direction: .down,
                detentCount: 2
            ))
        )
    }

    func testOrdinaryAndContinuousScrollingPassThrough() {
        let state = WheelChordStateMachine()
        XCTAssertEqual(state.route(verticalDelta: 1, isContinuous: false), .passThrough)

        state.setActive(.zoom, for: .razer)
        XCTAssertEqual(
            state.route(verticalDelta: 1, isContinuous: true, scrollPhase: 2),
            .passThrough
        )
        XCTAssertEqual(
            state.route(verticalDelta: 1, isContinuous: true, momentumPhase: 2),
            .passThrough
        )
        XCTAssertEqual(state.route(verticalDelta: 0, isContinuous: false), .passThrough)
    }

    func testPhaseFreeVirtualMouseDetentsWorkWhenMarkedContinuous() {
        let state = WheelChordStateMachine()
        state.setActive(.spaces, for: .corsair)

        XCTAssertEqual(
            state.route(
                verticalDelta: 1,
                isContinuous: true,
                scrollPhase: 0,
                momentumPhase: 0
            ),
            .consume(.init(
                source: .corsair,
                control: .spaces,
                direction: .up,
                detentCount: 1
            ))
        )
    }

    func testVirtualMousePointAndFixedPointDeltasProvideDirectionFallbacks() {
        XCTAssertEqual(
            WheelChordDirection.effectiveVerticalDelta(
                lineDelta: 0,
                pointDelta: 32,
                fixedPointDelta: 0
            ),
            32
        )
        XCTAssertEqual(
            WheelChordDirection.effectiveVerticalDelta(
                lineDelta: 0,
                pointDelta: 0,
                fixedPointDelta: -65_536
            ),
            -1
        )
        XCTAssertEqual(
            WheelChordDirection.effectiveVerticalDelta(
                lineDelta: -1,
                pointDelta: 32,
                fixedPointDelta: 65_536
            ),
            -1
        )
    }

    func testTwoSimultaneousSourceChordsAreConsumedWithoutGuessing() {
        let state = WheelChordStateMachine()
        state.setActive(.brightness, for: .corsair)
        state.setActive(.spaces, for: .razer)

        XCTAssertEqual(state.route(verticalDelta: 1, isContinuous: false), .consumeAmbiguous)

        state.clear(source: .corsair)
        XCTAssertEqual(
            state.route(verticalDelta: -1, isContinuous: false),
            .consume(.init(
                source: .razer,
                control: .spaces,
                direction: .down,
                detentCount: 1
            ))
        )
    }

    func testPlainYouTubeReleaseIsAClickOnBothMice() {
        for source in MouseSource.allCases {
            let state = WheelChordStateMachine()
            state.setActive(.youtubeScrub, for: source)

            XCTAssertEqual(
                state.release(.youtubeScrub, for: source),
                .init(
                    source: source,
                    control: .youtubeScrub,
                    didObserveWheelInput: false
                )
            )
            XCTAssertNil(state.activeControl(for: source))
            XCTAssertNil(state.release(.youtubeScrub, for: source))
        }
    }

    func testYouTubeWheelGestureSuppressesTheReleaseClick() {
        let state = WheelChordStateMachine()
        state.setActive(.youtubeScrub, for: .corsair)

        XCTAssertEqual(
            state.route(verticalDelta: -1, isContinuous: false),
            .consume(.init(
                source: .corsair,
                control: .youtubeScrub,
                direction: .down,
                detentCount: 1
            ))
        )
        state.setActive(.youtubeScrub, for: .corsair)
        XCTAssertEqual(
            state.release(.youtubeScrub, for: .corsair),
            .init(
                source: .corsair,
                control: .youtubeScrub,
                didObserveWheelInput: true
            ),
            "a duplicate press must not forget that this hold already used the wheel"
        )
    }

    func testPassedThroughAndAmbiguousWheelInputAlsoSuppressYouTubeClick() {
        let state = WheelChordStateMachine()
        state.setActive(.youtubeScrub, for: .razer)
        XCTAssertEqual(
            state.route(
                verticalDelta: 1,
                isContinuous: true,
                scrollPhase: 2
            ),
            .passThrough
        )
        XCTAssertEqual(
            state.release(.youtubeScrub, for: .razer)?.didObserveWheelInput,
            true
        )

        state.setActive(.youtubeScrub, for: .corsair)
        state.setActive(.brightness, for: .razer)
        XCTAssertEqual(state.route(verticalDelta: -1, isContinuous: false), .consumeAmbiguous)
        XCTAssertEqual(
            state.release(.youtubeScrub, for: .corsair)?.didObserveWheelInput,
            true
        )
        XCTAssertEqual(
            state.release(.brightness, for: .razer)?.didObserveWheelInput,
            true
        )
    }

    func testStaleReleaseAndLifecycleClearCannotTriggerYouTubeClick() {
        let state = WheelChordStateMachine()
        state.setActive(.youtubeScrub, for: .corsair)

        XCTAssertNil(state.release(.clipboard, for: .corsair))
        XCTAssertEqual(state.activeControl(for: .corsair), .youtubeScrub)

        state.clear(source: .corsair)
        XCTAssertNil(state.release(.youtubeScrub, for: .corsair))
    }

    func testSpacesProducesAtMostOneStepPerHoldAndRearmsOnRelease() {
        let state = WheelChordStateMachine()
        state.setActive(.spaces, for: .corsair)

        guard case .consume(let first) = state.route(
            verticalDelta: 1,
            isContinuous: false
        ), case .consumeAfterFirstHoldAction(let second) = state.route(
            verticalDelta: 1,
            isContinuous: false
        ), case .consumeAfterFirstHoldAction(let reversed) = state.route(
            verticalDelta: -1,
            isContinuous: false
        ) else {
            return XCTFail("only the first accepted sign should produce a Space step")
        }
        XCTAssertEqual(first.detentCount, 1)
        XCTAssertEqual(second.detentCount, 2)
        XCTAssertEqual(reversed.detentCount, 3)
        XCTAssertEqual(reversed.direction, .down)

        state.setActive(.spaces, for: .corsair)
        guard case .consumeAfterFirstHoldAction(let duplicatePress) = state.route(
            verticalDelta: 1,
            isContinuous: false
        ) else {
            return XCTFail("a duplicate press command must not re-arm the physical hold")
        }
        XCTAssertEqual(duplicatePress.detentCount, 4)

        state.setActive(nil, for: .corsair)
        state.setActive(.spaces, for: .corsair)
        guard case .consume(let afterRearm) = state.route(
            verticalDelta: -1,
            isContinuous: false
        ) else {
            return XCTFail("the re-armed detent should route")
        }
        XCTAssertEqual(afterRearm.detentCount, 1)
        XCTAssertEqual(afterRearm.direction, .down)
    }

    func testApplicationWindowsUsesOnlyWheelDownAndActsOncePerHold() {
        let state = WheelChordStateMachine()
        state.setActive(.applicationWindows, for: .corsair)

        guard case .consumeInactiveDirection(let ignoredUp) = state.route(
            verticalDelta: 1,
            isContinuous: false
        ), case .consume(let firstDown) = state.route(
            verticalDelta: -1,
            isContinuous: false
        ), case .consumeAfterFirstHoldAction(let secondDown) = state.route(
            verticalDelta: -1,
            isContinuous: false
        ) else {
            return XCTFail("App Exposé should accept only the first wheel-down detent")
        }
        XCTAssertEqual(ignoredUp.detentCount, 1)
        XCTAssertEqual(firstDown.detentCount, 2)
        XCTAssertEqual(secondDown.detentCount, 3)

        state.setActive(nil, for: .corsair)
        state.setActive(.applicationWindows, for: .corsair)
        XCTAssertEqual(
            state.route(verticalDelta: -1, isContinuous: false),
            .consume(.init(
                source: .corsair,
                control: .applicationWindows,
                direction: .down,
                detentCount: 1
            ))
        )
    }

    func testContinuousControlsContinueActingForEveryAcceptedEvent() {
        let state = WheelChordStateMachine()
        for control in [
            WheelChordControl.brightness,
            .zoom,
        ] {
            state.setActive(control, for: .razer)
            guard case .consume(let first) = state.route(
                verticalDelta: 1,
                isContinuous: false
            ), case .consume(let second) = state.route(
                verticalDelta: -1,
                isContinuous: false
            ) else {
                return XCTFail("\(control) should remain continuous")
            }
            XCTAssertEqual(first.detentCount, 1)
            XCTAssertEqual(second.detentCount, 2)
            XCTAssertEqual(first.direction, .up)
            XCTAssertEqual(second.direction, .down)
            state.setActive(nil, for: .razer)
        }
    }

    func testSystemOverviewActsOnlyOncePerHold() {
        let state = WheelChordStateMachine()

        for control in [WheelChordControl.systemOverview] {
            state.setActive(control, for: .corsair)
            guard case .consume(let first) = state.route(
                verticalDelta: 1,
                isContinuous: false
            ), case .consumeAfterFirstHoldAction(let duplicate) = state.route(
                verticalDelta: -1,
                isContinuous: false
            ) else {
                return XCTFail("\(control) should dispatch once per hold")
            }
            XCTAssertEqual(first.detentCount, 1)
            XCTAssertEqual(duplicate.detentCount, 2)

            state.setActive(nil, for: .corsair)
            state.setActive(control, for: .corsair)
            guard case .consume(let rearmed) = state.route(
                verticalDelta: -1,
                isContinuous: false
            ) else {
                return XCTFail("release should re-arm \(control)")
            }
            XCTAssertEqual(rearmed.detentCount, 1)
            state.setActive(nil, for: .corsair)
        }
    }

    func testDiscreteRepeatersCoalesceSameDirectionRawEventBursts() {
        let clock = ManualClock(now: 10)
        let state = WheelChordStateMachine(clock: clock)

        let controls: [(WheelChordControl, TimeInterval)] = [
            (.horizontalScroll, 0.08),
            (.youtubeScrub, 0.08),
            (.clipboard, 0.12),
            (.chromeTabs, 0.08),
            (.spotifyVolume, 0.08),
            (.magnetWindow, 0.15),
        ]
        for (control, interval) in controls {
            state.setActive(control, for: .razer)
            guard case .consume(let first) = state.route(
                verticalDelta: 1,
                isContinuous: false
            ), case .consumeDebounced(let duplicate) = state.route(
                verticalDelta: 1,
                isContinuous: false
            ) else {
                return XCTFail("\(control) should suppress the duplicate event burst")
            }
            XCTAssertEqual(first.detentCount, 1)
            XCTAssertEqual(duplicate.detentCount, 2)

            clock.advance(by: interval - 0.001)
            guard case .consumeDebounced = state.route(
                verticalDelta: 1,
                isContinuous: false
            ) else {
                return XCTFail("\(control) should remain inside its debounce window")
            }
            clock.advance(by: 0.002)
            guard case .consume(let nextRatchet) = state.route(
                verticalDelta: 1,
                isContinuous: false
            ) else {
                return XCTFail("\(control) should accept a later physical ratchet")
            }
            XCTAssertEqual(nextRatchet.detentCount, 4)
            XCTAssertEqual(nextRatchet.direction, .up)
            state.setActive(nil, for: .razer)
        }
    }

    func testDiscreteRepeatersAcceptAnImmediateDirectionReversal() {
        let clock = ManualClock(now: 10)
        let state = WheelChordStateMachine(clock: clock)
        for control in [
            WheelChordControl.horizontalScroll,
            .youtubeScrub,
            .clipboard,
            .chromeTabs,
            .spotifyVolume,
            .magnetWindow,
        ] {
            state.setActive(control, for: .corsair)
            guard case .consume = state.route(verticalDelta: 1, isContinuous: false),
                  case .consume(let reversed) = state.route(
                    verticalDelta: -1,
                    isContinuous: false
                  )
            else { return XCTFail("\(control) reversal should remain immediate") }
            XCTAssertEqual(reversed.direction, .down)
            XCTAssertEqual(reversed.detentCount, 2)
            state.setActive(nil, for: .corsair)
        }
    }

    func testVSCodeCursorHistoryCoalescesEachSameDirectionRatchetAndKeepsReversalImmediate() {
        let clock = ManualClock(now: 10)
        let state = WheelChordStateMachine(clock: clock)
        state.setActive(.vsCodeCursorHistory, for: .corsair)

        guard case .consume(let first) = state.route(
            verticalDelta: 1,
            isContinuous: false
        ) else { return XCTFail("the first raw event should dispatch one history action") }
        XCTAssertEqual(first.direction, .up)
        XCTAssertEqual(
            first.control.vsCodeCursorHistoryCommand(for: first.direction),
            .navigateForward
        )

        clock.advance(by: 0.09)
        guard case .consumeDebounced = state.route(
            verticalDelta: 1,
            isContinuous: false
        ) else { return XCTFail("a same-sign raw burst event should be coalesced") }

        clock.advance(by: 0.09)
        guard case .consumeDebounced = state.route(
            verticalDelta: 1,
            isContinuous: false
        ) else { return XCTFail("a burst longer than the first window must remain coalesced") }

        clock.advance(by: 0.149)
        guard case .consumeDebounced = state.route(
            verticalDelta: 1,
            isContinuous: false
        ) else { return XCTFail("the quiet gap extends from the latest raw event") }

        clock.advance(by: 0.151)
        guard case .consume(let nextRatchet) = state.route(
            verticalDelta: 1,
            isContinuous: false
        ) else { return XCTFail("a distinct later ratchet should dispatch again") }
        XCTAssertEqual(nextRatchet.direction, .up)
        XCTAssertEqual(
            nextRatchet.control.vsCodeCursorHistoryCommand(for: nextRatchet.direction),
            .navigateForward
        )

        clock.advance(by: 0.01)
        guard case .consume(let reversed) = state.route(
            verticalDelta: -1,
            isContinuous: false
        ) else { return XCTFail("an intentional reverse ratchet should dispatch immediately") }
        XCTAssertEqual(reversed.direction, .down)
        XCTAssertEqual(
            reversed.control.vsCodeCursorHistoryCommand(for: reversed.direction),
            .navigateBack
        )

        clock.advance(by: 0.05)
        guard case .consumeDebounced = state.route(
            verticalDelta: -1,
            isContinuous: false
        ) else { return XCTFail("the reverse ratchet's duplicate burst should coalesce") }
    }

    func testCodexReasoningEffortInvertsQuartzSignButChatHistoryKeepsItsOwnPolarity() {
        XCTAssertEqual(WheelChordControl.codexReasoningEffort.diagnosticCell.rawValue, 4)
        XCTAssertEqual(WheelChordControl.codexChatHistory.diagnosticCell.rawValue, 11)
        XCTAssertEqual(
            WheelChordControl.codexReasoningEffort.codexReasoningEffortAction(for: .up),
            .decrease
        )
        XCTAssertEqual(
            WheelChordControl.codexReasoningEffort.codexReasoningEffortAction(for: .down),
            .increase
        )
        XCTAssertEqual(
            WheelChordControl.codexReasoningEffort.feedbackActionTitle(for: .up),
            "Reasoning Effort Down"
        )
        XCTAssertEqual(
            WheelChordControl.codexReasoningEffort.feedbackActionTitle(for: .down),
            "Reasoning Effort Up"
        )
        XCTAssertEqual(
            WheelChordControl.codexChatHistory.codexChatHistoryAction(for: .up),
            .forward
        )
        XCTAssertEqual(
            WheelChordControl.codexChatHistory.codexChatHistoryAction(for: .down),
            .back
        )
        XCTAssertNil(WheelChordControl.zoom.codexReasoningEffortAction(for: .up))
        XCTAssertNil(WheelChordControl.zoom.codexChatHistoryAction(for: .up))
    }

    func testCodexReasoningEffortCoalescesOneRawBurstPerRatchet() {
        let clock = ManualClock(now: 10)
        let state = WheelChordStateMachine(clock: clock)
        state.setActive(.codexReasoningEffort, for: .corsair)
        guard case .consume(let first) = state.route(
            verticalDelta: 1,
            isContinuous: false
        ), case .consumeDebounced = state.route(
            verticalDelta: 1,
            isContinuous: false
        ) else { return XCTFail("Reasoning Effort should coalesce a same-sign raw burst") }
        XCTAssertEqual(first.direction, .up)

        clock.advance(by: 0.151)
        guard case .consume(let next) = state.route(
            verticalDelta: 1,
            isContinuous: false
        ), case .consume(let reversed) = state.route(
            verticalDelta: -1,
            isContinuous: false
        ) else { return XCTFail("Reasoning Effort should repeat and reverse deliberately") }
        XCTAssertEqual(next.direction, .up)
        XCTAssertEqual(reversed.direction, .down)
    }

    func testCodexChatHistoryDispatchesEachRatchetWithoutAQuietGap() {
        let clock = ManualClock(now: 10)
        let state = WheelChordStateMachine(clock: clock)
        state.setActive(.codexChatHistory, for: .corsair)

        XCTAssertEqual(
            WheelChordControl.codexChatHistory.dispatchPolicy,
            .debounced(minimumInterval: 0.08)
        )
        guard case .consume(let first) = state.route(
            verticalDelta: 1,
            isContinuous: false
        ) else { return XCTFail("the first Chats Selection ratchet should dispatch") }
        XCTAssertEqual(first.direction, .up)

        clock.advance(by: 0.05)
        guard case .consumeDebounced = state.route(
            verticalDelta: 1,
            isContinuous: false
        ) else { return XCTFail("one ratchet's duplicate raw event should be filtered") }

        // The suppressed raw event must not restart a sliding quiet gap. The
        // next physical ratchet can advance one chat as soon as the fixed
        // leading-edge window from the prior dispatched action has elapsed.
        clock.advance(by: 0.031)
        guard case .consume(let nextRatchet) = state.route(
            verticalDelta: 1,
            isContinuous: false
        ) else { return XCTFail("the next Chats Selection ratchet should dispatch without a quiet gap") }
        XCTAssertEqual(nextRatchet.direction, .up)

        clock.advance(by: 0.01)
        guard case .consume(let reversed) = state.route(
            verticalDelta: -1,
            isContinuous: false
        ) else { return XCTFail("a reverse Chats Selection ratchet should remain immediate") }
        XCTAssertEqual(reversed.direction, .down)

        clock.advance(by: 0.05)
        guard case .consumeDebounced = state.route(
            verticalDelta: -1,
            isContinuous: false
        ) else { return XCTFail("the reverse ratchet's duplicate raw event should be filtered") }
    }

    func testLifecycleClearPreventsAStaleArmFromConsumingLaterScrolling() {
        let state = WheelChordStateMachine()
        state.setActive(.spaces, for: .corsair)
        state.clearAll()

        XCTAssertEqual(
            state.route(verticalDelta: 1, isContinuous: false),
            .passThrough
        )
    }

    func testActiveChordIsInspectableWithoutChangingRouting() {
        let state = WheelChordStateMachine()
        XCTAssertNil(state.soleActiveChord)

        state.setActive(.spaces, for: .corsair)
        XCTAssertEqual(state.activeControl(for: .corsair), .spaces)
        XCTAssertEqual(state.soleActiveChord?.source, .corsair)
        XCTAssertEqual(state.soleActiveChord?.control, .spaces)

        state.setActive(.horizontalScroll, for: .razer)
        XCTAssertNil(state.soleActiveChord)
    }

    func testDiagnosticThrottleCoalescesOnlyHudUpdates() {
        let clock = ManualClock(now: 10)
        let throttle = WheelChordDiagnosticThrottle(
            clock: clock,
            minimumInterval: 0.125
        )

        XCTAssertTrue(throttle.shouldEmit(for: .corsair))
        XCTAssertFalse(throttle.shouldEmit(for: .corsair))
        XCTAssertTrue(throttle.shouldEmit(for: .razer), "each source has an independent trace")

        clock.advance(by: 0.124)
        XCTAssertFalse(throttle.shouldEmit(for: .corsair))
        clock.advance(by: 0.001)
        XCTAssertTrue(throttle.shouldEmit(for: .corsair))

        throttle.reset(source: .corsair)
        XCTAssertTrue(throttle.shouldEmit(for: .corsair))
        throttle.resetAll()
        XCTAssertTrue(throttle.shouldEmit(for: .razer))
    }

    func testWheelDirectionsResolveEveryTwoWayUtilityFamily() {
        XCTAssertEqual(WheelChordControl.brightness.utilityAction(for: .up), .decreaseDisplayBrightness)
        XCTAssertEqual(WheelChordControl.brightness.utilityAction(for: .down), .increaseDisplayBrightness)
        XCTAssertEqual(WheelChordControl.zoom.utilityAction(for: .up), .zoomIn)
        XCTAssertEqual(WheelChordControl.zoom.utilityAction(for: .down), .zoomOut)
        XCTAssertEqual(WheelChordControl.clipboard.utilityAction(for: .up), .paste)
        XCTAssertEqual(WheelChordControl.clipboard.utilityAction(for: .down), .copy)
        XCTAssertEqual(WheelChordControl.systemOverview.utilityAction(for: .up), .missionControl)
        XCTAssertEqual(WheelChordControl.systemOverview.utilityAction(for: .down), .showDesktop)
        XCTAssertEqual(
            WheelChordControl.applicationWindows.utilityAction(for: .up),
            nil
        )
        XCTAssertEqual(
            WheelChordControl.applicationWindows.utilityAction(for: .down),
            .showApplicationWindows
        )
        XCTAssertEqual(
            WheelChordControl.magnetWindow.utilityAction(for: .up),
            .moveWindowLeftWithMagnet
        )
        XCTAssertEqual(
            WheelChordControl.magnetWindow.utilityAction(for: .down),
            .moveWindowRightWithMagnet
        )
        XCTAssertEqual(WheelChordControl.spaces.utilityAction(for: .up), .moveToSpaceRight)
        XCTAssertEqual(WheelChordControl.spaces.utilityAction(for: .down), .moveToSpaceLeft)
        XCTAssertNil(WheelChordControl.horizontalScroll.utilityAction(for: .up))
        XCTAssertNil(WheelChordControl.youtubeScrub.utilityAction(for: .up))
        XCTAssertEqual(
            WheelChordControl.youtubeScrub.youtubeSeekAction(for: .up),
            .backwardFiveSeconds
        )
        XCTAssertEqual(
            WheelChordControl.youtubeScrub.youtubeSeekAction(for: .down),
            .forwardFiveSeconds
        )
        XCTAssertNil(WheelChordControl.zoom.youtubeSeekAction(for: .up))
        XCTAssertEqual(YouTubeSeekAction.forwardFiveSeconds.seconds, 5)
        XCTAssertEqual(YouTubeSeekAction.backwardFiveSeconds.seconds, -5)
        XCTAssertNil(WheelChordControl.chromeTabs.utilityAction(for: .up))
        XCTAssertEqual(WheelChordControl.chromeTabs.chromeTabAction(for: .up), .previousTab)
        XCTAssertEqual(WheelChordControl.chromeTabs.chromeTabAction(for: .down), .nextTab)
        XCTAssertNil(WheelChordControl.zoom.chromeTabAction(for: .up))
        XCTAssertEqual(
            WheelChordControl.spotifyVolume.spotifyVolumeAction(for: .up),
            StandardAppModeAction(
                cell: StandardAppMode.spotifyVolumeWheelCell,
                title: "Volume up",
                keyCode: 126,
                modifiers: [.command]
            )
        )
        XCTAssertEqual(
            WheelChordControl.spotifyVolume.spotifyVolumeAction(for: .down),
            StandardAppModeAction(
                cell: StandardAppMode.spotifyVolumeWheelCell,
                title: "Volume down",
                keyCode: 125,
                modifiers: [.command]
            )
        )
        XCTAssertNil(WheelChordControl.zoom.spotifyVolumeAction(for: .up))
        XCTAssertEqual(WheelChordControl.mediaTracks.mediaTrackAction(for: .down), .next)
        XCTAssertEqual(WheelChordControl.mediaTracks.mediaTrackAction(for: .up), .previous)
        XCTAssertNil(WheelChordControl.zoom.mediaTrackAction(for: .up))
        XCTAssertEqual(WheelChordDirection.up.horizontalWheelDelta, -1)
        XCTAssertEqual(WheelChordDirection.down.horizontalWheelDelta, 1)
    }

    func testEveryActionableWheelDirectionHasConciseFooterFeedbackCopy() {
        let expectations: [(WheelChordControl, WheelChordDirection, String?)] = [
            (.horizontalScroll, .up, "Scroll Right"),
            (.horizontalScroll, .down, "Scroll Left"),
            (.youtubeScrub, .up, "YouTube −5 sec"),
            (.youtubeScrub, .down, "YouTube +5 sec"),
            (.brightness, .up, "Brightness Down"),
            (.brightness, .down, "Brightness Up"),
            (.zoom, .up, "Zoom In"),
            (.zoom, .down, "Zoom Out"),
            (.clipboard, .up, "Paste"),
            (.clipboard, .down, "Copy"),
            (.systemOverview, .up, "Mission Control"),
            (.systemOverview, .down, "Show Desktop"),
            (.applicationWindows, .up, nil),
            (.applicationWindows, .down, "App Exposé"),
            (.magnetWindow, .up, "Magnet Left"),
            (.magnetWindow, .down, "Magnet Right"),
            (.spaces, .up, "Space Right"),
            (.spaces, .down, "Space Left"),
            (.chromeTabs, .up, "Previous Tab"),
            (.chromeTabs, .down, "Next Tab"),
            (.spotifyVolume, .up, "Volume up"),
            (.spotifyVolume, .down, "Volume down"),
            (.mediaTracks, .up, "Previous Track"),
            (.mediaTracks, .down, "Next Track"),
            (.vsCodeCursorHistory, .up, "Cursor History Forward"),
            (.vsCodeCursorHistory, .down, "Cursor History Back"),
        ]

        for (control, direction, expected) in expectations {
            XCTAssertEqual(
                control.feedbackActionTitle(for: direction),
                expected,
                "\(control.rawValue) \(direction)"
            )
        }

        for control in WheelChordControl.allCases {
            for direction in [WheelChordDirection.up, .down] where control.accepts(direction) {
                XCTAssertNotNil(
                    control.feedbackActionTitle(for: direction),
                    "Every dispatched wheel action must have footer feedback copy"
                )
            }
        }

        XCTAssertEqual(
            WheelChordControl.clipboard.hudFeedback(
                for: .down,
                detentCount: 2
            ),
            ModeHUDFeedback(
                message: "Copy sent · 2 ratchets",
                tone: .informational
            )
        )
        XCTAssertEqual(
            WheelChordControl.chromeTabs.hudFeedback(
                for: .up,
                detentCount: 1,
                outcome: .couldNotBeSent
            ),
            ModeHUDFeedback(
                message: "Previous Tab could not be sent · 1 ratchet",
                tone: .notConfirmed
            )
        )
        XCTAssertEqual(
            WheelChordControl.magnetWindow.hudFeedback(
                for: .down,
                detentCount: 0,
                outcome: .couldNotBeQueued
            ),
            ModeHUDFeedback(
                message: "Magnet Right could not be queued · 1 ratchet",
                tone: .notConfirmed
            )
        )
        XCTAssertNil(
            WheelChordControl.applicationWindows.hudFeedback(
                for: .up,
                detentCount: 1
            )
        )
    }

    func testTopLevelWheelChordsUseCanonicalCellsOneFourAndSix() {
        XCTAssertEqual(WheelChordControl.clipboard.topLevelCell, PhysicalCell(rawValue: 4))
        XCTAssertEqual(WheelChordControl.horizontalScroll.topLevelCell, PhysicalCell(rawValue: 1))
        XCTAssertEqual(WheelChordControl.youtubeScrub.topLevelCell, PhysicalCell(rawValue: 6))
        XCTAssertNil(WheelChordControl.brightness.topLevelCell)
        XCTAssertNil(WheelChordControl.zoom.topLevelCell)
        XCTAssertNil(WheelChordControl.spaces.topLevelCell)
        XCTAssertNil(WheelChordControl.systemOverview.topLevelCell)
        XCTAssertNil(WheelChordControl.applicationWindows.topLevelCell)
        XCTAssertNil(WheelChordControl.magnetWindow.topLevelCell)
        XCTAssertNil(WheelChordControl.chromeTabs.topLevelCell)
        XCTAssertNil(WheelChordControl.spotifyVolume.topLevelCell)
        XCTAssertNil(WheelChordControl.mediaTracks.topLevelCell)
        XCTAssertNil(WheelChordControl.vsCodeCursorHistory.topLevelCell)
        XCTAssertEqual(WheelChordControl.topLevelControl(for: PhysicalCell(rawValue: 1)!), .horizontalScroll)
        XCTAssertEqual(WheelChordControl.topLevelControl(for: PhysicalCell(rawValue: 4)!), .clipboard)
        XCTAssertEqual(WheelChordControl.topLevelControl(for: PhysicalCell(rawValue: 6)!), .youtubeScrub)
        XCTAssertEqual(
            WheelChordControl.clipboard.topLevelSystemAction(for: .up),
            .paste
        )
        XCTAssertNil(WheelChordControl.spaces.topLevelSystemAction(for: .up))
        XCTAssertNil(WheelChordControl.brightness.topLevelSystemAction(for: .up))
        XCTAssertNil(WheelChordControl.horizontalScroll.topLevelSystemAction(for: .up))
    }

    func testKeysTracksWheelUsesCellNineAndFixedRatchetDebounce() {
        let cell = PhysicalCell.mediaTracksWheelControl

        XCTAssertEqual(WheelChordControl.keysControl(for: cell), .mediaTracks)
        XCTAssertNil(WheelChordControl.keysControl(for: PhysicalCell(rawValue: 8)!))
        XCTAssertEqual(WheelChordControl.mediaTracks.diagnosticCell, cell)
        XCTAssertEqual(WheelChordControl.mediaTracks.dispatchPolicy, .debounced(minimumInterval: 0.08))

        let clock = ManualClock(now: 10)
        let state = WheelChordStateMachine(clock: clock)
        state.setActive(.mediaTracks, for: .corsair)
        guard case .consume(let first) = state.route(verticalDelta: -1, isContinuous: false),
              case .consumeDebounced = state.route(verticalDelta: -1, isContinuous: false)
        else { return XCTFail("one media ratchet should dispatch once") }
        XCTAssertEqual(first.direction, .down)

        clock.advance(by: 0.081)
        guard case .consume(let nextRatchet) = state.route(verticalDelta: -1, isContinuous: false),
              case .consume(let reversed) = state.route(verticalDelta: 1, isContinuous: false)
        else { return XCTFail("a later ratchet and immediate reversal should dispatch") }
        XCTAssertEqual(nextRatchet.direction, .down)
        XCTAssertEqual(reversed.direction, .up)
    }

    func testChromeTabsAndCodexReasoningUseTheirOwnDefinitionsOnSharedCellFour() {
        let cell = PhysicalCell(rawValue: 4)!

        XCTAssertEqual(
            WheelChordControl.appSpecificControl(for: .chrome, cell: cell),
            .chromeTabs
        )
        XCTAssertEqual(
            WheelChordControl.appSpecificControl(for: .codex, cell: cell),
            .codexReasoningEffort
        )
        XCTAssertNil(
            WheelChordControl.appSpecificControl(
                for: .chrome,
                cell: PhysicalCell(rawValue: 5)!
            )
        )
        XCTAssertEqual(cell.printedSide(on: .corsair), 4)
        XCTAssertEqual(cell.printedSide(on: .razer), 6)
    }

    func testSpotifyVolumeWheelUsesSharedCanonicalCellSeven() {
        let cell = StandardAppMode.spotifyVolumeWheelCell

        XCTAssertEqual(
            WheelChordControl.appSpecificControl(for: .spotify, cell: cell),
            .spotifyVolume
        )
        XCTAssertNil(WheelChordControl.appSpecificControl(for: .chrome, cell: cell))
        XCTAssertNil(
            WheelChordControl.appSpecificControl(
                for: .spotify,
                cell: PhysicalCell(rawValue: 8)!
            )
        )
        XCTAssertEqual(cell.printedSide(on: .corsair), 7)
        XCTAssertEqual(cell.printedSide(on: .razer), 9)
    }

    func testVSCodeCursorHistoryWheelUsesSharedCanonicalCellSixAndCorrectDirection() {
        let cell = VSCodeMode.cursorHistoryWheelCell

        XCTAssertEqual(
            WheelChordControl.appSpecificControl(for: .vsCode, cell: cell),
            .vsCodeCursorHistory
        )
        XCTAssertNil(WheelChordControl.appSpecificControl(for: .chrome, cell: cell))
        XCTAssertNil(
            WheelChordControl.appSpecificControl(
                for: .vsCode,
                cell: PhysicalCell(rawValue: 9)!
            )
        )
        XCTAssertEqual(
            WheelChordControl.vsCodeCursorHistory.vsCodeCursorHistoryCommand(for: .down),
            .navigateBack
        )
        XCTAssertEqual(
            WheelChordControl.vsCodeCursorHistory.vsCodeCursorHistoryCommand(for: .up),
            .navigateForward
        )
        XCTAssertNil(WheelChordControl.chromeTabs.vsCodeCursorHistoryCommand(for: .up))
        XCTAssertEqual(cell.printedSide(on: .corsair), 6)
        XCTAssertEqual(cell.printedSide(on: .razer), 4)
        XCTAssertEqual(WheelChordControl.vsCodeCursorHistory.diagnosticCell, cell)
    }

    func testTopLevelCommandPreservesSourceControlAndReleasePhase() throws {
        let command = WheelChordCommand(
            control: .horizontalScroll,
            source: .razer,
            phase: .release
        )
        let data = try JSONEncoder().encode(command)

        XCTAssertEqual(try WheelChordCommand.decode(data), command)

        let clipboard = WheelChordCommand(
            control: .clipboard,
            source: .corsair,
            phase: .press
        )
        XCTAssertEqual(
            try WheelChordCommand.decodeTopLevel(JSONEncoder().encode(clipboard)),
            clipboard
        )
        let youtube = WheelChordCommand(
            control: .youtubeScrub,
            source: .razer,
            phase: .press
        )
        XCTAssertEqual(
            try WheelChordCommand.decodeTopLevel(JSONEncoder().encode(youtube)),
            youtube
        )

        let utilityOnly = WheelChordCommand(
            control: .brightness,
            source: .corsair,
            phase: .press
        )
        XCTAssertThrowsError(
            try WheelChordCommand.decodeTopLevel(JSONEncoder().encode(utilityOnly))
        )
        let spaces = WheelChordCommand(
            control: .spaces,
            source: .corsair,
            phase: .press
        )
        XCTAssertThrowsError(
            try WheelChordCommand.decodeTopLevel(JSONEncoder().encode(spaces))
        )
    }
}
