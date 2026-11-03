// Check running-host proof and event-driven recovery with private test receipts.
import Foundation
import ScimitarKit
import XCTest
@testable import AgenticMouseApp

final class VSCodeEyesHostReceiptTests: XCTestCase {
    private let app = URL(fileURLWithPath: "/Applications/Visual Studio Code.app")
    private let activation = "CA13C361-A19C-4FCE-9CBC-8092F6776753"
    private let codeStart = "Fri Oct 30 16:22:21 2026"
    private let hostStart = "Tue Nov 3 00:04:30 2026"

    private func payload(host: Int32 = 222) -> [String: Any] {
        ["schemaVersion": 1, "extensionVersion": "1.2.147", "capabilities": ["atomic-default-eyes-begin-v1"],
         "activationId": activation, "hostPid": host, "hostStartTime": hostStart,
         "codePid": 111, "codeStartTime": codeStart]
    }

    private func decode(_ value: [String: Any], filename: String? = nil) throws -> VSCodeEyesHostReceipts.Receipt? {
        VSCodeEyesHostReceipts.Receipt.decode(try JSONSerialization.data(withJSONObject: value),
            filename: filename ?? "\(value["hostPid"]!)-\(activation).json")
    }

    func testStatusAndUTCStartParsingPreservePathsContainingSpaces() {
        XCTAssertEqual(VSCodeEyesHostReceipts.hostPIDs(status: "0 1 444 window [1] (File)\n0 1 555 window [2] (File)\n  3 495395959011 222 extension-host [1]\n 1 100 333 extension-host [2]"), [222, 333])
        XCTAssertNil(VSCodeEyesHostReceipts.hostPIDs(status: "0 1 444 window [1]\n0 1 555 window [2]\n0 1 222 extension-host [1]"), "A starting window without its host cannot inherit another window's proof")
        XCTAssertNil(VSCodeEyesHostReceipts.hostPIDs(status: "0 1 222 renderer [1]"))
        XCTAssertNil(VSCodeEyesHostReceipts.hostPIDs(status: "0 1 222 extension-host [1]\n0 1 222 extension-host [2]"))
        let processes = VSCodeEyesHostReceipts.processes(" 111  Fri Oct 30 16:22:21 2026     \(app.path)/Contents/MacOS/Code\n222 Tue Nov  3 00:04:30 2026     \(app.path)/Contents/Frameworks/Code Helper (Plugin).app/Contents/MacOS/Code Helper (Plugin)")
        XCTAssertEqual(processes[111]?.path, app.path + "/Contents/MacOS/Code", "macOS ps pads the executable column; padding is not part of the path")
        XCTAssertEqual(processes[222]?.path, app.path + "/Contents/Frameworks/Code Helper (Plugin).app/Contents/MacOS/Code Helper (Plugin)")
        XCTAssertEqual(processes[222]?.startTime, hostStart)
        XCTAssertTrue(processes[222]?.path.hasSuffix("Code Helper (Plugin)") == true)
    }

    func testReceiptRejectsMalformedUnsupportedAndMismatchedIdentity() throws {
        XCTAssertNotNil(try decode(payload()))
        for (key, bad) in [("schemaVersion", 2 as Any), ("extensionVersion", "1.2.145"),
                           ("extensionVersion", "1.2.147.extra"), ("capabilities", []),
                           ("hostPid", 0), ("activationId", "not-a-uuid")] {
            var value = payload(); value[key] = bad
            XCTAssertNil(try decode(value), key)
        }
        XCTAssertNil(try decode(payload(), filename: "333-\(activation).json"))
        XCTAssertNil(VSCodeEyesHostReceipts.Receipt.decode(Data(repeating: 32, count: 8193), filename: "222-\(activation).json"))
    }

