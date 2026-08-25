import AppKit
import ScimitarKit
@testable import ScimitarUI
import XCTest

@MainActor
final class ModeHUDAppBackdropTests: XCTestCase {
    func testExactRunningApplicationPathWinsOverBundleLookup() throws {
        let exactPath = "/Applications/Exact.app"
        var lookedUpBundleIdentifiers: [String] = []
        var loadedPaths: [String] = []
        let provider = WorkspaceModeHUDAppIconProvider(
            fileExists: { $0 == exactPath },
            applicationURLForBundleIdentifier: {
                lookedUpBundleIdentifiers.append($0)
                return URL(fileURLWithPath: "/Applications/Fallback.app")
            },
            iconForFile: {
                loadedPaths.append($0)
                return NSImage(size: NSSize(width: 32, height: 32))
            }
        )

        let icon = provider.icon(for: try XCTUnwrap(ModeHUDAppBackdrop(
            bundleIdentifier: "com.example.Exact",
            applicationPath: exactPath
        )))

        XCTAssertNotNil(icon)
        XCTAssertEqual(lookedUpBundleIdentifiers, [])
        XCTAssertEqual(loadedPaths, [exactPath])
        XCTAssertEqual(icon?.size, NSSize(width: 512, height: 512))
    }

    func testConfiguredTargetFallsBackToItsCanonicalBundleIdentifier() throws {
        var loadedPaths: [String] = []
        let provider = WorkspaceModeHUDAppIconProvider(
            fileExists: { _ in false },
            applicationURLForBundleIdentifier: { bundleIdentifier in
                XCTAssertEqual(bundleIdentifier, "com.example.Configured")
                return URL(fileURLWithPath: "/Applications/Configured.app")
            },
            iconForFile: {
                loadedPaths.append($0)
                return NSImage(size: NSSize(width: 32, height: 32))
            }
        )

        XCTAssertNotNil(provider.icon(for: try XCTUnwrap(ModeHUDAppBackdrop(
            bundleIdentifier: "com.example.Configured"
        ))))
        XCTAssertEqual(loadedPaths, ["/Applications/Configured.app"])
    }

    func testResolvedIconIsCachedByStableAppIdentity() throws {
        var loads = 0
        let provider = WorkspaceModeHUDAppIconProvider(
            fileExists: { _ in false },
            applicationURLForBundleIdentifier: { _ in
                URL(fileURLWithPath: "/Applications/Cached.app")
            },
            iconForFile: { _ in
                loads += 1
                return NSImage(size: NSSize(width: 32, height: 32))
            }
        )
        let backdrop = try XCTUnwrap(ModeHUDAppBackdrop(
            bundleIdentifier: "com.example.Cached"
        ))

        XCTAssertNotNil(provider.icon(for: backdrop))
        XCTAssertNotNil(provider.icon(for: backdrop))
        _ = provider.accent(for: backdrop)
        XCTAssertEqual(loads, 1)
    }

    func testAutomaticAndManualIdentitiesShareTheResolvedPathCache() throws {
        let path = "/Applications/Shared.app"
        var loads = 0
        let provider = WorkspaceModeHUDAppIconProvider(
            fileExists: { $0 == path },
            applicationURLForBundleIdentifier: { _ in URL(fileURLWithPath: path) },
            iconForFile: { _ in
                loads += 1
                return self.image { bounds in
                    NSColor.systemBlue.setFill()
                    bounds.fill()
                }
            }
        )
        let automatic = try XCTUnwrap(ModeHUDAppBackdrop(
            bundleIdentifier: "com.example.Shared",
            applicationPath: path
        ))
        let manual = try XCTUnwrap(ModeHUDAppBackdrop(
            bundleIdentifier: "com.example.Shared"
        ))

        XCTAssertNotNil(provider.accent(for: automatic))
        XCTAssertNotNil(provider.icon(for: manual))
        XCTAssertEqual(loads, 1)
    }

