import XCTest
@testable import ScimitarKit

/// Ethan: "a better design language around when a button click actually does
/// the button versus when holding it and doing wheel up or wheel down or wand
/// up or wand down changes some value." One grammar on every HUD card:
/// `Click · Hold ↕`, `Hold ↕` when a click does nothing, and no arrow for an
/// ordinary click. These tests pin it to the typed wheel definitions.
final class ModeHUDGestureTests: XCTestCase {
    private let motionGlyphs: Set<Character> = ["↕", "↓", "↑", "↔"]

    // MARK: Canonical metadata

    /// The click half must match what a wheel-free release actually does in
    /// the app shell's wheel-chord release handling.
    func testOnlyControlsWhoseReleaseActsNameAClick() {
        let clicks = Dictionary(uniqueKeysWithValues: WheelChordControl.allCases.compactMap { control in
            control.hudClickTitle.map { (control, $0) }
        })
        XCTAssertEqual(clicks, [
            .clipboard: "Space",
            .mediaTracks: "Next Track",
            .screenshotPaste: "Screenshot",
            .youtubeScrub: "YouTube −5 sec",
            .codexResponseSpeed: "Cycle speed",
        ])
    }

    /// The arrow names the physical direction that acts, derived from the
    /// dispatcher's own `accepts`, never from the Quartz enum label.
    func testMotionArrowIsHonestAboutWhichPhysicalDirectionActs() {
        for control in WheelChordControl.allCases {
            let physicalDown: WheelChordDirection = control.physicalUpDirection == .up ? .down : .up
            switch control.hudMotion {
            case .upDown:
                XCTAssertTrue(control.accepts(control.physicalUpDirection), "\(control)")
                XCTAssertTrue(control.accepts(physicalDown), "\(control)")
            case .down:
                XCTAssertFalse(control.accepts(control.physicalUpDirection), "\(control)")
                XCTAssertTrue(control.accepts(physicalDown), "\(control)")
            case .up, .leftRight:
                XCTFail("\(control) has no upward-only or horizontal mouse wheel")
            }
        }
        // Ethan's accepted one-way gestures are both physical wheel down.
        XCTAssertEqual(WheelChordControl.screenshotPaste.hudMotion, .down)
        XCTAssertEqual(WheelChordControl.applicationWindows.hudMotion, .down)
        XCTAssertEqual(WheelChordControl.codexPin.hudMotion, .upDown, "either direction toggles once")
    }

    func testWandAvailabilityFollowsTheExistingArmThenAdjustLifecycle() {
        for control in WheelChordControl.allCases {
            XCTAssertEqual(control.hudGesture.isAvailableOnWand, control.supportsWandAdjustment, "\(control)")
        }
    }

    // MARK: Default and wand home

    func testCodexSpeedNamesItsMouseClickWithoutChangingTheWand() {
        let card = CodexMode.definition.legend.first { $0.cell == CodexMode.responseSpeedWheelCell }!
        for source in [MouseSource.corsair, .razer] {
            XCTAssertEqual(card.displayTitle(on: source), "Cycle speed · Speed ↕")
            XCTAssertEqual(card.accessibilityDescription(on: source), "Cycle speed. Hold and turn the wheel up or down for Speed")
        }
        XCTAssertEqual(card.displayTitle(on: .wand), "Speed ↕")
    }

    func testCopyPasteSaysSpaceForTheClickOnEverySource() {
        for source in MouseSource.allCases {
            let card = DefaultMapLegend.snapshot(source: source).legend[3]
            XCTAssertEqual(card.cell, .clipboardWheelControl)
            XCTAssertEqual(card.actionTitle, "Space · Copy / Paste")
            XCTAssertEqual(card.displayTitle(on: source), "Space · Copy / Paste ↕", "\(source)")
        }
        let corsair = DefaultMapLegend.snapshot(source: .corsair).legend[3]
        XCTAssertEqual(corsair.accessibilityDescription(on: .corsair),
                       "Space. Hold and turn the wheel up or down for Copy / Paste")
        XCTAssertEqual(corsair.accessibilityDescription(on: .wand),
                       "Space. Hold and tilt up or down for Copy / Paste")
        XCTAssertEqual(corsair.accent, ModeHUDActionFamilyPalette.clipboard, "the clipboard fill is unchanged")
    }

    func testDefaultMixedAndWheelOnlyCardsReadTheSameOnBothMice() {
        for source in [MouseSource.corsair, .razer] {
            let legend = DefaultMapLegend.snapshot(source: source).legend
            XCTAssertEqual(legend[0].displayTitle(on: source), "Horizontal Scroll ↕")
            XCTAssertNil(legend[0].gesture?.click, "a plain click on Horizontal Scroll does nothing")
            XCTAssertEqual(legend[2].displayTitle(on: source), "Screenshot · Paste ↓")
            XCTAssertEqual(legend[5].displayTitle(on: source), "YouTube −5 sec · Hold 2× / Scrub ↕")
            XCTAssertEqual(legend[10].displayTitle(on: source), "Switch App", "the mice keep a plain Switch App")
            XCTAssertNil(legend[10].gesture)
            XCTAssertEqual(legend[9].displayTitle(on: source), "Legend toggle · Hold ⌘", "a hold without motion keeps its words")
        }
    }

