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
        XCTAssertEqual(
            VSCodeCommandBridge.url(for: .addToChat)?.absoluteString,
            "vscode://ethansk.agentic-mouse-vscode-bridge/codex/add-to-chat"
        )
    }

    func testOpensBackThroughTheRunningFrontmostVSCodeWithoutActivationRequest() async {
        var opened: [(URL, URL)] = []
        var result: Result<Void, VSCodeCommandBridge.BridgeError>?
        let completed = expectation(description: "bridge request completed")
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

        bridge.perform(.cursorHistoryBack) {
            result = $0
            completed.fulfill()
        }
        await fulfillment(of: [completed], timeout: 1)

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

    func testAddToChatUsesTheRetainedVSCodeSelectionWithoutActivatingVSCode() async {
        var openedURL: URL?
        var result: Result<Void, VSCodeCommandBridge.BridgeError>?
        let completed = expectation(description: "background Add to chat completed")
        let bridge = VSCodeCommandBridge(
            targetResolver: { .init(
                processIdentifier: 314,
                applicationURL: self.appURL,
                isActive: false
            ) },
            openURL: { url, _, completion in
                openedURL = url
                completion(nil)
            },
            inputAllowed: { true }
        )

        bridge.perform(.addToChat) {
            result = $0
            completed.fulfill()
        }
        await fulfillment(of: [completed], timeout: 1)

        XCTAssertEqual(
            openedURL?.absoluteString,
            "vscode://ethansk.agentic-mouse-vscode-bridge/codex/add-to-chat"
        )
        guard case .success = result else {
            return XCTFail("Add to chat should preserve the background VS Code selection")
        }
    }

    func testReportsMissingVSCodeAndWorkspaceOpenFailuresHonestly() async {
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
        let rejectedCompletion = expectation(description: "rejected bridge request completed")
        VSCodeCommandBridge(
            targetResolver: { .init(
                processIdentifier: 314,
                applicationURL: self.appURL,
                isActive: true
            ) },
            openURL: { _, _, completion in completion(OpenFailure()) },
            inputAllowed: { true }
        ).perform(.cursorHistoryForward) {
            rejected = $0
            rejectedCompletion.fulfill()
        }
        await fulfillment(of: [rejectedCompletion], timeout: 1)
        guard case .failure(let rejectedError) = rejected else {
            return XCTFail("workspace open failure should be reported")
        }
        XCTAssertEqual(
            rejectedError.description,
            "Could not reach the VS Code bridge: URI rejected"
        )
    }

    func testReturnsBackgroundWorkspaceCompletionToTheMainThread() async {
        let completed = expectation(description: "background bridge request completed")
        let bridge = VSCodeCommandBridge(
            targetResolver: { .init(
                processIdentifier: 314,
                applicationURL: self.appURL,
                isActive: true
            ) },
            openURL: { _, _, completion in
                DispatchQueue.global().async { completion(nil) }
            },
            inputAllowed: { true }
        )

        bridge.perform(.cursorHistoryBack) { result in
            XCTAssertTrue(Thread.isMainThread)
            guard case .success = result else {
                return XCTFail("the background workspace completion should still succeed")
            }
            completed.fulfill()
        }

        await fulfillment(of: [completed], timeout: 1)
    }
}
