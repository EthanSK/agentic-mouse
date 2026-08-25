import Foundation
import XCTest
@testable import AgenticMouseApp

@MainActor
final class VSCodeCommandBridgeTests: XCTestCase {
    private let appURL = URL(fileURLWithPath: "/Applications/Visual Studio Code.app")

    func testBuildsOnlyTheAllowListedBridgeURLs() {
        XCTAssertEqual(
            VSCodeCommandBridge.url(for: .cursorHistoryBack)?.absoluteString,
            "vscode://ethansk.agentic-mouse-vscode-bridge/cursor-history/back"
        )
        XCTAssertEqual(
            VSCodeCommandBridge.url(for: .cursorHistoryForward)?.absoluteString,
            "vscode://ethansk.agentic-mouse-vscode-bridge/cursor-history/forward"
        )
        XCTAssertEqual(
            VSCodeCommandBridge.url(for: .toggleTerminal)?.absoluteString,
            "vscode://ethansk.agentic-mouse-vscode-bridge/terminal/toggle"
        )
    }

    func testOpensBackThroughTheRunningFrontmostVSCodeWithoutActivationRequest() {
        var opened: [(URL, URL)] = []
        var result: Result<Void, VSCodeCommandBridge.BridgeError>?
        let bridge = VSCodeCommandBridge(
            targetResolver: { .init(
                processIdentifier: 314,
                applicationURL: self.appURL,
                isActive: true
            ) },
            openURL: { url, applicationURL, completion in
                opened.append((url, applicationURL))
                completion(nil)
            },
            inputAllowed: { true }
        )

        bridge.perform(.cursorHistoryBack) { result = $0 }

        XCTAssertEqual(opened.count, 1)
        XCTAssertEqual(
            opened.first?.0.absoluteString,
            "vscode://ethansk.agentic-mouse-vscode-bridge/cursor-history/back"
        )
        XCTAssertEqual(opened.first?.1, appURL)
        guard case .success = result else {
            return XCTFail("frontmost VS Code should accept the direct bridge request")
        }
    }

    func testFailsClosedWhenInputIsBlocked() {
        var opened = false
        var result: Result<Void, VSCodeCommandBridge.BridgeError>?
        let bridge = VSCodeCommandBridge(
            targetResolver: { .init(
                processIdentifier: 314,
                applicationURL: self.appURL,
                isActive: true
            ) },
            openURL: { _, _, _ in opened = true },
            inputAllowed: { false }
        )

        bridge.perform(.cursorHistoryBack) { result = $0 }

        XCTAssertFalse(opened)
        guard case .failure(let error) = result else {
            return XCTFail("locked input must reject the bridge request")
        }
        XCTAssertEqual(
            error.description,
            "Mouse commands are disabled while macOS is locked"
        )
    }

    func testFailsClosedUnlessVSCodeIsFrontmost() {
        var opened = false
        var result: Result<Void, VSCodeCommandBridge.BridgeError>?
        let bridge = VSCodeCommandBridge(
            targetResolver: { .init(
                processIdentifier: 314,
                applicationURL: self.appURL,
                isActive: false
            ) },
            openURL: { _, _, _ in opened = true },
            inputAllowed: { true }
        )

        bridge.perform(.cursorHistoryForward) { result = $0 }

        XCTAssertFalse(opened)
        guard case .failure(let error) = result else {
            return XCTFail("background VS Code must reject Cursor History")
        }
        XCTAssertEqual(error.description, "VS Code must be frontmost for Cursor History")

        var terminalResult: Result<Void, VSCodeCommandBridge.BridgeError>?
        bridge.perform(.toggleTerminal) { terminalResult = $0 }
        guard case .failure(let terminalError) = terminalResult else {
            return XCTFail("background VS Code must reject Toggle Terminal")
        }
        XCTAssertEqual(terminalError.description, "VS Code must be frontmost for Toggle Terminal")
    }

    func testReportsMissingVSCodeAndWorkspaceOpenFailuresHonestly() {
        var missing: Result<Void, VSCodeCommandBridge.BridgeError>?
        VSCodeCommandBridge(
            targetResolver: { nil },
            openURL: { _, _, _ in XCTFail("missing VS Code must not open a URI") },
            inputAllowed: { true }
        ).perform(.cursorHistoryBack) { missing = $0 }
        guard case .failure(let missingError) = missing else {
            return XCTFail("missing VS Code should fail")
        }
        XCTAssertEqual(missingError.description, "VS Code is not running")

        struct OpenFailure: LocalizedError {
            var errorDescription: String? { "URI rejected" }
        }
        var rejected: Result<Void, VSCodeCommandBridge.BridgeError>?
        VSCodeCommandBridge(
            targetResolver: { .init(
                processIdentifier: 314,
                applicationURL: self.appURL,
                isActive: true
            ) },
            openURL: { _, _, completion in completion(OpenFailure()) },
            inputAllowed: { true }
        ).perform(.cursorHistoryForward) { rejected = $0 }
        guard case .failure(let rejectedError) = rejected else {
            return XCTFail("workspace open failure should be reported")
        }
        XCTAssertEqual(
            rejectedError.description,
            "Could not reach the VS Code bridge: URI rejected"
        )
    }
}