    /// The wand can arm only side-effect-free wheel cards, and it moves Switch
    /// App left and right. Its cards claim exactly that.
    func testWandHomeShowsOnlyGesturesTheWandCanPerform() {
        let legend = DefaultMapLegend.snapshot(source: .wand).legend
        // The wand's arrow follows the control's own axis (Ethan, 2026-10-30).
        XCTAssertEqual(legend[0].displayTitle(on: .wand), "Horizontal Scroll ↔")
        XCTAssertEqual(legend[0].displayTitle(on: .corsair), "Horizontal Scroll ↕", "the wheel still turns up and down")
        XCTAssertEqual(legend[2].displayTitle(on: .wand), "Screenshot", "screenshot paste needs the mouse wheel")
        XCTAssertEqual(legend[2].printedControlLabel(on: .wand), "Corsair 3", "its click still works, so no marker")
        XCTAssertEqual(legend[5].displayTitle(on: .wand), "YouTube −5 sec")
        XCTAssertEqual(legend[5].accessibilityDescription(on: .wand), "YouTube −5 sec")
        XCTAssertEqual(legend[10].displayTitle(on: .wand), "Switch App · Choose ↔")
        XCTAssertEqual(legend[10].accessibilityDescription(on: .wand),
                       "Switch App. Hold and tilt left or right for Choose")
        XCTAssertEqual(legend[10].accent, DefaultMapLegend.legend[10].accent, "same Switch App colour as the mice")
    }

    func testScreenshotStatusStatesShowNoGesture() {
        for state in [ScreenshotActionPresentationState.capturing, .copying] {
            let card = DefaultMapLegend.snapshot(source: .corsair, screenshotActionState: state).legend[2]
            XCTAssertNil(card.gesture)
            XCTAssertEqual(card.displayTitle(on: .corsair), ModeHUDCopy.screenshotActionTitle(state: state))
        }
        for state in [ScreenshotActionPresentationState.idle, .pasteReady] {
            let card = DefaultMapLegend.snapshot(source: .corsair, screenshotActionState: state).legend[2]
            XCTAssertEqual(card.displayTitle(on: .corsair), "Screenshot · Paste ↓")
        }
    }

    func testDynamicAppAccentPreservesGestureMetadata() {
        let recolored = ChromeMode.definition.replacingIdentityAccent(with: RGBColor(red: 18, green: 70, blue: 160))
        for original in ChromeMode.definition.legend {
            let updated = recolored.legend.first { $0.cell == original.cell }!
            XCTAssertEqual(updated.gesture, original.gesture)
            XCTAssertEqual(updated.displayTitle(on: .wand), original.displayTitle(on: .wand))
            XCTAssertEqual(updated.displayTitle(on: .corsair), original.displayTitle(on: .corsair))
        }
    }

    // MARK: Every surface

    private var everySurface: [(String, MouseSource, [ModeHUDLegendItem])] {
        var surfaces: [(String, MouseSource, [ModeHUDLegendItem])] = []
        for source in MouseSource.allCases {
            surfaces.append(("Default", source, DefaultMapLegend.snapshot(source: source).legend))
            surfaces.append(("Default YouTube Volume", source,
                             DefaultMapLegend.snapshot(source: source, youtubeVolumeModifierActive: true).legend))
            surfaces.append(("Utility", source, ModePickerCoordinator.modesLegend(for: source)))
            surfaces.append(("Extra Utilities", source, ModePickerCoordinator.extraUtilitiesLegend(for: source)))
            surfaces.append(("Keys", source, ModePickerCoordinator.keysLegend(for: source)))
            for target in AppSpecificTarget.allCases {
                surfaces.append((target.displayName, source, target.definition.legend))
            }
            surfaces.append(("Chrome websites", source, ChromeWebsitesMode.definition.legend))
        }
        return surfaces
    }

    /// No card spells the wheel out in words any more, and only gesture cards
    /// end in a motion arrow.
    func testEveryCardUsesTheSharedGrammar() {
        for (page, source, legend) in everySurface {
            for item in legend {
                let shown = item.displayTitle(on: source)
                XCTAssertFalse(shown.contains("Wheel"), "\(page) \(item.cell) on \(source): \(shown)")
                if let gesture = item.gesture {
                    XCTAssertEqual(item.actionTitle, gesture.words)
                    if gesture.isAvailable(on: source) {
                        XCTAssertEqual(shown, "\(gesture.words) \(gesture.motion.glyph)")
                    } else {
                        XCTAssertFalse(shown.last.map(motionGlyphs.contains) ?? false, "\(page) \(item.cell)")
                    }
                } else {
                    if let modifier = item.heldModifierCell {
                        XCTAssertEqual(shown, "\(item.actionTitle) + Hold \(modifier.displayLabel(on: source))")
                    } else {
                        XCTAssertEqual(shown, item.actionTitle)
                    }
                    XCTAssertFalse(shown.last.map(motionGlyphs.contains) ?? false,
                                   "\(page) \(item.cell): a plain click never ends in a motion arrow")
                }
            }
        }
    }

