import Darwin
import Foundation
import ScimitarKit

enum KarabinerModeBridgeError: Error, CustomStringConvertible {
    case commandLineUnavailable
    case commandLineFailed(Int32)
    case socketPathOccupied(String)
    case systemCall(String, Int32)

    var description: String {
        switch self {
        case .commandLineUnavailable:
            return "Karabiner command-line tool is unavailable"
        case .commandLineFailed(let status):
            return "Karabiner variable update failed with status \(status)"
        case .socketPathOccupied(let path):
            return "another user-command receiver owns \(path)"
        case .systemCall(let name, let code):
            return "\(name) failed with errno \(code)"
        }
    }
}

/// Renews the absolute Karabiner expiry while the proof HUD is alive.
/// Spawning the CLI happens on a serialized background queue on a two-second
/// heartbeat, never per button press or on the AppKit main thread.
final class KarabinerCLIModeLease: ColorProofLeaseControlling {
    static let defaultVariableName = "agentic_mouse_color_proof_expires_at"
    static let commandLinePath = "/Library/Application Support/org.pqrs/Karabiner-Elements/bin/karabiner_cli"

    private let leaseDurationMilliseconds: Int64
    private let variableName: String
    private let processQueue = DispatchQueue(label: "com.ethansk.agentic-mouse.karabiner-variable-writer")
    private let stateLock = NSLock()
    private var generation: UInt64 = 0
    private var active = false

    /// Delivered on the main queue only for the currently active generation.
    var onFailure: ((Error) -> Void)?

    init(
        leaseDuration: TimeInterval,
        variableName: String = KarabinerCLIModeLease.defaultVariableName
    ) {
        leaseDurationMilliseconds = Int64(max(1, leaseDuration) * 1_000)
        self.variableName = variableName
    }

    func activate() throws {
        let token = stateLock.withLock {
            generation &+= 1
            active = true
            return generation
        }
        try enqueue(expiryMilliseconds: nextExpiry(), generation: token, reportsFailure: true)
    }

    func renew() throws {
        let token = stateLock.withLock { generation }
        try enqueue(expiryMilliseconds: nextExpiry(), generation: token, reportsFailure: true)
    }

    func deactivate() {
        let token = stateLock.withLock {
            generation &+= 1
            active = false
            return generation
        }
        try? enqueue(expiryMilliseconds: 0, generation: token, reportsFailure: false)
    }

    private func nextExpiry() -> Int64 {
        Int64((Date().timeIntervalSince1970 * 1_000).rounded()) + leaseDurationMilliseconds
    }

    private func enqueue(
        expiryMilliseconds: Int64,
        generation: UInt64,
        reportsFailure: Bool
    ) throws {
        guard FileManager.default.isExecutableFile(atPath: Self.commandLinePath) else {
            throw KarabinerModeBridgeError.commandLineUnavailable
        }

        let payload = try JSONSerialization.data(
            withJSONObject: [variableName: expiryMilliseconds],
            options: [.sortedKeys]
        )
        guard let json = String(data: payload, encoding: .utf8) else {
            throw KarabinerModeBridgeError.commandLineFailed(-1)
        }

        processQueue.async { [weak self] in
            guard let self else { return }
            do {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: Self.commandLinePath)
                process.arguments = ["--silent", "--set-variables", json]
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice
                try process.run()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else {
                    throw KarabinerModeBridgeError.commandLineFailed(process.terminationStatus)
                }
            } catch {
                guard reportsFailure else { return }
                let isCurrent = self.stateLock.withLock {
                    self.active && self.generation == generation
                }
                guard isCurrent else { return }
                DispatchQueue.main.async { [weak self] in self?.onFailure?(error) }
            }
        }
    }
}

/// Receives Karabiner 16 `send_user_command` payloads over its documented
/// UNIX datagram endpoint. A lock marker prevents this app from stealing a
/// socket owned by another user-command server; only its own stale crash socket
/// is reclaimed.
final class KarabinerUserCommandReceiver {
    typealias Handler = (Data) -> Void