    func testEveryActualHostNeedsItsOwnLivePIDStartAndCodeIdentity() throws {
        let code = VSCodeEyesHostProof.ProcessIdentity(pid: 111, startTime: codeStart, path: app.path + "/Contents/MacOS/Code")
        let host = VSCodeEyesHostProof.ProcessIdentity(pid: 222, startTime: hostStart, path: app.path + "/Contents/Frameworks/Code Helper (Plugin)")
        let other = VSCodeEyesHostProof.ProcessIdentity(pid: 333, startTime: hostStart, path: host.path)
        let target = VSCodeEyesHostReceipts.Target(pid: 111, appURL: app)
        let receipts = [try XCTUnwrap(decode(payload()))]
        XCTAssertNotNil(VSCodeEyesHostReceipts.qualify(target: target, hosts: [222], processes: [111: code, 222: host], receipts: receipts))
        XCTAssertNil(VSCodeEyesHostReceipts.qualify(target: target, hosts: [222, 333], processes: [111: code, 222: host, 333: other], receipts: receipts), "One upgraded window cannot qualify an older second host")
        let reused = VSCodeEyesHostProof.ProcessIdentity(pid: 222, startTime: "Tue Nov 3 01:00:00 2026", path: host.path)
        XCTAssertNil(VSCodeEyesHostReceipts.qualify(target: target, hosts: [222], processes: [111: code, 222: reused], receipts: receipts))
        let foreign = VSCodeEyesHostProof.ProcessIdentity(pid: 222, startTime: hostStart, path: "/bin/other")
        XCTAssertNil(VSCodeEyesHostReceipts.qualify(target: target, hosts: [222], processes: [111: code, 222: foreign], receipts: receipts))
        let replacedCode = VSCodeEyesHostProof.ProcessIdentity(pid: 111, startTime: "Tue Nov 3 02:00:00 2026", path: code.path)
        XCTAssertNil(VSCodeEyesHostReceipts.qualify(target: target, hosts: [222], processes: [111: replacedCode, 222: host], receipts: receipts))
    }

    func testFiniteProcessReaderUsesTheContractsLocaleAndTimezone() throws {
        let reader = VSCodeEyesProcessReader()
        let executable = URL(fileURLWithPath: "/usr/bin/printenv")
        // BSD printenv accepts one name; extra names are silently ignored.
        XCTAssertEqual(try reader.run(executable, ["LC_ALL"]), "C\n")
        XCTAssertEqual(try reader.run(executable, ["TZ"]), "UTC\n")
        XCTAssertEqual(try reader.run(executable, ["VSCODE_CLI"]), "1\n")
        let environment = try reader.run(URL(fileURLWithPath: "/usr/bin/env"), [])
        let keys = Set(environment.split(separator: "\n").map { String($0.split(separator: "=", maxSplits: 1)[0]) })
        XCTAssertEqual(keys, ["PATH", "HOME", "USER", "LOGNAME", "TMPDIR", "LC_ALL", "LANG", "TZ", "VSCODE_CLI"],
            "A read-only CLI must not inherit credentials or another app's bootstrap environment")
    }

    func testReaderChecksPermissionsAndIgnoresStaleMalformedOrSymlinkFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("eyes-receipts-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("222-\(activation).json")
        try JSONSerialization.data(withJSONObject: payload()).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        let target = VSCodeEyesHostReceipts.Target(pid: 111, appURL: app)
        let run: (URL, [String]) throws -> String = { executable, _ in
            if executable.lastPathComponent == "code" { return "0 10 444 window [1]\n0 10 222 extension-host [1]" }
            return "111 Fri Oct 30 16:22:21 2026 \(self.app.path)/Contents/MacOS/Code\n222 Tue Nov 3 00:04:30 2026 \(self.app.path)/Contents/Frameworks/Code Helper (Plugin)"
        }
        XCTAssertNotNil(VSCodeEyesHostReceipts.read(target: target, directory: directory, run: run))
        try Data("invalid".utf8).write(to: directory.appendingPathComponent("invalid.json"))
        XCTAssertNotNil(VSCodeEyesHostReceipts.read(target: target, directory: directory, run: run))
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        XCTAssertNil(VSCodeEyesHostReceipts.read(target: target, directory: directory, run: run))
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: directory.appendingPathComponent("invalid.json"))
        XCTAssertNil(VSCodeEyesHostReceipts.read(target: target, directory: directory, run: run))
    }
}