    func testRepresentativeAccentPrefersChromaticIdentityOverWhiteIconBackground() throws {
        let image = image { bounds in
            NSColor.white.setFill()
            bounds.fill()
            NSColor(calibratedRed: 0.08, green: 0.74, blue: 0.25, alpha: 1).setFill()
            NSRect(x: 0, y: 0, width: bounds.width * 0.28, height: bounds.height).fill()
        }

        let accent = try XCTUnwrap(
            ModeHUDAppIconAccentExtractor.representativeAccent(from: image)
        )

        XCTAssertGreaterThan(accent.green, accent.red)
        XCTAssertGreaterThan(accent.green, accent.blue)
        XCTAssertGreaterThanOrEqual(accent.green, 184)
        XCTAssertEqual(accent.alpha, 255)
    }

    func testRepresentativeAccentKeepsNeutralIconsLegible() throws {
        let image = image { bounds in
            NSColor(calibratedWhite: 0.04, alpha: 1).setFill()
            bounds.fill()
        }

        let accent = try XCTUnwrap(
            ModeHUDAppIconAccentExtractor.representativeAccent(from: image)
        )

        XCTAssertEqual(accent.red, accent.green)
        XCTAssertEqual(accent.green, accent.blue)
        XCTAssertGreaterThanOrEqual(accent.red, 140)
    }

    func testAppBackdropUsesSharperRecognisableTreatment() {
        XCTAssertEqual(ModeHUDAppBackdropMetrics.scale, 1.14)
        XCTAssertEqual(ModeHUDAppBackdropMetrics.blurRadius, 8)
    }

    func testViewModelResolvesOnlyDecoratedSlotsAndClearsThemOnNextSnapshot() throws {
        let expectedIcon = NSImage(size: NSSize(width: 32, height: 32))
        let provider = RecordingAppIconProvider(icon: expectedIcon)
        let model = ModeHUDViewModel(source: .corsair, appIconProvider: provider)
        let backdrop = try XCTUnwrap(ModeHUDAppBackdrop(
            bundleIdentifier: "com.example.App"
        ))

        model.apply(snapshot(appBackdrop: backdrop))
        XCTAssertTrue(model.appIcons[PhysicalCell(rawValue: 2)!] === expectedIcon)
        XCTAssertEqual(model.appIcons.count, 1)
        XCTAssertEqual(provider.requests, [backdrop])

        model.apply(snapshot(appBackdrop: nil))
        XCTAssertTrue(model.appIcons.isEmpty)
    }

    private func snapshot(appBackdrop: ModeHUDAppBackdrop?) -> ModeHUDSnapshot {
        ModeHUDSnapshot(
            isActive: true,
            modeTitle: "Example mode",
            source: .corsair,
            selection: nil,
            legend: [
                ModeHUDLegendItem(
                    cell: PhysicalCell(rawValue: 1)!,
                    actionTitle: "Ordinary",
                    accent: RGBColor(red: 120, green: 120, blue: 120)
                ),
                ModeHUDLegendItem(
                    cell: PhysicalCell(rawValue: 2)!,
                    actionTitle: "Example mode",
                    accent: RGBColor(red: 0, green: 132, blue: 255),
                    destinationModeAccent: RGBColor(red: 0, green: 132, blue: 255),
                    appBackdrop: appBackdrop
                ),
            ],
            accent: RGBColor(red: 0, green: 132, blue: 255),
            footerTitle: "Example mode",
            presentationStyle: .boldOpaque,
            showsOnAllDisplays: true
        )
    }

    private func image(
        drawing: @escaping (NSRect) -> Void
    ) -> NSImage {
        NSImage(
            size: NSSize(width: 64, height: 64),
            flipped: false,
            drawingHandler: { bounds in
                drawing(bounds)
                return true
            }
        )
    }
}

private final class RecordingAppIconProvider: ModeHUDAppIconProviding {
    let iconValue: NSImage
    private(set) var requests: [ModeHUDAppBackdrop] = []

    init(icon: NSImage) {
        iconValue = icon
    }

    func icon(for backdrop: ModeHUDAppBackdrop) -> NSImage? {
        requests.append(backdrop)
        return iconValue
    }
}
