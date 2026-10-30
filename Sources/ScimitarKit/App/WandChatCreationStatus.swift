import Foundation

/// Double Top's external progress display only. Agent Flow owns the actual
/// new-chat/focus/recording operation; this packet never dispatches an input.
public struct WandChatCreationStatusCommand: Decodable, Equatable, Sendable {
    public static let commandName = "agentic_mouse_wand_chat_creation_status"
    public enum Phase: String, Decodable, Sendable { case show, hide }
    public let command: String
    public let version: Int
    public let id: UUID
    public let phase: Phase

    public init(id: UUID, phase: Phase) {
        command = Self.commandName
        version = 1
        self.id = id
        self.phase = phase
    }

    public static func decode(_ data: Data) throws -> Self {
        guard data.count <= 256,
              let fields = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(fields.keys) == ["command", "version", "id", "phase"] else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "invalid wand chat status"))
        }
        let value = try JSONDecoder().decode(Self.self, from: data)
        guard value.command == commandName, value.version == 1 else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "invalid wand chat status"))
        }
        return value
    }
}

/// A bounded display lease. A late completion cannot hide a newer operation,
/// and late show packets cannot resurrect a completed or expired operation.
public final class WandChatCreationStatusController {
    public static let leaseDuration: TimeInterval = 10
    private static let retiredLimit = 64
    public var onVisibilityChange: ((Bool) -> Void)?
    public private(set) var currentID: UUID?
    public var isVisible: Bool { currentID != nil }
    private var deadline: TimeInterval?
    private var retired: [UUID] = []
    private let scheduler: TickScheduler
    private let clock: MonotonicClock
    private let allowed: () -> Bool

    public init(scheduler: TickScheduler, clock: MonotonicClock, allowed: @escaping () -> Bool = { true }) {
        self.scheduler = scheduler
        self.clock = clock
        self.allowed = allowed
    }

    public func handle(_ command: WandChatCreationStatusCommand) {
        guard allowed() else { reset(); return }
        expireIfNeeded()
        switch command.phase {
        case .show:
            guard !retired.contains(command.id) else { return }
            let wasVisible = isVisible
            if let old = currentID, old != command.id { retire(old) }
            currentID = command.id
            deadline = clock.now + Self.leaseDuration
            if !wasVisible { onVisibilityChange?(true) }
            if !scheduler.isRunning {
                scheduler.start(interval: 0.25) { [weak self] in self?.tick() }
            }
        case .hide:
            retire(command.id)
            guard command.id == currentID else { return }
            clear()
        }
    }

    public func reset() {
        if let id = currentID { retire(id) }
        clear()
    }

    private func tick() {
        guard allowed() else { reset(); return }
        expireIfNeeded()
    }

    private func expireIfNeeded() {
        guard let deadline, clock.now >= deadline else { return }
        if let id = currentID { retire(id) }
        clear()
    }

    private func clear() {
        let wasVisible = isVisible
        currentID = nil
        deadline = nil
        scheduler.stop()
        if wasVisible { onVisibilityChange?(false) }
    }

    private func retire(_ id: UUID) {
        guard !retired.contains(id) else { return }
        retired.append(id)
        if retired.count > Self.retiredLimit { retired.removeFirst() }
    }
}
