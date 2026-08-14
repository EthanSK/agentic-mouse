import Foundation

public enum LightingError: Error, Equatable {
    case sdkUnavailable(String)
    case notConnected
    case deviceNotFound
    case writeFailed(Int32)
}

/// A description of the mouse we are allowed to paint. Contains no serial and
/// no raw identifier beyond what the caller chooses to keep in memory.
public struct LightingDeviceSummary: Equatable, Sendable {
    public let model: String
    public let ledCount: Int
    /// Redacted device tag, safe to log or display.
    public let redactedIdentifier: String

    public init(model: String, ledCount: Int, redactedIdentifier: String) {
        self.model = model
        self.ledCount = ledCount
        self.redactedIdentifier = redactedIdentifier
    }
}

/// Writes colours to exactly one device.
public protocol LightingController: AnyObject {
    var device: LightingDeviceSummary? { get }
    var isAvailable: Bool { get }

    /// Applies a frame. Implementations are expected to drop redundant writes.
    func apply(_ frame: LightingFrame) throws
    /// Releases this client's lighting layer so ordinary iCUE lighting returns.
    func release() throws
}

/// Test double that records every write and lets tests inject failures.
public final class RecordingLightingController: LightingController {
    public private(set) var appliedFrames: [LightingFrame] = []
    public private(set) var releaseCount = 0
    public var device: LightingDeviceSummary?
    public var isAvailable: Bool = true
    public var errorToThrow: LightingError?

    public init(device: LightingDeviceSummary? = LightingDeviceSummary(
        model: "CORSAIR SCIMITAR ELITE WIRELESS SE",
        ledCount: 4,
        redactedIdentifier: "id:testtest"
    )) {
        self.device = device
    }

    public func apply(_ frame: LightingFrame) throws {
        if let errorToThrow { throw errorToThrow }
        appliedFrames.append(frame)
    }

    public func release() throws {
        if let errorToThrow { throw errorToThrow }
        releaseCount += 1
        appliedFrames.append(.released)
    }

    public func reset() {
        appliedFrames.removeAll()
        releaseCount = 0
    }
}

/// Drops writes that would change nothing, and rate-limits the rest.
///
/// The mode pulse ticks continuously. It must not hammer iCUE or re-send a
/// frame the mouse is already displaying.
public final class ThrottlingLightingController: LightingController {
    private let wrapped: LightingController
    private let clock: MonotonicClock
    private let minimumInterval: TimeInterval

    private var lastFrame: LightingFrame?
    private var lastWriteTime: TimeInterval = -.greatestFiniteMagnitude
    /// A frame that arrived during the cool-down and still needs sending.
    private var deferredFrame: LightingFrame?

    public private(set) var writeCount = 0
    public private(set) var suppressedCount = 0

    public init(
        wrapping controller: LightingController,
        clock: MonotonicClock = SystemMonotonicClock(),
        minimumInterval: TimeInterval = 1.0 / 30.0
    ) {
        self.wrapped = controller
        self.clock = clock
        self.minimumInterval = minimumInterval.isFinite ? max(0, minimumInterval) : 0
    }

    public var device: LightingDeviceSummary? { wrapped.device }
    public var isAvailable: Bool { wrapped.isAvailable }

    public func apply(_ frame: LightingFrame) throws {
        guard frame != lastFrame else {
            // `apply` always describes the newest desired state. If an older,
            // different frame was deferred, returning to the frame already on
            // the mouse cancels that stale write.
            deferredFrame = nil
            suppressedCount += 1
            return
        }
        let now = clock.now
        guard now - lastWriteTime >= minimumInterval else {
            deferredFrame = frame
            suppressedCount += 1
            return
        }
        try wrapped.apply(frame)
        lastFrame = frame
        deferredFrame = nil
        lastWriteTime = now
        writeCount += 1
    }

    /// Flushes anything that was held back by the rate limit. Call from the
    /// tick loop so a final colour never gets stuck in the cool-down.
    public func flushDeferred() throws {
        guard let frame = deferredFrame else { return }
        guard clock.now - lastWriteTime >= minimumInterval else { return }
        try wrapped.apply(frame)
        deferredFrame = nil
        lastFrame = frame
        lastWriteTime = clock.now
        writeCount += 1
    }

    public var hasDeferredFrame: Bool { deferredFrame != nil }

    public var deferredFlushDelay: TimeInterval {
        guard deferredFrame != nil else { return 0 }
        return max(0, minimumInterval - (clock.now - lastWriteTime))
    }

    public func release() throws {
        try wrapped.release()
        lastFrame = nil
        deferredFrame = nil
        lastWriteTime = clock.now
    }

    /// Forgets the cached frame so the next `apply` definitely writes. Used
    /// after a reconnect, when the device's actual state is unknown.
    public func invalidateCache() {
        lastFrame = nil
    }
}

/// Used when no SDK is present. Everything succeeds and nothing happens, so the
/// rest of the app can run unchanged with lighting simply absent.
public final class NullLightingController: LightingController {
    public let device: LightingDeviceSummary? = nil
    public let isAvailable = false
    public init() {}
    public func apply(_ frame: LightingFrame) throws {}
    public func release() throws {}
}
