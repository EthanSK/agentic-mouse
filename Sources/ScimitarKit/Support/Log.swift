import Foundation
import os

public enum LogLevel: Int, Comparable, Sendable {
    case debug = 0
    case info = 1
    case notice = 2
    case error = 3

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool { lhs.rawValue < rhs.rawValue }

    public var label: String {
        switch self {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .notice: return "NOTE"
        case .error: return "ERROR"
        }
    }
}

/// Injectable sink so tests can assert *what* was logged (and prove that raw
/// identifiers are never logged).
public protocol LogSink: AnyObject, Sendable {
    func write(level: LogLevel, category: String, message: String)
}

public final class OSLogSink: LogSink, @unchecked Sendable {
    private let subsystem: String
    private var loggers: [String: Logger] = [:]
    private let lock = NSLock()

    public init(subsystem: String = "com.ethan.agentic-mouse") {
        self.subsystem = subsystem
    }

    public func write(level: LogLevel, category: String, message: String) {
        lock.lock()
        let logger: Logger
        if let existing = loggers[category] {
            logger = existing
        } else {
            logger = Logger(subsystem: subsystem, category: category)
            loggers[category] = logger
        }
        lock.unlock()

        // All interpolated values are pre-redacted by the caller; marking them
        // public keeps them readable in Console.app without leaking anything.
        switch level {
        case .debug: logger.debug("\(message, privacy: .public)")
        case .info: logger.info("\(message, privacy: .public)")
        case .notice: logger.notice("\(message, privacy: .public)")
        case .error: logger.error("\(message, privacy: .public)")
        }
    }
}

/// Writes to stderr. Used by the CLI and by `--verbose` runs.
public final class StandardErrorLogSink: LogSink, @unchecked Sendable {
    private let minimumLevel: LogLevel
    private let lock = NSLock()

    public init(minimumLevel: LogLevel = .info) {
        self.minimumLevel = minimumLevel
    }

    public func write(level: LogLevel, category: String, message: String) {
        guard level >= minimumLevel else { return }
        let line = "[\(level.label)] \(category): \(message)\n"
        lock.lock()
        FileHandle.standardError.write(Data(line.utf8))
        lock.unlock()
    }
}

public final class CompositeLogSink: LogSink, @unchecked Sendable {
    private let sinks: [LogSink]
    public init(_ sinks: [LogSink]) { self.sinks = sinks }
    public func write(level: LogLevel, category: String, message: String) {
        sinks.forEach { $0.write(level: level, category: category, message: message) }
    }
}

/// Captures log lines in memory. Used by tests and by the status menu's
/// "recent activity" view.
public final class RecordingLogSink: LogSink, @unchecked Sendable {
    public struct Entry: Equatable {
        public let level: LogLevel
        public let category: String
        public let message: String
    }

    private var storage: [Entry] = []
    private let limit: Int
    private let lock = NSLock()

    public init(limit: Int = 500) { self.limit = limit }

    public func write(level: LogLevel, category: String, message: String) {
        lock.lock()
        storage.append(Entry(level: level, category: category, message: message))
        if storage.count > limit { storage.removeFirst(storage.count - limit) }
        lock.unlock()
    }

    public var entries: [Entry] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    public func clear() {
        lock.lock()
        storage.removeAll()
        lock.unlock()
    }
}

public final class NullLogSink: LogSink, @unchecked Sendable {
    public init() {}
    public func write(level: LogLevel, category: String, message: String) {}
}

/// Small category-scoped facade.
public struct Log: Sendable {
    public let category: String
    private let sink: LogSink

    public init(category: String, sink: LogSink) {
        self.category = category
        self.sink = sink
    }

    public func debug(_ message: @autoclosure () -> String) {
        sink.write(level: .debug, category: category, message: message())
    }

    public func info(_ message: @autoclosure () -> String) {
        sink.write(level: .info, category: category, message: message())
    }

    public func notice(_ message: @autoclosure () -> String) {
        sink.write(level: .notice, category: category, message: message())
    }

    public func error(_ message: @autoclosure () -> String) {
        sink.write(level: .error, category: category, message: message())
    }

    public func scoped(_ newCategory: String) -> Log {
        Log(category: newCategory, sink: sink)
    }
}
