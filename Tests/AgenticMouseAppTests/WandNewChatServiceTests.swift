import XCTest
import ScimitarKit
@testable import AgenticMouseApp

@MainActor
final class WandNewChatServiceTests: XCTestCase {
    func testRequestBoundaryRejectsStaleAndMalformedNotifications() {
        let id = UUID().uuidString
        let valid: [AnyHashable: Any] = ["version": 1, "target": "codex", "sentAt": 100.0]
        XCTAssertEqual(WandNewChatRequest.decode(object: id, info: valid, now: 100)?.target, .codex)
        for replacement in ["version": true, "target": "claude", "sentAt": true] as [String: Any] {
            var fields = valid; fields[replacement.key] = replacement.value
            XCTAssertNil(WandNewChatRequest.decode(object: id, info: fields, now: 100))
        }
        XCTAssertNil(WandNewChatRequest.decode(object: id, info: valid, now: 111))
        XCTAssertNil(WandNewChatRequest.decode(object: id, info: valid, now: 97))
        XCTAssertNil(WandNewChatRequest.decode(object: "bad", info: valid, now: 100))
        var expanded = valid; expanded["script"] = "unexpected"
        XCTAssertNil(WandNewChatRequest.decode(object: id, info: expanded, now: 100))
    }

    func testDuplicatePendingRequestCreatesOnceAndCancellationVetoesLateReady() async {
        let request = WandNewChatRequest(id: UUID(), target: .codex)
        var attempts = 0
        var release: CheckedContinuation<Void, Never>?
        var outcomes: [WandNewChatCoordinator.Outcome] = []
        var didActAfterCancel = false
        let coordinator = WandNewChatCoordinator(allowed: { true }) { _, valid in
            attempts += 1
            await withCheckedContinuation { release = $0 }
            if valid() { didActAfterCancel = true }
            return .success(.init(pid: 123))
        }
        coordinator.onResult = { _, result in outcomes.append(result) }
        coordinator.handle(request)
        for _ in 0..<10 { await Task.yield() }
        coordinator.handle(request)
        XCTAssertEqual(attempts, 1)
        coordinator.cancel(request.id)
        release?.resume()
        for _ in 0..<10 { await Task.yield() }
        XCTAssertFalse(didActAfterCancel)
        XCTAssertEqual(outcomes, [.failure(.cancelled)])
        coordinator.handle(request)
        XCTAssertEqual(attempts, 1)
        XCTAssertEqual(outcomes.last, .failure(.cancelled))
    }

    func testCompletedRequestCannotLaunchOrReuseAnOldReadyGrant() async {
        var attempts = 0
        var outcomes: [WandNewChatCoordinator.Outcome] = []
        let coordinator = WandNewChatCoordinator(allowed: { true }) { _, _ in
            attempts += 1; return .success(.init(pid: 123))
        }
        coordinator.onResult = { _, result in outcomes.append(result) }
        let request = WandNewChatRequest(id: UUID(), target: .codex)
        coordinator.handle(request)
        for _ in 0..<10 { await Task.yield() }
        coordinator.handle(request)
        XCTAssertEqual(attempts, 1)
        XCTAssertEqual(outcomes, [.success(.init(pid: 123)), .failure(.alreadyCompleted)])
    }

    func testCancellationBeforeRequestAndInactiveSessionNeverLaunch() async {
        var attempts = 0
        var allowed = true
        let coordinator = WandNewChatCoordinator(allowed: { allowed }) { _, _ in
            attempts += 1; return .failure(.shortcutFailed)
        }
        let request = WandNewChatRequest(id: UUID(), target: .codex)
        coordinator.cancel(request.id)
        coordinator.handle(request)
        allowed = false
        coordinator.handle(.init(id: UUID(), target: .claudeCode))
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(attempts, 0)
    }

    func testHungCreateRenewsProgressThenTimesOutWithoutLateReady() async {
        let clock = ManualClock(), scheduler = ManualTickScheduler()
        var release: CheckedContinuation<Void, Never>?
        var outcomes: [WandNewChatCoordinator.Outcome] = []
        var progress: [Bool] = []
        var actedAfterTimeout = false
        let coordinator = WandNewChatCoordinator(allowed: { true }, scheduler: scheduler, clock: clock) { _, valid in
            await withCheckedContinuation { release = $0 }
            actedAfterTimeout = valid()
            return .success(.init(pid: 123))
        }
        coordinator.onResult = { _, result in outcomes.append(result) }
        coordinator.onProgress = { _, visible in progress.append(visible) }
        coordinator.handle(.init(id: UUID(), target: .codex))
        for _ in 0..<10 { await Task.yield() }
        clock.advance(by: 3); scheduler.fire()
        XCTAssertEqual(progress, [true, true])
        clock.advance(by: 22); scheduler.fire()
        XCTAssertEqual(progress, [true, true, false])
        XCTAssertEqual(outcomes, [.failure(.timedOut)])
        XCTAssertFalse(scheduler.isRunning)
        release?.resume()
        for _ in 0..<10 { await Task.yield() }
        XCTAssertFalse(actedAfterTimeout)
        XCTAssertEqual(outcomes, [.failure(.timedOut)])
    }

    func testClaudeCodeShellUsesFreshSessionAndQuotesLiteralArguments() throws {
        let id = UUID()
        let cwd = "/tmp/a'b $(printf injected)"
        let shell = WandNewChatAdapter.claudeShell(executable: "/tmp/Claude Code", cwd: cwd, id: id)
        XCTAssertTrue(shell.contains(" --session-id '" + id.uuidString + "'"))
        XCTAssertFalse(shell.contains("--resume")); XCTAssertFalse(shell.contains("--continue"))
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "printf '%s' " + WandNewChatAdapter.shellQuote(cwd)]
        let output = Pipe(); process.standardOutput = output
        try process.run(); process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertEqual(String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8), cwd)
    }

    func testClaudeCodeReadinessRejectsTrustLoginAndNonemptyInputs() {
        XCTAssertTrue(WandNewChatAdapter.terminalReady("zsh,claude\u{1f}Claude Code\n❯ \n"))
        XCTAssertFalse(WandNewChatAdapter.terminalReady("zsh,claude\u{1f}❯ 1. Yes, I trust this folder"))
        XCTAssertFalse(WandNewChatAdapter.terminalReady("zsh,claude\u{1f}❯ 1. Log in"))
        XCTAssertFalse(WandNewChatAdapter.terminalReady("zsh,claude\u{1f}❯ user already typed"))
        XCTAssertFalse(WandNewChatAdapter.terminalReady("zsh\u{1f}❯"))
        XCTAssertFalse(WandNewChatAdapter.terminalReady("zsh,claude\u{1f}❯\nTrust this folder?\n❯ 1. Yes, I trust this folder"))
        XCTAssertFalse(WandNewChatAdapter.terminalReady("zsh,claude\u{1f}❯\n❯ already typed"))
    }
}