    static var defaultSocketPath: String {
        "/Library/Application Support/org.pqrs/tmp/user/\(geteuid())/user_command_receiver.sock"
    }

    private let socketPath: String
    private let queue = DispatchQueue(label: "com.ethansk.agentic-mouse.karabiner-user-command")
    private let queueKey = DispatchSpecificKey<Void>()
    private var socketFD: Int32 = -1
    private var lockFD: Int32 = -1
    private var source: DispatchSourceRead?
    private var boundIdentity: SocketIdentity?

    struct SocketIdentity: Equatable {
        let device: dev_t
        let inode: ino_t
        let user: uid_t
        let type: mode_t
    }

    init(socketPath: String = KarabinerUserCommandReceiver.defaultSocketPath) {
        self.socketPath = socketPath
        queue.setSpecific(key: queueKey, value: ())
    }

    deinit { stop() }

    func start(handler: @escaping Handler) throws {
        guard socketFD < 0 else { return }
        let lockPath = socketPath + ".agentic-mouse.lock"
        let lockExisted = FileManager.default.fileExists(atPath: lockPath)

        let openedLock = open(lockPath, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard openedLock >= 0 else {
            throw KarabinerModeBridgeError.systemCall("open lock", errno)
        }
        guard flock(openedLock, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            close(openedLock)
            throw KarabinerModeBridgeError.systemCall("lock receiver", code)
        }
        _ = fchmod(openedLock, S_IRUSR | S_IWUSR)
        lockFD = openedLock

        if FileManager.default.fileExists(atPath: socketPath) {
            let recordedIdentity = Self.recordedSocketIdentity(from: openedLock)
            guard lockExisted,
                  let currentIdentity = Self.socketIdentity(at: socketPath),
                  currentIdentity == recordedIdentity
            else {
                releaseLock(removeMarker: !lockExisted)
                throw KarabinerModeBridgeError.socketPathOccupied(socketPath)
            }
            unlink(socketPath)
        }

        do {
            socketFD = try Self.bindDatagramSocket(path: socketPath)
            _ = chmod(socketPath, S_IRUSR | S_IWUSR)
            guard let identity = Self.socketIdentity(at: socketPath) else {
                let code = errno == 0 ? ENOENT : errno
                close(socketFD)
                socketFD = -1
                unlink(socketPath)
                throw KarabinerModeBridgeError.systemCall("inspect bound socket", code)
            }
            boundIdentity = identity
            try Self.record(identity, in: openedLock)
            let existingFlags = fcntl(socketFD, F_GETFL)
            _ = fcntl(socketFD, F_SETFL, existingFlags | O_NONBLOCK)
        } catch {
            if socketFD >= 0 {
                close(socketFD)
                socketFD = -1
            }
            if let boundIdentity,
               Self.socketIdentity(at: socketPath) == boundIdentity {
                unlink(socketPath)
            }
            self.boundIdentity = nil
            releaseLock(removeMarker: true)
            throw error
        }

        let boundFD = socketFD
        let readSource = DispatchSource.makeReadSource(fileDescriptor: socketFD, queue: queue)
        readSource.setEventHandler { [weak self] in
            self?.receiveAvailable(from: boundFD, handler: handler)
        }
        readSource.setCancelHandler { close(boundFD) }
        readSource.resume()
        source = readSource
    }

    func stop() {
        let cleanup = { [self] in
            let ownedSocket = socketFD >= 0
            if let source {
                source.setEventHandler {}
                source.cancel()
                self.source = nil
            } else if socketFD >= 0 {
                close(socketFD)
            }
            socketFD = -1
            if ownedSocket,
               let boundIdentity,
               Self.socketIdentity(at: socketPath) == boundIdentity {
                unlink(socketPath)
            }
            boundIdentity = nil
            releaseLock(removeMarker: ownedSocket)
        }
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            cleanup()
        } else {
            queue.sync(execute: cleanup)
        }
    }

