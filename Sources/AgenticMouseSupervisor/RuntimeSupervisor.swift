import AppKit
import Foundation
import os

struct RuntimeSupervisorRecoveryPolicy {
    enum Decision: Equatable {
        case none
        case launch
        case paused(TimeInterval)
    }

    static let stableRuntime: TimeInterval = 60
    static let attemptWindow: TimeInterval = 120
    static let maximumAttempts = 5
    static let crashLoopPause: TimeInterval = 300
    static let retryDelays: [TimeInterval] = [2, 5, 10, 30, 60]

    private(set) var attemptTimes: [TimeInterval] = []
    private(set) var runningSince: TimeInterval?
    private(set) var nextEligibleAttempt: TimeInterval = 0

    mutating func observe(isRunning: Bool, now: TimeInterval) -> Decision {
        if isRunning {
            if runningSince == nil { runningSince = now }
            if let runningSince, now - runningSince >= Self.stableRuntime {
                attemptTimes.removeAll()
                nextEligibleAttempt = now
            }
            return .none
        }

        runningSince = nil
        attemptTimes.removeAll { now - $0 > Self.attemptWindow }
        guard now >= nextEligibleAttempt else { return .none }

        if attemptTimes.count >= Self.maximumAttempts {
            nextEligibleAttempt = now + Self.crashLoopPause
            return .paused(Self.crashLoopPause)
        }

        attemptTimes.append(now)
        let delayIndex = min(attemptTimes.count - 1, Self.retryDelays.count - 1)
        nextEligibleAttempt = now + Self.retryDelays[delayIndex]
        return .launch
    }
}

enum OuterApplicationLocator {
    static func locate(
        from executableURL: URL,
        expectedBundleIdentifier: String
    ) -> URL? {
        var current = executableURL.resolvingSymlinksInPath().deletingLastPathComponent()
        var candidates: [URL] = []

        while current.path != "/" {
            if current.pathExtension.caseInsensitiveCompare("app") == .orderedSame {
                candidates.append(current)
            }
            current.deleteLastPathComponent()
        }

        return candidates.first { candidate in
            Bundle(url: candidate)?.bundleIdentifier == expectedBundleIdentifier
        }
    }
}

protocol SupervisedApplicationManaging: AnyObject {
    func isRunning(bundleIdentifier: String) -> Bool
    func userSessionAllowsRelaunch() -> Bool
    func launch(
        applicationURL: URL,
        completion: @escaping (Error?) -> Void
    )
}

final class WorkspaceSupervisedApplicationManager: SupervisedApplicationManaging {
    private static let blockedSessionOwners: Set<String> = [
        "com.apple.loginwindow",
        "com.apple.ScreenSaver.Engine",
        "com.apple.ScreenSaver",
    ]

    private let workspace: NSWorkspace

    init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
    }

    func isRunning(bundleIdentifier: String) -> Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .contains { !$0.isTerminated }
    }

    func userSessionAllowsRelaunch() -> Bool {
        guard let frontmost = workspace.frontmostApplication else { return false }
        guard let identifier = frontmost.bundleIdentifier else { return false }
        return !Self.blockedSessionOwners.contains(identifier)
    }

    func launch(
        applicationURL: URL,
        completion: @escaping (Error?) -> Void
    ) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        configuration.createsNewApplicationInstance = false
        configuration.allowsRunningApplicationSubstitution = false
        configuration.promptsUserIfNeeded = false
        workspace.openApplication(at: applicationURL, configuration: configuration) { _, error in
            completion(error)
        }
    }
}

final class AgenticMouseRuntimeSupervisor {
    static let applicationBundleIdentifier = "com.ethan.agentic-mouse"
    static let pollInterval: TimeInterval = 2
    static let launchCompletionTimeout: TimeInterval = 15

    private let applicationURL: URL
    private let manager: SupervisedApplicationManaging
    private let now: () -> TimeInterval
    private let log: Logger
    private var policy = RuntimeSupervisorRecoveryPolicy()
    private var timer: DispatchSourceTimer?
    private var launchStartedAt: TimeInterval?
    private var relaunchWasDeferredForSession = false

    init(
        applicationURL: URL,
        manager: SupervisedApplicationManaging = WorkspaceSupervisedApplicationManager(),
        now: @escaping () -> TimeInterval = {
            Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
        },
        log: Logger = Logger(
            subsystem: "com.ethan.agentic-mouse.runtime-supervisor",
            category: "runtime"
        )
    ) {
        self.applicationURL = applicationURL
        self.manager = manager
        self.now = now
        self.log = log
    }

    func start() {
        guard timer == nil else { return }
        checkNow()
        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(
            deadline: .now() + Self.pollInterval,
            repeating: Self.pollInterval,
            leeway: .milliseconds(100)
        )
        source.setEventHandler { [weak self] in self?.checkNow() }
        source.resume()
        timer = source
        log.info("runtime supervision started for \(self.applicationURL.path, privacy: .public)")
    }

    func stop() {
        timer?.cancel()
        timer = nil
        launchStartedAt = nil
    }

    func checkNow() {
        let timestamp = now()
        let isRunning = manager.isRunning(bundleIdentifier: Self.applicationBundleIdentifier)
        if isRunning {
            launchStartedAt = nil
            relaunchWasDeferredForSession = false
        } else if let startedAt = launchStartedAt,
                  timestamp - startedAt >= Self.launchCompletionTimeout {
            launchStartedAt = nil
            log.error("runtime launch request timed out")
        }

        if !isRunning, !manager.userSessionAllowsRelaunch() {
            if !relaunchWasDeferredForSession {
                log.notice("runtime absent while loginwindow owns the session; relaunch deferred")
                relaunchWasDeferredForSession = true
            }
            return
        }
        relaunchWasDeferredForSession = false

        let decision = policy.observe(isRunning: isRunning, now: timestamp)
        switch decision {
        case .none:
            return
        case .paused(let duration):
            log.fault("runtime restart loop paused for \(duration, privacy: .public) seconds")
        case .launch:
            guard launchStartedAt == nil else { return }
            launchStartedAt = timestamp
            log.notice("Agentic Mouse runtime absent; requesting background relaunch")
            manager.launch(applicationURL: applicationURL) { [weak self] error in
                let complete = {
                    guard let self else { return }
                    self.launchStartedAt = nil
                    if let error {
                        self.log.error("runtime relaunch request failed: \(error.localizedDescription, privacy: .public)")
                    } else {
                        self.log.info("runtime relaunch request accepted")
                    }
                }
                if Thread.isMainThread {
                    complete()
                } else {
                    DispatchQueue.main.async(execute: complete)
                }
            }
        }
    }

    deinit { timer?.cancel() }
}
