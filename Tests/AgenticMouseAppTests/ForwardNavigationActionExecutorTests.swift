@testable import AgenticMouseApp
import XCTest

@MainActor
final class ForwardNavigationActionExecutorTests: XCTestCase {
    func testForwardPostsExactlyOneAuxiliaryClickWhenInputIsAllowed() {
        var postCount = 0
        let executor = ForwardNavigationActionExecutor(
            post: {
                postCount += 1
                return true
            },
            accessibilityTrusted: { true }
        )

        guard case .success = executor.perform() else {
            return XCTFail("an unused physical cell 5 release should send Forward")
        }
        XCTAssertEqual(postCount, 1)
    }

    func testForwardFailsClosedWhenLockedUntrustedOrPostingFails() {
        let blocked = ForwardNavigationActionExecutor(
            post: { XCTFail("locked input must not post"); return true },
            accessibilityTrusted: { true },
            inputAllowed: { false }
        )
        guard case .failure(.inputBlocked) = blocked.perform() else {
            return XCTFail("locked input should reject Forward")
        }

        let untrusted = ForwardNavigationActionExecutor(
            post: { XCTFail("untrusted input must not post"); return true },
            accessibilityTrusted: { false }
        )
        guard case .failure(.accessibilityPermissionMissing) = untrusted.perform() else {
            return XCTFail("untrusted input should reject Forward")
        }

        let failed = ForwardNavigationActionExecutor(
            post: { false },
            accessibilityTrusted: { true }
        )
        guard case .failure(.eventCreationFailed) = failed.perform() else {
            return XCTFail("a failed auxiliary click should be surfaced")
        }
    }
}
