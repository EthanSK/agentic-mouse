// Sparkle owns standard update dialogs and verified installation. This adapter
// postpones replacement until dictation and mouse work are idle, and disarms
// the signed recovery helper without changing the user's mappings or settings.
import AppKit
import Combine
import Sparkle

@MainActor final class UpdateInstallation {
    private let mayInstall: () async -> Bool
    private let prepare: () async -> Bool
    private let restore: () async -> Void
    private var handler: (() -> Void)?
    private var checkTask: Task<Void, Never>?
    private var abortTask: Task<Void, Never>?
    private var checkAgain = false
    private var prepared = false
    private var generation = 0

    init(mayInstall: @escaping () async -> Bool, prepare: @escaping () async -> Bool,
         restore: @escaping () async -> Void) {
        self.mayInstall = mayInstall; self.prepare = prepare; self.restore = restore
    }

    func offer(_ install: @escaping () -> Void) {
        generation += 1
        let token = generation, previousAbort = abortTask
        Task { @MainActor in
            await previousAbort?.value
            guard token == generation else { return }
            handler = install; prepared = false; requestCheck()
        }
    }

    func requestCheck() {
        guard handler != nil else { return }
        checkAgain = true
        guard checkTask == nil else { return }
        checkTask = Task { @MainActor in
            defer { checkTask = nil }
            while handler != nil, checkAgain, !Task.isCancelled {
                checkAgain = false
                guard await mayInstall(), !Task.isCancelled, handler != nil else { continue }
                prepared = await prepare()
                guard !Task.isCancelled, prepared, handler != nil else { continue }
                // The asynchronous Service Management disarm can overlap a new
                // recording or mouse mode. Revalidate immediately before relaunch.
                let allowed = await mayInstall()
                guard !Task.isCancelled, handler != nil else { return }
                guard allowed else { await restore(); prepared = false; continue }
                let install = handler; handler = nil; install?()
            }
        }
    }

    func abort() async {
        generation += 1; handler = nil; checkAgain = false
        if let abortTask { await abortTask.value; return }
        let pending = checkTask; pending?.cancel()
        let recovery = Task { @MainActor in
            await pending?.value
            if prepared { await restore(); prepared = false }
        }
        abortTask = recovery; await recovery.value; abortTask = nil
    }
}

@MainActor final class AppUpdater: NSObject, SPUUpdaterDelegate {
    var onChange: (() -> Void)?
    var canCheck: Bool { controller?.updater.canCheckForUpdates ?? false }
    var automaticChecks: Bool { controller?.updater.automaticallyChecksForUpdates ?? false }
    var automaticDownloads: Bool { controller?.updater.automaticallyDownloadsUpdates ?? false }
    private var controller: SPUStandardUpdaterController?
    private var observations = Set<AnyCancellable>()
    private var workspaceObservers: [NSObjectProtocol] = []
    private var readinessObserver: NSObjectProtocol?
    private let installation: UpdateInstallation

    init(mayInstall: @escaping () async -> Bool, prepare: @escaping () async -> Bool,
         restore: @escaping () async -> Void) {
        installation = UpdateInstallation(mayInstall: mayInstall, prepare: prepare, restore: restore)
        super.init()
        guard let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              Data(base64Encoded: key)?.count == 32 else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: false,
            updaterDelegate: self, userDriverDelegate: nil)
        self.controller = controller
        controller.updater.updateCheckInterval = 86_400
        controller.updater.publisher(for: \.canCheckForUpdates)
            .sink { [weak self] _ in self?.onChange?() }.store(in: &observations)
        controller.updater.publisher(for: \.automaticallyChecksForUpdates)
            .sink { [weak self] _ in self?.onChange?() }.store(in: &observations)
        controller.updater.publisher(for: \.automaticallyDownloadsUpdates)
            .sink { [weak self] _ in self?.onChange?() }.store(in: &observations)
        readinessObserver = DistributedNotificationCenter.default().addObserver(
            forName: .init("com.ethansk.AgentFlow.updateReadiness.changed.v1"), object: nil,
            queue: .main) { [weak self] _ in Task { @MainActor in self?.resumeIfIdle() } }
        for name in [NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.sessionDidBecomeActiveNotification] {
            workspaceObservers.append(NSWorkspace.shared.notificationCenter.addObserver(
                forName: name, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.resumeIfIdle() } })
        }
        controller.startUpdater()
    }

    func checkForUpdates() { if canCheck { controller?.checkForUpdates(nil) } }
    func toggleAutomaticChecks() { controller?.updater.automaticallyChecksForUpdates = !automaticChecks; onChange?() }
    func toggleAutomaticDownloads() { controller?.updater.automaticallyDownloadsUpdates = !automaticDownloads; onChange?() }
    func resumeIfIdle() { installation.requestCheck() }

    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
                 untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        installation.offer(installHandler)
        return true
    }
    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        Task { await installation.abort() }
    }
}

// A request/response to the exact running Agent Flow PID is authoritative.
// No microphone commands, speech-admission grants, polling or AX permission are
// involved. Old/unresponsive builds fail closed instead of guessing from a file.
@MainActor final class AgentFlowUpdateReadiness {
    static func check() async -> Bool {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.ethansk.VoiceInkPlusPlus")
            .filter { !$0.isTerminated }
        guard !apps.isEmpty else { return true }
        guard apps.count == 1, let app = apps.first else { return false }
        let request = UUID().uuidString
        return await withCheckedContinuation { continuation in
            let probe = AgentFlowUpdateReadiness(request: request, pid: app.processIdentifier) {
                continuation.resume(returning: $0)
            }
            probe.start()
        }
    }

    private let request: String
    private let pid: pid_t
    private var completion: ((Bool) -> Void)?
    private var observer: NSObjectProtocol?
    private var deadline: DispatchWorkItem?
    private init(request: String, pid: pid_t, completion: @escaping (Bool) -> Void) {
        self.request = request; self.pid = pid; self.completion = completion
    }
    private func start() {
        observer = DistributedNotificationCenter.default().addObserver(
            forName: .init("com.ethansk.AgentFlow.updateReadiness.reply.v1"), object: nil,
            queue: .main) { [self] note in
                guard let text = note.object as? String, text.utf8.count < 1_024,
                      let data = text.data(using: .utf8),
                      let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      value["schema"] as? Int == 1, value["requestID"] as? String == request,
                      value["appPID"] as? Int32 == pid, let ready = value["ready"] as? Bool else { return }
                Task { @MainActor in finish(ready) }
            }
        let deadline = DispatchWorkItem { [self] in finish(false) }
        self.deadline = deadline
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: deadline)
        DistributedNotificationCenter.default().postNotificationName(
            .init("com.ethansk.AgentFlow.updateReadiness.request.v1"), object: request,
            userInfo: nil, deliverImmediately: true)
    }
    private func finish(_ allowed: Bool) {
        guard let completion else { return }
        self.completion = nil; deadline?.cancel(); deadline = nil
        if let observer { DistributedNotificationCenter.default().removeObserver(observer) }
        observer = nil
        let running = NSRunningApplication(processIdentifier: pid)
        completion(allowed && running?.isTerminated == false
            && running?.bundleIdentifier == "com.ethansk.VoiceInkPlusPlus")
    }
}