    var isHealthy: Bool {
        let inspect = { [self] in
            guard socketFD >= 0, source != nil, let boundIdentity else { return false }
            return Self.socketIdentity(at: socketPath) == boundIdentity
        }
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            return inspect()
        }
        return queue.sync(execute: inspect)
    }

    private func receiveAvailable(from fd: Int32, handler: @escaping Handler) {
        var buffer = [UInt8](repeating: 0, count: 32 * 1_024)
        while true {
            let count = recv(fd, &buffer, buffer.count, 0)
            if count > 0 {
                var end = count
                if end > 0, buffer[end - 1] == 0x0A { end -= 1 }
                if end > 0, buffer[end - 1] == 0x0D { end -= 1 }
                guard end > 0 else { continue }
                let data = Data(buffer[0..<end])
                DispatchQueue.main.async { handler(data) }
                continue
            }
            if count < 0, errno == EINTR { continue }
            if count < 0, errno == EAGAIN || errno == EWOULDBLOCK { return }
            return
        }
    }

    private func releaseLock(removeMarker: Bool) {
        guard lockFD >= 0 else { return }
        _ = flock(lockFD, LOCK_UN)
        close(lockFD)
        lockFD = -1
        if removeMarker { unlink(socketPath + ".agentic-mouse.lock") }
    }

    static func socketIdentity(at path: String) -> SocketIdentity? {
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }
        return SocketIdentity(
            device: info.st_dev,
            inode: info.st_ino,
            user: info.st_uid,
            type: info.st_mode & S_IFMT
        )
    }

    private static func record(_ identity: SocketIdentity, in fileDescriptor: Int32) throws {
        let payload = "\(identity.device) \(identity.inode) \(identity.user) \(identity.type)\n"
        let data = Data(payload.utf8)
        guard ftruncate(fileDescriptor, 0) == 0,
              lseek(fileDescriptor, 0, SEEK_SET) == 0
        else {
            throw KarabinerModeBridgeError.systemCall("prepare receiver marker", errno)
        }
        let written = data.withUnsafeBytes { bytes in
            Darwin.write(fileDescriptor, bytes.baseAddress, bytes.count)
        }
        guard written == data.count else {
            throw KarabinerModeBridgeError.systemCall("write receiver marker", errno)
        }
        _ = fsync(fileDescriptor)
    }

    private static func recordedSocketIdentity(from fileDescriptor: Int32) -> SocketIdentity? {
        guard lseek(fileDescriptor, 0, SEEK_SET) == 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: 256)
        let count = Darwin.read(fileDescriptor, &bytes, bytes.count)
        guard count > 0,
              let value = String(bytes: bytes[0..<count], encoding: .utf8)
        else { return nil }
        let fields = value.split(whereSeparator: { $0 == " " || $0 == "\n" })
        guard fields.count == 4,
              let device = dev_t(fields[0]),
              let inode = ino_t(fields[1]),
              let user = uid_t(fields[2]),
              let type = mode_t(fields[3])
        else { return nil }
        return SocketIdentity(device: device, inode: inode, user: user, type: type)
    }

    private static func bindDatagramSocket(path: String) throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_DGRAM, 0)
        guard fd >= 0 else {
            throw KarabinerModeBridgeError.systemCall("socket", errno)
        }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard path.utf8CString.count <= capacity else {
            close(fd)
            throw KarabinerModeBridgeError.systemCall("socket path", ENAMETOOLONG)
        }
        path.withCString { source in
            withUnsafeMutablePointer(to: &address.sun_path) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: capacity) { destination in
                    strncpy(destination, source, capacity - 1)
                    destination[capacity - 1] = 0
                }
            }
        }

        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Darwin.bind(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else {
            let code = errno
            close(fd)
            throw KarabinerModeBridgeError.systemCall("bind", code)
        }
        return fd
    }
}