@MainActor
final class VSCodeEyesReceiptObserverTests: XCTestCase {
    func testStatusHelperLaunchAndTerminationDoNotInvalidateTheirOwnQuery() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("eyes-helper-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let lease = ReceiptLease(), admitted = expectation(description: "one query admits the real host")
        let counter = ReceiptReadCounter()
        var targetAvailable = true
        lease.onActivate = { admitted.fulfill() }
        let gate = VSCodeEyesBeginGate(lease: lease, scheduler: ManualTickScheduler(), allowed: { true },
            validate: { _, _ in true }, watch: { _, _, _ in {} })
        let proof = VSCodeEyesHostProof(code: .init(pid: 111, startTime: "code", path: "code"),
            hosts: [.init(pid: 222, startTime: "host", path: "host")])
        let observer = VSCodeEyesReceiptObserver(gate: gate, directory: directory,
            allowed: { true }, onStatus: { _ in }, targetProvider: {
                targetAvailable ? .init(pid: 111, appURL: URL(fileURLWithPath: "/test/Code.app")) : nil
            }, readProof: { _, _ in counter.increment(); return proof }, observeCode: { _, _, _ in {} })
        defer { lease.onActivate = nil; observer.stop() }
        observer.start()
        observer.applicationChanged(pid: 999, activated: false)
        observer.applicationChanged(pid: 999, activated: false)
        await fulfillment(of: [admitted], timeout: 3)
        XCTAssertTrue(gate.isEnabled)
        XCTAssertEqual(counter.value, 1, "Code's own status helper must not cause another status query")
        targetAvailable = false
        observer.applicationChanged(pid: 999, activated: true)
        XCTAssertFalse(gate.isEnabled, "Activating another main must revoke admission before discovering its hosts")
    }

    func testDirectoryEventsAndUnlockRestoreAdmissionWithoutAManualEnable() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("eyes-observer-\(UUID())")
        let directory = root.appendingPathComponent("BetterGit/active-hosts")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let marker = directory.appendingPathComponent("supported")
        let firstRead = expectation(description: "startup observes no qualifying receipt")
        firstRead.assertForOverFulfill = false
        let lease = ReceiptLease()
        var allowed = true
        var status: ((Bool) -> Void)?
        var callbacks: [Int32: @MainActor () -> Void] = [:]
        let gate = VSCodeEyesBeginGate(lease: lease, scheduler: ManualTickScheduler(), allowed: { allowed },
            validate: { _, _ in true }, watch: { pid, _, changed in callbacks[pid] = changed; return {} })
        let proof = VSCodeEyesHostProof(code: .init(pid: 111, startTime: "code", path: "code"), hosts: [.init(pid: 222, startTime: "host", path: "host")])
        let observer = VSCodeEyesReceiptObserver(gate: gate, directory: directory, allowed: { allowed }, onStatus: { status?($0) },
            targetProvider: { .init(pid: 111, appURL: URL(fileURLWithPath: "/test/Code.app")) },
            readProof: { _, _ in
                guard FileManager.default.fileExists(atPath: marker.path) else { firstRead.fulfill(); return nil }
                return proof
            }, observeCode: { _, _, _ in {} })
        defer { observer.stop() }
        observer.start()
        await fulfillment(of: [firstRead], timeout: 3)
        let initial = expectation(description: "directory event enables qualified hosts")
        lease.onActivate = { initial.fulfill() }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data().write(to: marker, options: .atomic)
        await fulfillment(of: [initial], timeout: 3)
        XCTAssertTrue(gate.isEnabled)
        let fork = expectation(description: "same supported hosts requalify after unrelated fork")
        lease.onActivate = { fork.fulfill() }
        callbacks[222]?()
        await fulfillment(of: [fork], timeout: 3)
        XCTAssertTrue(gate.isEnabled)
        allowed = false; observer.invalidate()
        XCTAssertFalse(gate.isEnabled)
        let unlock = expectation(description: "unlock restores fresh proof")
        lease.onActivate = { unlock.fulfill() }
        allowed = true; observer.refresh()
        await fulfillment(of: [unlock], timeout: 3)
        XCTAssertTrue(gate.isEnabled)
        lease.onActivate = nil
        let replacement = expectation(description: "directory replacement revokes obsolete proof")
        replacement.assertForOverFulfill = false
        status = { if !$0 { replacement.fulfill() } }
        try FileManager.default.moveItem(at: directory, to: root.appendingPathComponent("old-hosts"))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        await fulfillment(of: [replacement], timeout: 3)
        XCTAssertFalse(gate.isEnabled)
        let restored = expectation(description: "replacement directory is watched for a fresh receipt")
        lease.onActivate = { restored.fulfill() }
        try Data().write(to: marker, options: .atomic)
        await fulfillment(of: [restored], timeout: 3)
        XCTAssertTrue(gate.isEnabled)
        lease.onActivate = nil; status = nil
    }
}

private final class ReceiptLease: ColorProofLeaseControlling {
    var onActivate: (() -> Void)?
    func activate() throws { onActivate?() }
    func renew() throws {}
    func deactivate() {}
}

private final class ReceiptReadCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
    func increment() { lock.lock(); count += 1; lock.unlock() }
}
