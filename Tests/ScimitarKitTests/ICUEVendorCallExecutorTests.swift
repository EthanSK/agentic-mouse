import XCTest
@testable import ScimitarKit

final class ICUEVendorCallExecutorTests: XCTestCase {
    func testVendorWorkRunsOffTheMainThreadAndReturnsItsValue() {
        let executor = ICUEVendorCallExecutor(timeout: 0.1)
        XCTAssertEqual(executor.perform(fallback: false) { !Thread.isMainThread }, true)
        XCTAssertEqual(executor.perform(fallback: 0) { 42 }, 42)
    }

    func testHungRequestTimesOutRejectsBacklogAndRecoversOnlyAfterCompletion() {
        let executor = ICUEVendorCallExecutor(timeout: 0.03)
        let release = DispatchSemaphore(value: 0)
        let entered = DispatchSemaphore(value: 0)
        let finished = DispatchSemaphore(value: 0)
        let start = Date()
        let result = executor.perform(fallback: -1) {
            entered.signal()
            release.wait()
            finished.signal()
            return 99
        }
        XCTAssertEqual(result, -1)
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.3)
        XCTAssertEqual(entered.wait(timeout: .now() + 0.2), .success)
        for _ in 0..<100 {
            XCTAssertEqual(executor.perform(fallback: -2) { XCTFail("must not queue work behind the hung SDK"); return 0 }, -2)
        }
        release.signal()
        XCTAssertEqual(finished.wait(timeout: .now() + 0.5), .success)
        var recovered = -1
        for _ in 0..<100 where recovered == -1 {
            recovered = executor.perform(fallback: -1) { 7 }
            if recovered == -1 { Thread.sleep(forTimeInterval: 0.001) }
        }
        XCTAssertEqual(recovered, 7)
        XCTAssertEqual(result, -1, "late SDK completion never changes the returned fallback")
    }
}