    /// Each page's wheel cells take their card from the typed control.
    func testEveryHeldWheelCardIsBuiltFromItsControl() {
        for source in MouseSource.allCases {
            for item in ModePickerCoordinator.modesLegend(for: source) {
                XCTAssertEqual(item.gesture, WheelChordControl.utilityControl(for: item.cell)?.hudGesture, "Utility \(item.cell)")
            }
            for item in ModePickerCoordinator.extraUtilitiesLegend(for: source) {
                XCTAssertEqual(item.gesture, WheelChordControl.extraUtilitiesControl(for: item.cell)?.hudGesture,
                               "Extra Utilities \(item.cell)")
            }
            for item in ModePickerCoordinator.keysLegend(for: source) {
                XCTAssertEqual(item.gesture, WheelChordControl.keysControl(for: item.cell)?.hudGesture, "Keys \(item.cell)")
            }
        }
        for target in AppSpecificTarget.allCases {
            for item in target.definition.legend {
                guard let control = WheelChordControl.appSpecificControl(for: target, cell: item.cell) else { continue }
                if control == .claudePin {
                    XCTAssertNil(item.heldModifierCell)
                    XCTAssertEqual(item.displayTitle(on: .wand), "Pin/Unpin ↕")
                } else {
                    XCTAssertEqual(item.gesture, control.hudGesture, "\(target.displayName) \(item.cell)")
                }
            }
        }
        let tracks = ModePickerCoordinator.keysLegend(for: .corsair).first { $0.cell == .mediaTracksWheelControl }!
        XCTAssertEqual(tracks.displayTitle(on: .corsair), "Next Track · Tracks ↕")
        let expose = ModePickerCoordinator.extraUtilitiesLegend(for: .corsair).first { $0.cell == .applicationWindowsWheelControl }!
        XCTAssertEqual(expose.displayTitle(on: .corsair), "App Exposé ↓")
        XCTAssertEqual(expose.displayTitle(on: .wand), "App Exposé ↓")
        let chromeTabs = ChromeMode.definition.legend.first { $0.cell == ChromeModeAction.cycleTabsWithWheel.cell }!
        XCTAssertEqual(chromeTabs.displayTitle(on: .razer), "Tab History ↕")
    }

    /// A wheel-only card the wand cannot adjust does nothing on the wand, so
    /// it carries the existing unavailable marker there and nowhere else.
    func testMouseWheelOnlyCardsAreMarkedUnavailableOnTheWand() {
        let width = ModePickerCoordinator.extraUtilitiesLegend(for: .wand).first { $0.cell == .windowWidthWheelControl }!
        XCTAssertEqual(width.displayTitle(on: .wand), "Width")
        XCTAssertTrue(width.printedControlLabel(on: .wand).hasSuffix(" ×"))
        XCTAssertEqual(width.accessibilityDescription(on: .wand), "Width, mouse wheel only")
        XCTAssertEqual(width.displayTitle(on: .corsair), "Width ↕")
        XCTAssertFalse(width.printedControlLabel(on: .corsair).contains("×"))
        XCTAssertFalse(width.printedControlLabel(on: .razer).contains("×"))
    }

    func testRepairAndUnavailableMarkersKeepTheirMeaning() {
        let pin = ClaudeMode.definition.legend[0]
        XCTAssertEqual(pin.displayTitle(on: .corsair), "Pin/Unpin")
        XCTAssertEqual(pin.printedControlLabel(on: .corsair), "Corsair 1")
        XCTAssertEqual(pin.displayTitle(on: .razer), "Pin/Unpin")
        XCTAssertEqual(pin.printedControlLabel(on: .razer), "Razer 3")
        let effort = ClaudeMode.definition.legend[5]
        XCTAssertEqual(effort.displayTitle(on: .corsair), "Choose effort")
        XCTAssertNil(effort.gesture)
        let codexPin = CodexMode.definition.legend.first { $0.cell == CodexMode.pinToggleCell }!
        XCTAssertNil(codexPin.gesture, "Codex Pin is a single click")
        XCTAssertNil(codexPin.heldModifierCell)
        XCTAssertEqual(codexPin.displayTitle(on: .corsair), "Pin/Unpin")
        XCTAssertEqual(codexPin.displayTitle(on: .razer), "Pin/Unpin")
        XCTAssertEqual(codexPin.accessibilityDescription(on: .razer), "Pin/Unpin")
        XCTAssertEqual(codexPin.displayTitle(on: .wand), "Pin/Unpin")
        XCTAssertEqual(codexPin.withHeldModifier(PhysicalCell(rawValue: 9)!).displayTitle(on: .razer),
                       "Pin/Unpin + Hold Razer 7", "derive the printed number from the actual crosswalk")
    }
}
