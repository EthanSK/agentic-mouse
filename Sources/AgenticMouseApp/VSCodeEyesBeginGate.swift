// One-session admission for Better Git's atomic Default Eyes begin. The owner
// explicitly qualifies every running extension host before sending enable;
// installed version files never grant this lease. No cross-app probe protocol.
import AppKit
import Darwin
import ScimitarKit

@MainActor
final class VSCodeEyesBeginGate {
    static let variableName = "agentic_mouse_vscode_eyes_begin_expires_at"

    struct Command: Decodable {
        let command: String
        let enabled: Bool
        let codePID: Int32?
        let hostPIDs: [Int32]?
        enum CodingKeys: String, CodingKey {
            case command, enabled
            case codePID = "code_pid"
            case hostPIDs = "host_pids"
        }
        static func decode(_ data: Data) throws -> Self {
            let value = try JSONDecoder().decode(Self.self, from: data)
            guard value.command == "agentic_mouse_vscode_eyes_begin_gate" else {
                throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "wrong gate namespace"))
            }
            return value
        }
    }

    typealias WatchProcess = @MainActor (Int32, DispatchSource.ProcessEvent, @escaping @MainActor () -> Void) -> (() -> Void)?
    private let lease: ColorProofLeaseControlling
    private let scheduler: TickScheduler
    private let allowed: () -> Bool
    private let validate: @MainActor (Int32, [Int32]) -> Bool
    private let watch: WatchProcess
    private var cancelWatches: [() -> Void] = []
    private var generation = 0
    private(set) var isEnabled = false

    init(lease: ColorProofLeaseControlling, scheduler: TickScheduler,
         allowed: @escaping () -> Bool,
         validate: @escaping @MainActor (Int32, [Int32]) -> Bool = VSCodeEyesBeginGate.validateProcesses,
         watch: @escaping WatchProcess = VSCodeEyesBeginGate.watchProcess) {
        self.lease = lease; self.scheduler = scheduler; self.allowed = allowed
        self.validate = validate; self.watch = watch
        reset() // A companion restart must never inherit a previous proof.
    }

    @discardableResult
    func handle(_ command: Command) -> Bool {
        reset()
        guard command.enabled else { return true }
        guard allowed(), let codePID = command.codePID, let hostPIDs = command.hostPIDs,
              codePID > 1, !hostPIDs.isEmpty, hostPIDs.count <= 64,
              hostPIDs.allSatisfy({ $0 > 1 && $0 != codePID }),
              Set(hostPIDs).count == hostPIDs.count,
              validate(codePID, hostPIDs) else { return false }
        let token = generation
        for pid in [codePID] + hostPIDs {
            guard let cancel = watch(pid, Self.events(for: pid, codePID: codePID), { [weak self] in
                guard let self, self.generation == token else { return }
                self.reset()
            }) else { reset(); return false }
            cancelWatches.append(cancel)
        }
        // Catch exit between validation and installing the process observers.
        guard validate(codePID, hostPIDs) else { reset(); return false }
        do { try lease.activate() } catch { reset(); return false }
        isEnabled = true
        scheduler.start(interval: 2) { [weak self] in
            guard let self, self.isEnabled else { return }
            guard self.allowed(), self.validate(codePID, hostPIDs) else { self.reset(); return }
            do { try self.lease.renew() } catch { self.reset() }
        }
        return true
    }

    func reset() {
        generation &+= 1
        isEnabled = false
        scheduler.stop()
        cancelWatches.forEach { $0() }; cancelWatches.removeAll()
        lease.deactivate()
    }

    private static func validateProcesses(_ codePID: Int32, _ hostPIDs: [Int32]) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: codePID), !app.isTerminated,
              app.bundleIdentifier == "com.microsoft.VSCode", let bundle = app.bundleURL else { return false }
        return hostPIDs.allSatisfy { pid in
            // proc_info.h defines PROC_PIDPATHINFO_MAXSIZE as 4 * MAXPATHLEN;
            // that compound macro is not imported by Swift on all SDKs.
            var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
            guard proc_pidpath(pid, &path, UInt32(path.count)) > 0 else { return false }
            return String(cString: path).hasPrefix(bundle.path + "/Contents/Frameworks/")
                && kill(pid, 0) == 0
        }
    }

    static func events(for pid: Int32, codePID: Int32) -> DispatchSource.ProcessEvent {
        // Git and language-worker children are routine extension-host work.
        // They neither change that host's identity nor justify a Code --status
        // query. Only the Code main process watches fork for new host creation.
        pid == codePID ? [.exit, .fork, .exec] : [.exit, .exec]
    }

    private static func watchProcess(_ pid: Int32, events: DispatchSource.ProcessEvent, changed: @escaping @MainActor () -> Void) -> (() -> Void)? {
        guard kill(pid, 0) == 0 else { return nil }
        let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: events, queue: .main)
        source.setEventHandler { MainActor.assumeIsolated { changed() } }
        source.resume()
        return { source.cancel() }
    }
}
