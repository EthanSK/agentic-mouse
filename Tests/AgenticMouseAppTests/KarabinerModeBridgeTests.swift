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

        try send(payload + Data([0x0A]), to: socketPath)
        wait(for: [delivered], timeout: 1)

        receiver.stop()
        XCTAssertFalse(FileManager.default.fileExists(atPath: socketPath))
        XCTAssertFalse(FileManager.default.fileExists(atPath: socketPath + ".agentic-mouse.lock"))
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
