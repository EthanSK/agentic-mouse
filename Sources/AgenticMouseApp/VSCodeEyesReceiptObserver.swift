// Event-driven recovery of Default Eyes admission after host/app/session changes.
// Better Git owns receipt files; this consumer never writes or removes them.
import AppKit
import Darwin
import Foundation

@MainActor
final class VSCodeEyesReceiptObserver {
    typealias TargetProvider = @MainActor () -> VSCodeEyesHostReceipts.Target?
    typealias ReadProof = (VSCodeEyesHostReceipts.Target, URL) -> VSCodeEyesHostProof?
    private let gate: VSCodeEyesBeginGate
    private let directory: URL
    private let allowed: () -> Bool
    private let onStatus: (Bool) -> Void
    private let queue = DispatchQueue(label: "com.ethansk.agentic-mouse.eyes-host-proof", qos: .utility)
    private let reader: VSCodeEyesProcessReader
    private let targetProvider: TargetProvider
    private let readProof: ReadProof
    private let observeCode: VSCodeEyesBeginGate.WatchProcess
    private var filesystem: DispatchSourceFileSystemObject?
    private var watchedDirectory: URL?
    private var observers: [NSObjectProtocol] = []
    private var started = false
    private var busy = false
    private var pending = false
    private var generation = 0
    private var admitted: VSCodeEyesHostProof?
    private var watcherID = UUID()
    private var codePID: Int32?
    private var cancelCodeWatch: (() -> Void)?

    init(gate: VSCodeEyesBeginGate, directory: URL = VSCodeEyesHostReceipts.directory,
         allowed: @escaping () -> Bool, onStatus: @escaping (Bool) -> Void,
         targetProvider: @escaping TargetProvider = VSCodeEyesReceiptObserver.currentTarget,
         readProof: ReadProof? = nil,
         observeCode: @escaping VSCodeEyesBeginGate.WatchProcess = VSCodeEyesReceiptObserver.watchCode) {
        self.gate = gate; self.directory = directory; self.allowed = allowed; self.onStatus = onStatus
        self.targetProvider = targetProvider
        self.observeCode = observeCode
        let reader = VSCodeEyesProcessReader()
        self.reader = reader
        self.readProof = readProof ?? { target, directory in
            VSCodeEyesHostReceipts.read(target: target, directory: directory, run: reader.run)
        }
    }

    func start() {
        guard !started else { return }
        started = true
        gate.onProcessInvalidation = { [weak self] in self?.refresh() }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didActivateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.bundleIdentifier == "com.microsoft.VSCode" else { return }
                MainActor.assumeIsolated {
                    self?.applicationChanged(pid: app.processIdentifier,
                        activated: notification.name == NSWorkspace.didActivateApplicationNotification)
                }
            })
        }
        refresh()
    }

    func stop() {
        started = false
        invalidate()
        filesystem?.cancel(); filesystem = nil; watchedDirectory = nil
        cancelCodeWatch?(); cancelCodeWatch = nil; codePID = nil
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }; observers.removeAll()
        gate.onProcessInvalidation = nil
    }

    func invalidate() {
        generation &+= 1
        pending = false
        admitted = nil
        reader.cancel()
        gate.reset()
    }

    func applicationChanged(pid: Int32, activated: Bool) {
        // macOS Code --status briefly launches its own windowless Code app.
        // Its launch/termination must not invalidate the query producing it.
        // The selected main's kernel watch owns its lifetime; new windows/hosts
        // publish receipts, and activation of another main revokes admission.
        guard activated || codePID == nil || codePID == pid else { return }
        if activated && codePID != pid { invalidate() }
        refresh()
    }

    func refresh() {
        guard started else { return }
        configureWatcher()
        generation &+= 1
        guard allowed() else { invalidate(); return }
        guard !busy else { pending = true; return }
        guard let target = targetProvider() else {
            cancelCodeWatch?(); cancelCodeWatch = nil; codePID = nil
            admitted = nil; gate.reset(); onStatus(false); return
        }
        if codePID != target.pid {
            cancelCodeWatch?(); cancelCodeWatch = nil; codePID = target.pid
            cancelCodeWatch = observeCode(target.pid, [.fork, .exec, .exit], { [weak self] in
                guard let self, self.started, self.codePID == target.pid else { return }
                self.invalidate(); self.refresh()
            })
        }
        guard cancelCodeWatch != nil else { gate.reset(); onStatus(false); return }
        let token = generation, directory = directory, readProof = readProof
        busy = true; pending = false
        queue.async { [weak self] in
            let proof = readProof(target, directory)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.busy = false
                guard self.started else { return }
                if token == self.generation, self.allowed() {
                    if let proof, self.targetProvider()?.pid == target.pid {
                        // An unrelated worker fork may leave the qualified host set
                        // unchanged. Restore automatically; do not require a human.
                        if self.admitted != proof || !self.gate.isEnabled {
                            let command = VSCodeEyesBeginGate.Command(command: "agentic_mouse_vscode_eyes_begin_gate",
                                enabled: true, codePID: proof.code.pid, hostPIDs: proof.hosts.map(\.pid))
                            if self.gate.handle(command) { self.admitted = proof }
                            else { self.admitted = nil }
                            self.onStatus(self.gate.isEnabled)
                        }
                    } else {
                        let wasEnabled = self.gate.isEnabled
                        self.admitted = nil; self.gate.reset()
                        if wasEnabled { self.onStatus(false) }
                    }
                }
                if self.pending || token != self.generation { self.refresh() }
            }
        }
    }

    private static func currentTarget() -> VSCodeEyesHostReceipts.Target? {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.microsoft.VSCode")
            .filter { !$0.isTerminated && kill($0.processIdentifier, 0) == 0 }
        guard apps.count == 1, let app = apps.first, kill(app.processIdentifier, 0) == 0,
              let url = app.bundleURL else { return nil }
        return .init(pid: app.processIdentifier, appURL: url)
    }

    private static func watchCode(_ pid: Int32, events: DispatchSource.ProcessEvent, changed: @escaping @MainActor () -> Void) -> (() -> Void)? {
        guard kill(pid, 0) == 0 else { return nil }
        let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: events, queue: .main)
        source.setEventHandler { MainActor.assumeIsolated { changed() } }
        source.resume()
        return { source.cancel() }
    }

    private func configureWatcher() {
        var ancestor = directory
        var isDirectory: ObjCBool = false
        while !FileManager.default.fileExists(atPath: ancestor.path, isDirectory: &isDirectory) || !isDirectory.boolValue {
            let parent = ancestor.deletingLastPathComponent()
            guard parent != ancestor else { return }
            ancestor = parent
        }
        guard watchedDirectory != ancestor else { return }
        let fd = open(ancestor.path, O_EVTONLY)
        guard fd >= 0 else { return }
        filesystem?.cancel()
        let token = UUID()
        watcherID = token
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        source.setCancelHandler { close(fd) }
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.started, self.watcherID == token else { return }
                // A replaced directory needs a new descriptor even at the same path.
                if let flags = self.filesystem?.data, !flags.intersection([.rename, .delete]).isEmpty { self.watchedDirectory = nil }
                self.refresh()
            }
        }
        filesystem = source; watchedDirectory = ancestor; source.resume()
    }
}
