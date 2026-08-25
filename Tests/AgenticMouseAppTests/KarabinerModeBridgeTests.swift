import Darwin
import Foundation
@testable import AgenticMouseApp
import XCTest

final class KarabinerModeBridgeTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        // sockaddr_un.sun_path is only 104 bytes on macOS, so keep the
        // integration-test endpoint deliberately short.
        temporaryDirectory = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("am-\(getpid())-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
    }

    func testReceiverDeliversDatagramAndRemovesOnlyItsOwnSocket() throws {
        let socketPath = temporaryDirectory.appendingPathComponent("receiver.sock").path
        let payload = Data("{\"action\":\"enter\"}".utf8)
        let delivered = expectation(description: "user command delivered")
        let receiver = KarabinerUserCommandReceiver(socketPath: socketPath)

        try receiver.start { data in
            XCTAssertEqual(data, payload)
            delivered.fulfill()
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: socketPath))
        XCTAssertTrue(receiver.isHealthy)

        try send(payload + Data([0x0A]), to: socketPath)
        wait(for: [delivered], timeout: 1)

        receiver.stop()
        XCTAssertFalse(FileManager.default.fileExists(atPath: socketPath))
        XCTAssertFalse(FileManager.default.fileExists(atPath: socketPath + ".agentic-mouse.lock"))
    }

    func testReceiverDetectsAReplacedSocketAndNeverUnlinksTheReplacement() throws {
        let socketPath = temporaryDirectory.appendingPathComponent("replaced.sock").path
        let receiver = KarabinerUserCommandReceiver(socketPath: socketPath)
        try receiver.start { _ in }
        XCTAssertTrue(receiver.isHealthy)

        unlink(socketPath)
        let replacementFD = try bindDatagramSocket(at: socketPath)
        defer {
            close(replacementFD)
            unlink(socketPath)
        }

        XCTAssertFalse(receiver.isHealthy)
        receiver.stop()
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: socketPath),
            "stopping a stale receiver must not remove another process's replacement socket"
        )
    }

    func testReceiverNeverUnlinksForeignSocket() throws {
        let socketPath = temporaryDirectory.appendingPathComponent("foreign.sock").path
        let foreignFD = try bindDatagramSocket(at: socketPath)
        defer {
            close(foreignFD)
            unlink(socketPath)
        }

        do {
            let receiver = KarabinerUserCommandReceiver(socketPath: socketPath)
            XCTAssertThrowsError(try receiver.start { _ in }) { error in
                guard case KarabinerModeBridgeError.socketPathOccupied(let occupiedPath) = error else {
                    return XCTFail("unexpected error: \(error)")
                }
                XCTAssertEqual(occupiedPath, socketPath)
            }
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: socketPath))
        XCTAssertFalse(FileManager.default.fileExists(atPath: socketPath + ".agentic-mouse.lock"))
    }

    func testReceiverReclaimsOnlyTheExactCrashRecordedSocket() throws {
        let socketPath = temporaryDirectory.appendingPathComponent("crash.sock").path
        let crashedFD = try bindDatagramSocket(at: socketPath)
        guard let identity = KarabinerUserCommandReceiver.socketIdentity(at: socketPath) else {
            return XCTFail("expected the bound socket identity")
        }
        try writeMarker(identity, socketPath: socketPath)
        close(crashedFD)

        let receiver = KarabinerUserCommandReceiver(socketPath: socketPath)
        try receiver.start { _ in }
        XCTAssertTrue(receiver.isHealthy)
        XCTAssertNotEqual(
            KarabinerUserCommandReceiver.socketIdentity(at: socketPath),
            identity,
            "recovery must bind a new socket after reclaiming the exact crash artifact"
        )
        receiver.stop()
    }

    func testReceiverRefusesSocketThatDoesNotMatchTheCrashMarker() throws {
        let socketPath = temporaryDirectory.appendingPathComponent("mismatch.sock").path
        let foreignFD = try bindDatagramSocket(at: socketPath)
        defer {
            close(foreignFD)
            unlink(socketPath)
            unlink(socketPath + ".agentic-mouse.lock")
        }
        guard let identity = KarabinerUserCommandReceiver.socketIdentity(at: socketPath) else {
            return XCTFail("expected the foreign socket identity")
        }
        let staleIdentity = KarabinerUserCommandReceiver.SocketIdentity(
            device: identity.device,
            inode: identity.inode &+ 1,
            user: identity.user,
            type: identity.type
        )
        try writeMarker(staleIdentity, socketPath: socketPath)

        let receiver = KarabinerUserCommandReceiver(socketPath: socketPath)
        XCTAssertThrowsError(try receiver.start { _ in })
        XCTAssertEqual(KarabinerUserCommandReceiver.socketIdentity(at: socketPath), identity)
    }

    private func send(_ data: Data, to path: String) throws {
        let fd = socket(AF_UNIX, SOCK_DGRAM, 0)
        guard fd >= 0 else { throw POSIXError(.EIO) }
        defer { close(fd) }

        var address = try socketAddress(path: path)
        let sent = data.withUnsafeBytes { bytes in
            withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                    sendto(
                        fd,
                        bytes.baseAddress,
                        bytes.count,
                        0,
                        sockaddrPointer,
                        socklen_t(MemoryLayout<sockaddr_un>.size)
                    )
                }
            }
        }
        guard sent == data.count else { throw POSIXError(.EIO) }
    }

    private func writeMarker(
        _ identity: KarabinerUserCommandReceiver.SocketIdentity,
        socketPath: String
    ) throws {
        let value = "\(identity.device) \(identity.inode) \(identity.user) \(identity.type)\n"
        try value.write(
            toFile: socketPath + ".agentic-mouse.lock",
            atomically: false,
            encoding: .utf8
        )
    }

    private func bindDatagramSocket(at path: String) throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_DGRAM, 0)
        guard fd >= 0 else { throw POSIXError(.EIO) }
        var address = try socketAddress(path: path)
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Darwin.bind(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else {
            close(fd)
            throw POSIXError(.EIO)
        }
        return fd
    }

    private func socketAddress(path: String) throws -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard path.utf8CString.count <= capacity else { throw POSIXError(.ENAMETOOLONG) }
        path.withCString { source in
            withUnsafeMutablePointer(to: &address.sun_path) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: capacity) { destination in
                    strncpy(destination, source, capacity - 1)
                    destination[capacity - 1] = 0
                }
            }
        }
        return address
    }
}
