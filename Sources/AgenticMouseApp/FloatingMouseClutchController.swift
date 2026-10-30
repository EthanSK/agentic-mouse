import Foundation
import CoreFoundation

/// A short, source-specific lease; no camera or pointer state crosses this bridge.
final class FloatingMouseClutchController {
    static let contextName = Notification.Name("com.ethansk.FloatingMouse.context.v1")
    static let clutchName = Notification.Name("com.ethansk.FloatingMouse.clutch.v1")
    static let reacquireName = Notification.Name("com.ethansk.FloatingMouse.reacquire.v1")
    static let variableName = "agentic_mouse_floating_corsair1_expires_at"
    static let source = "corsair1"
    private let wallTime: () -> TimeInterval
    private let monotonicTime: () -> TimeInterval
    private let allowed: () -> Bool
    private let writeExpiry: (Int64) -> Void
    private let publish: (Bool) -> Void
    private let publishReacquire: (String, TimeInterval) -> Void
    private var observer: NSObjectProtocol?
    private var timer: Timer?
    private var deadline: TimeInterval = 0
    private var activatedAt: TimeInterval = 0
    private var detectingDeadline: TimeInterval = 0
    private var detectingActivatedAt: TimeInterval = 0
    private var lastSentAt: TimeInterval = -.infinity
    private var buttonDown = false
    private(set) var isActive = false
    private(set) var isDetecting = false
    private(set) var isClutched = false

    init(
        wallTime: @escaping () -> TimeInterval = { Date().timeIntervalSince1970 },
        monotonicTime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        allowed: @escaping () -> Bool,
        writeExpiry: @escaping (Int64) -> Void,
        publish: @escaping (Bool) -> Void = { held in
            DistributedNotificationCenter.default().postNotificationName(
                FloatingMouseClutchController.clutchName, object: FloatingMouseClutchController.source,
                userInfo: ["held": held, "sentAt": Date().timeIntervalSince1970],
                deliverImmediately: true
            )
        },
        publishReacquire: @escaping (String, TimeInterval) -> Void = { pressID, sentAt in
            DistributedNotificationCenter.default().postNotificationName(
                FloatingMouseClutchController.reacquireName, object: FloatingMouseClutchController.source,
                userInfo: ["pressID": pressID, "sentAt": sentAt], deliverImmediately: true
            )
        }
    ) {
        self.wallTime = wallTime
        self.monotonicTime = monotonicTime
        self.allowed = allowed
        self.writeExpiry = writeExpiry
        self.publish = publish
        self.publishReacquire = publishReacquire
    }

    func start() {
        guard observer == nil else { return }
        writeExpiry(0)
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Self.contextName, object: nil, queue: .main
        ) { [weak self] note in
            self?.receiveContext(source: note.object as? String, info: note.userInfo)
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in self?.tick() }
    }

    func stop() {
        if let observer { DistributedNotificationCenter.default().removeObserver(observer) }
        observer = nil
        timer?.invalidate()
        timer = nil
        cancel(resetButton: true)
    }

    func receiveContext(source: String?, info: [AnyHashable: Any]?) {
        guard source == Self.source,
              let active = info?["active"] as? NSNumber,
              CFGetTypeID(active) == CFBooleanGetTypeID(),
              let sentAt = info?["sentAt"] as? NSNumber,
              CFGetTypeID(sentAt) != CFBooleanGetTypeID(),
              sentAt.doubleValue.isFinite,
              abs(sentAt.doubleValue - wallTime()) <= 1,
              sentAt.doubleValue > lastSentAt else { return }
        // Missing detecting preserves compatibility with context.v1 senders.
        var detecting = false
        if let value = info?["detecting"] {
            guard let flag = value as? NSNumber,
                  CFGetTypeID(flag) == CFBooleanGetTypeID() else { return }
            detecting = flag.boolValue
        }
        lastSentAt = sentAt.doubleValue
        expireLeases()
        guard allowed() else { cancel(); return }
        let now = monotonicTime()
        if active.boolValue || detecting {
            if !isDetecting { detectingActivatedAt = now }
            isDetecting = true
            detectingDeadline = now + 0.65
        } else {
            isDetecting = false
            detectingDeadline = 0
        }
        if active.boolValue {
            if !isActive { activatedAt = now }
            isActive = true
            deadline = now + 0.65
            writeExpiry(Int64((wallTime() + 0.65) * 1_000))
        } else {
            endActiveLease()
        }
    }

    @discardableResult
    func handle(_ data: Data, inputTime: TimeInterval) -> Bool {
        guard let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              message["command"] as? String == "agentic_mouse_floating_clutch",
              message["source"] as? String == Self.source,
              let phase = message["phase"] as? String,
              phase == "press" || phase == "release" else { return false }
        if phase == "release" {
            buttonDown = false
            release()
            return true
        }
        guard !buttonDown else { return true }
        buttonDown = true
        expireLeases()
        guard allowed() else { cancel(); return true }
        let now = monotonicTime()
        guard inputTime.isFinite, inputTime <= now, now - inputTime <= 0.65 else { return true }
        if isDetecting, inputTime >= detectingActivatedAt {
            publishReacquire(UUID().uuidString, wallTime())
        }
        if isActive, inputTime >= activatedAt {
            isClutched = true
            publish(true)
        }
        return true
    }

    func tick() {
        guard allowed() else { cancel(); return }
        expireLeases()
        if isClutched { publish(true) }
    }

    func cancel(resetButton: Bool = false) {
        endActiveLease()
        isDetecting = false
        detectingDeadline = 0
        if resetButton { buttonDown = false }
    }

    private func expireLeases() {
        let now = monotonicTime()
        if isActive && now >= deadline { endActiveLease() }
        if isDetecting && now >= detectingDeadline {
            isDetecting = false
            detectingDeadline = 0
        }
    }

    private func endActiveLease() {
        if isActive { writeExpiry(0) }
        isActive = false
        deadline = 0
        release()
    }

    private func release() {
        guard isClutched else { return }
        isClutched = false
        publish(false)
    }
}

/// Uses Karabiner's supported CLI on context heartbeats (5 Hz while armed),
/// never on camera frames or button edges. Queued obsolete writes are dropped.
final class FloatingMouseKarabinerLeaseWriter {
    private let queue = DispatchQueue(label: "com.ethansk.agentic-mouse.floating-clutch-lease")
    private let lock = NSLock()
    private var generation: UInt64 = 0

    func write(_ expiry: Int64) {
        lock.lock(); generation &+= 1; let token = generation; lock.unlock()
        queue.async { [self] in
            lock.lock(); let current = generation == token; lock.unlock()
            guard current else { return }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: KarabinerCLIModeLease.commandLinePath)
            process.arguments = ["--silent", "--set-variables", "{\"\(FloatingMouseClutchController.variableName)\":\(expiry)}"]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
            if process.isRunning { process.waitUntilExit() }
        }
    }
}
