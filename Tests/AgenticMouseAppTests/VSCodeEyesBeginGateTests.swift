// Qualify the one-session gate without touching real Code hosts or Karabiner.
import Foundation
import ScimitarKit
import XCTest
@testable import AgenticMouseApp

@MainActor
final class VSCodeEyesBeginGateTests: XCTestCase {
    func testRealHostChildSpawnKeepsAdmissionAndHostExitStillRevokes() async throws {
        let code = Process(), host = Process(), input = Pipe(), output = Pipe()
        code.executableURL = URL(fileURLWithPath: "/bin/sleep"); code.arguments = ["30"]
        host.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        host.arguments = ["-c", "import os,sys\nprint('ready',flush=True)\nsys.stdin.readline()\npid=os.fork()\nif pid==0: os._exit(0)\nos.waitpid(pid,0)\nprint('spawned',flush=True)\nsys.stdin.readline()"]
        host.standardInput = input; host.standardOutput = output; host.standardError = FileHandle.nullDevice
        let hostReady = expectation(description: "host finished interpreter startup")
        output.fileHandleForReading.readabilityHandler = { handle in
            if !handle.availableData.isEmpty { handle.readabilityHandler = nil; hostReady.fulfill() }
        }
        try code.run(); try host.run()
        defer {
            output.fileHandleForReading.readabilityHandler = nil
            for process in [host, code] { if process.isRunning { process.terminate() }; process.waitUntilExit() }
        }
        await fulfillment(of: [hostReady], timeout: 3)
        let registered = expectation(description: "all kernel process watches registered")
        registered.expectedFulfillmentCount = 3
        let forked = expectation(description: "independent observer saw actual child creation")
        let childFinished = expectation(description: "real child finished")
        let witness = DispatchSource.makeProcessSource(identifier: host.processIdentifier, eventMask: .fork, queue: .main)
        witness.setRegistrationHandler { registered.fulfill() }
        witness.setEventHandler { forked.fulfill(); witness.cancel() }; witness.resume()
        defer { witness.cancel() }
        let lease = GateLease()
        let gate = VSCodeEyesBeginGate(lease: lease, scheduler: ManualTickScheduler(),
            allowed: { true }, validate: { _, _ in true }, watch: { pid, events, changed in
                let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: events, queue: .main)
                source.setRegistrationHandler { registered.fulfill() }
                source.setEventHandler { MainActor.assumeIsolated { changed() } }; source.resume()
                return { source.cancel() }
            })
        let enable = try VSCodeEyesBeginGate.Command.decode(JSONSerialization.data(withJSONObject: [
            "command": "agentic_mouse_vscode_eyes_begin_gate", "enabled": true,
            "code_pid": code.processIdentifier, "host_pids": [host.processIdentifier],
        ]))
        XCTAssertTrue(gate.handle(enable))
        await fulfillment(of: [registered], timeout: 3)
        output.fileHandleForReading.readabilityHandler = { handle in
            if !handle.availableData.isEmpty { handle.readabilityHandler = nil; childFinished.fulfill() }
        }
        input.fileHandleForWriting.write(Data("spawn\n".utf8))
        await fulfillment(of: [forked, childFinished], timeout: 3)
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        XCTAssertTrue(gate.isEnabled, "Routine host children must not revoke admission")
        let exited = expectation(description: "actual host replacement still revokes admission")
        lease.onDeactivate = { if lease.activations > 0 { exited.fulfill() } }
        host.terminate()
        await fulfillment(of: [exited], timeout: 3)
        XCTAssertFalse(gate.isEnabled)
        lease.onDeactivate = nil
    }

    func testRoutineExtensionHostChildrenCannotInvalidateAdmission() throws {
        var masks: [Int32: DispatchSource.ProcessEvent] = [:]
        let gate = VSCodeEyesBeginGate(lease: GateLease(), scheduler: ManualTickScheduler(),
            allowed: { true }, validate: { _, _ in true },
            watch: { pid, events, _ in masks[pid] = events; return {} })
        XCTAssertTrue(gate.handle(try command(true)))
        XCTAssertEqual(masks[111], [.fork, .exec, .exit])
        for pid: Int32 in [222, 333] {
            XCTAssertEqual(masks[pid], [.exec, .exit])
            XCTAssertFalse(masks[pid]?.contains(.fork) == true,
                "Routine Git/language-worker child creation must neither drop the lease nor trigger qualification")
        }
        XCTAssertTrue(gate.isEnabled)
    }

    func testRealProcessExitRevokesTheLeaseWithoutWaitingForHeartbeat() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["30"]
        try process.run()
        defer { if process.isRunning { process.terminate() }; process.waitUntilExit() }
        let lease = GateLease()
        let revoked = expectation(description: "kernel process-exit event revoked gate")
        lease.onDeactivate = { if lease.activations > 0 { revoked.fulfill() } }
        let gate = VSCodeEyesBeginGate(lease: lease, scheduler: ManualTickScheduler(),
            allowed: { true }, validate: { _, _ in true })
        let enable = try VSCodeEyesBeginGate.Command.decode(JSONSerialization.data(withJSONObject: [
            "command": "agentic_mouse_vscode_eyes_begin_gate", "enabled": true,
            "code_pid": process.processIdentifier, "host_pids": [ProcessInfo.processInfo.processIdentifier],
        ]))
        XCTAssertTrue(gate.handle(enable))
        process.terminate()
        await fulfillment(of: [revoked], timeout: 3)
        XCTAssertFalse(gate.isEnabled)
        lease.onDeactivate = nil
        gate.reset()
    }

    func testGateIsOffUntilExplicitProofAndResetsOnHostReplacement() throws {
        let lease = GateLease()
        let scheduler = ManualTickScheduler()
        var callbacks: [Int32: @MainActor () -> Void] = [:]
        var cancels = 0
        var allowed = true
        let gate = VSCodeEyesBeginGate(lease: lease, scheduler: scheduler,
            allowed: { allowed }, validate: { $0 == 111 && $1 == [222, 333] },
            watch: { pid, _, changed in callbacks[pid] = changed; return { cancels += 1 } })
        let enable = try command(true)
        XCTAssertFalse(gate.isEnabled)
        XCTAssertEqual(lease.activations, 0)
        XCTAssertTrue(gate.handle(enable))
        XCTAssertTrue(gate.isEnabled)
        XCTAssertEqual(Set(callbacks.keys), [111, 222, 333])
        scheduler.fire()
        XCTAssertEqual(lease.renewals, 1)
        let oldCallback = try XCTUnwrap(callbacks[222])
        oldCallback()
        XCTAssertFalse(gate.isEnabled)
        XCTAssertEqual(cancels, 3)
        XCTAssertTrue(gate.handle(enable))
        oldCallback() // An old session must not revoke a newer admitted session.
        XCTAssertTrue(gate.isEnabled)
        allowed = false
        scheduler.fire()
        XCTAssertFalse(gate.isEnabled)
        XCTAssertFalse(gate.handle(enable))
        XCTAssertTrue(gate.handle(try command(false)))
    }

    func testMalformedOrUnwatchedHostsNeverEnableAndLeaseErrorsFailClosed() throws {
        let lease = GateLease()
        let scheduler = ManualTickScheduler()
        let gate = VSCodeEyesBeginGate(lease: lease, scheduler: scheduler,
            allowed: { true }, validate: { _, _ in true }, watch: { _, _, _ in nil })
        XCTAssertFalse(gate.handle(try command(true)))
        XCTAssertFalse(gate.isEnabled)
        for hosts: [Int32] in [[], [222, 222], [111], [0]] {
            XCTAssertFalse(gate.handle(try command(true, hosts: hosts)))
        }
        let working = VSCodeEyesBeginGate(lease: lease, scheduler: scheduler,
            allowed: { true }, validate: { _, _ in true }, watch: { _, _, _ in {} })
        lease.fails = true
        XCTAssertFalse(working.handle(try command(true)))
        XCTAssertFalse(working.isEnabled)
        XCTAssertFalse(scheduler.isRunning)
    }

    private func command(_ enabled: Bool, hosts: [Int32] = [222, 333]) throws -> VSCodeEyesBeginGate.Command {
        try .decode(JSONSerialization.data(withJSONObject: [
            "command": "agentic_mouse_vscode_eyes_begin_gate", "enabled": enabled,
            "code_pid": 111, "host_pids": hosts,
        ]))
    }
}

private final class GateLease: ColorProofLeaseControlling {
    var activations = 0, renewals = 0, deactivations = 0
    var fails = false
    var onDeactivate: (() -> Void)?
    func activate() throws { if fails { throw NSError(domain: "test", code: 1) }; activations += 1 }
    func renew() throws { if fails { throw NSError(domain: "test", code: 1) }; renewals += 1 }
    func deactivate() { deactivations += 1; onDeactivate?() }
}
