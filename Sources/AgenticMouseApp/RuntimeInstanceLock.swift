import Darwin
import Foundation

enum RuntimeInstanceLockError: Error, CustomStringConvertible {
    case alreadyRunning
    case cannotCreateDirectory(String, Error)
    case cannotOpen(String, Int32)
    case cannotLock(String, Int32)

    var description: String {
        switch self {
        case .alreadyRunning:
            return "another Agentic Mouse runtime already owns the instance lock"
        case .cannotCreateDirectory(let path, let error):
            return "could not create runtime directory \(path): \(error)"
        case .cannotOpen(let path, let code):
            return "could not open instance lock \(path): errno \(code)"
        case .cannotLock(let path, let code):
            return "could not acquire instance lock \(path): errno \(code)"
        }
    }
}

/// Acquired before AppKit or the Karabiner lease starts so a duplicate login or
/// manual launch exits without clearing state owned by the healthy process.
final class RuntimeInstanceLock {
    private let fileDescriptor: Int32

    static func defaultURL(fileManager: FileManager = .default) throws -> URL {
        let support = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return support
            .appendingPathComponent("AgenticMouse", isDirectory: true)
            .appendingPathComponent("runtime-instance.lock")
    }

    static func acquire(
        at url: URL,
        fileManager: FileManager = .default
    ) throws -> RuntimeInstanceLock {
        let directory = url.deletingLastPathComponent()
        do {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            throw RuntimeInstanceLockError.cannotCreateDirectory(directory.path, error)
        }

        let descriptor = open(url.path, O_CREAT | O_RDWR | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            throw RuntimeInstanceLockError.cannotOpen(url.path, errno)
        }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            close(descriptor)
            if code == EWOULDBLOCK || code == EAGAIN {
                throw RuntimeInstanceLockError.alreadyRunning
            }
            throw RuntimeInstanceLockError.cannotLock(url.path, code)
        }
        _ = fchmod(descriptor, S_IRUSR | S_IWUSR)
        return RuntimeInstanceLock(fileDescriptor: descriptor)
    }

    private init(fileDescriptor: Int32) {
        self.fileDescriptor = fileDescriptor
    }

    deinit {
        _ = flock(fileDescriptor, LOCK_UN)
        close(fileDescriptor)
    }
}
