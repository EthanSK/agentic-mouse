import AppKit
import ApplicationServices
import ScimitarKit

enum WandNewChatTarget: String, Sendable { case codex, claudeCode }

struct WandNewChatRequest: Equatable, Sendable {
    let id: UUID
    let target: WandNewChatTarget

    static func decode(object: String?, info: [AnyHashable: Any]?, now: TimeInterval) -> Self? {
        guard let object, let id = UUID(uuidString: object), let info,
              Set(info.keys.compactMap { $0 as? String }) == ["version", "target", "sentAt"], info.count == 3,
              let version = info["version"] as? NSNumber, CFGetTypeID(version) != CFBooleanGetTypeID(), version.doubleValue == 1,
              let raw = info["target"] as? String, let target = WandNewChatTarget(rawValue: raw),
              let timestamp = info["sentAt"] as? NSNumber, CFGetTypeID(timestamp) != CFBooleanGetTypeID(),
              timestamp.doubleValue.isFinite, now - timestamp.doubleValue <= 10, timestamp.doubleValue - now <= 2
        else { return nil }
        return Self(id: id, target: target)
    }
}

enum WandNewChatFailure: String, Error, Sendable {
    case sessionInactive, cancelled, timedOut, requestInProgress, requestMismatch, alreadyCompleted
    case codexUnavailable, accessibilityDenied, focusChanged, shortcutFailed, composerNotConfirmed
    case claudeCodeUnavailable, workingDirectoryUnavailable, terminalUnavailable, terminalNotConfirmed, automationDenied
}

struct WandNewChatReceipt: Equatable, Sendable {
    let pid: pid_t
    var tty: String? = nil
}

/// One request owns a single create attempt. No launch/shortcut retries occur,
/// and cancelled asynchronous work may not report ready or steal focus later.
@MainActor
final class WandNewChatCoordinator {
    typealias Outcome = Result<WandNewChatReceipt, WandNewChatFailure>
    typealias Adapter = (WandNewChatRequest, @escaping () -> Bool) async -> Outcome
    var onResult: ((WandNewChatRequest, Outcome) -> Void)?
    var onProgress: ((UUID, Bool) -> Void)?
    private let allowed: () -> Bool
    private let adapter: Adapter
    private let scheduler: TickScheduler
    private let clock: MonotonicClock
    private var started: TimeInterval = 0
    private var renewed: TimeInterval = 0
    private var active: WandNewChatRequest?
    private var task: Task<Void, Never>?
    private var finished: [(WandNewChatRequest, Outcome)] = []
    private var cancelled: [UUID] = []

    init(allowed: @escaping () -> Bool, scheduler: TickScheduler = DispatchTickScheduler(),
         clock: MonotonicClock = SystemMonotonicClock(), adapter: @escaping Adapter) {
        self.allowed = allowed; self.adapter = adapter; self.scheduler = scheduler; self.clock = clock
    }

    func handle(_ request: WandNewChatRequest) {
        guard allowed() else { onResult?(request, .failure(.sessionInactive)); return }
        if cancelled.contains(request.id) { onResult?(request, .failure(.cancelled)); return }
        if let prior = finished.first(where: { $0.0.id == request.id }) {
            guard prior.0 == request else { onResult?(request, .failure(.requestMismatch)); return }
            // Ready is a point-in-time focus proof, never a reusable recording grant.
            if case .success = prior.1 { onResult?(request, .failure(.alreadyCompleted)) }
            else { onResult?(request, prior.1) }
            return
        }
        if let active {
            if active.id == request.id {
                if active != request { onResult?(request, .failure(.requestMismatch)) }
            } else { finish(request, .failure(.requestInProgress)) }
            return
        }
        active = request
        started = clock.now; renewed = started
        onProgress?(request.id, true)
        scheduler.start(interval: 0.25) { [weak self] in self?.tick() }
        task = Task { [weak self] in
            guard let self else { return }
            let result = await adapter(request) { [weak self] in
                self?.active == request && self?.allowed() == true && !Task.isCancelled
            }
            guard active == request else { return }
            active = nil; task = nil; scheduler.stop()
            onProgress?(request.id, false)
            finish(request, allowed() && !Task.isCancelled ? result : .failure(.cancelled))
        }
    }

    func cancel(_ id: UUID) {
        if !cancelled.contains(id) { cancelled.append(id); if cancelled.count > 64 { cancelled.removeFirst() } }
        guard let request = active, request.id == id else { return }
        active = nil; task?.cancel(); task = nil; scheduler.stop()
        onProgress?(id, false)
        finish(request, .failure(.cancelled))
    }

    func reset() { if let id = active?.id { cancel(id) } }

    private func tick() {
        guard let request = active else { scheduler.stop(); return }
        guard allowed() else { cancel(request.id); return }
        if clock.now - started >= 25 {
            active = nil; task?.cancel(); task = nil; scheduler.stop()
            if !cancelled.contains(request.id) { cancelled.append(request.id); if cancelled.count > 64 { cancelled.removeFirst() } }
            onProgress?(request.id, false)
            finish(request, .failure(.timedOut))
        } else if clock.now - renewed >= 3 {
            renewed = clock.now
            onProgress?(request.id, true)
        }
    }

    private func finish(_ request: WandNewChatRequest, _ result: Outcome) {
        finished.append((request, result)); if finished.count > 64 { finished.removeFirst() }
        onResult?(request, result)
    }
}

/// Local DistributedNotificationCenter boundary agreed with Agent Flow. It
/// carries only bounded operation IDs/targets/results, never dictated text.
@MainActor
final class WandNewChatService {
    static let requestName = Notification.Name("com.ethansk.AgenticMouse.newChat.v1")
    static let resultName = Notification.Name("com.ethansk.AgenticMouse.newChat.result.v1")
    static let cancelName = Notification.Name("com.ethansk.AgenticMouse.newChat.cancel.v1")
    static let flowProgressName = Notification.Name("com.ethansk.AgentFlow.newChatRecording.result.v1")
    private var observers: [NSObjectProtocol] = []
    private let coordinator: WandNewChatCoordinator
    /// Requests the wand HUD made itself; their results are not Agent Flow's.
    private var localRequests: Set<UUID> = []
    private let status: WandChatCreationStatusController

    init(allowed: @escaping () -> Bool, status: WandChatCreationStatusController,
         createCodex: @escaping () -> Bool) {
        self.status = status
        let native = WandNewChatAdapter(createCodex: createCodex)
        coordinator = WandNewChatCoordinator(allowed: allowed, adapter: native.perform)
        coordinator.onProgress = { [weak status] id, visible in
            status?.handle(.init(id: id, phase: visible ? .show : .hide))
        }
        coordinator.onResult = { [weak self] request, result in
            if self?.localRequests.remove(request.id) != nil { return }
            var info: [String: Any] = ["version": 1, "target": request.target.rawValue, "sentAt": Date().timeIntervalSince1970]
            switch result {
            case .success(let receipt):
                info["status"] = "ready"; info["reason"] = ""; info["pid"] = receipt.pid
                if let tty = receipt.tty { info["tty"] = tty }
            case .failure(let error): info["status"] = "failed"; info["reason"] = error.rawValue
            }
            DistributedNotificationCenter.default().postNotificationName(Self.resultName,
                object: request.id.uuidString, userInfo: info, deliverImmediately: true)
        }
    }

    func start() {
        guard observers.isEmpty else { return }
        let center = DistributedNotificationCenter.default()
        observers.append(center.addObserver(forName: Self.requestName, object: nil, queue: .main) { [weak self] note in
            guard let request = WandNewChatRequest.decode(object: note.object as? String, info: note.userInfo,
                now: Date().timeIntervalSince1970) else { return }
            Task { @MainActor in self?.coordinator.handle(request) }
        })
        observers.append(center.addObserver(forName: Self.cancelName, object: nil, queue: .main) { [weak self] note in
            guard let value = note.object as? String, let id = UUID(uuidString: value) else { return }
            Task { @MainActor in self?.coordinator.cancel(id) }
        })
        observers.append(center.addObserver(forName: Self.flowProgressName, object: nil, queue: .main) { [weak self] note in
            guard let value = note.object as? String, let id = UUID(uuidString: value),
                  let phase = note.userInfo?["phase"] as? String, ["creating", "ready", "failed"].contains(phase) else { return }
            Task { @MainActor in self?.status.handle(.init(id: id, phase: phase == "creating" ? .show : .hide)) }
        })
    }

    /// The wand's New Codex chat card: activate Codex and create one chat.
    /// It never starts recording and never changes the preferred harness.
    func createCodexChat() {
        let request = WandNewChatRequest(id: UUID(), target: .codex)
        localRequests.insert(request.id)
        coordinator.handle(request)
    }

    func reset() { coordinator.reset(); status.reset() }
    func stop() {
        observers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
        observers.removeAll(); reset()
    }
}

@MainActor
final class WandNewChatAdapter {
    private let createCodex: () -> Bool
    private let terminal = WandTerminalAppleScript()
    init(createCodex: @escaping () -> Bool) { self.createCodex = createCodex }

    func perform(_ request: WandNewChatRequest, valid: @escaping () -> Bool) async -> WandNewChatCoordinator.Outcome {
        guard valid() else { return .failure(.cancelled) }
        switch request.target {
        case .codex: return await codex(valid: valid)
        case .claudeCode: return await claudeCode(request.id, valid: valid)
        }
    }

    private func codex(valid: @escaping () -> Bool) async -> WandNewChatCoordinator.Outcome {
        let origin = NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard AXIsProcessTrusted() else { return .failure(.accessibilityDenied) }
        guard let app = await runningApplication(bundle: CodexMode.bundleIdentifier, valid: valid) else { return .failure(.codexUnavailable) }
        guard valid() else { return .failure(.cancelled) }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == origin || app.isActive else { return .failure(.focusChanged) }
        app.activate(options: [.activateIgnoringOtherApps])
        guard await wait(valid: valid, check: { app.isActive }) else { return .failure(.focusChanged) }
        let before = await WandComposerProbe.snapshot(pid: app.processIdentifier)
        guard valid(), app.isActive, createCodex() else { return .failure(.shortcutFailed) }
        let end = ProcessInfo.processInfo.systemUptime + 5
        var ready = false
        while valid(), app.isActive, ProcessInfo.processInfo.systemUptime < end {
            let snapshot = await WandComposerProbe.snapshot(pid: app.processIdentifier)
            guard valid(), app.isActive else { return .failure(.cancelled) }
            if let input = snapshot.input, snapshot.empty, snapshot.ownsKeyboard,
               before.input.map({ !CFEqual($0,input) }) == true || snapshot.newChatWindow {
                ready = true; break
            }
            try? await Task.sleep(nanoseconds: 80_000_000)
        }
        guard valid() else { return .failure(.cancelled) }
        return ready ? .success(.init(pid: app.processIdentifier)) : .failure(.composerNotConfirmed)
    }

    private func claudeCode(_ id: UUID, valid: @escaping () -> Bool) async -> WandNewChatCoordinator.Outcome {
        let origin = NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard let executable = Self.claudeExecutable() else { return .failure(.claudeCodeUnavailable) }
        let cwd = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Projects").resolvingSymlinksInPath()
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: cwd.path, isDirectory: &directory), directory.boolValue,
              FileManager.default.isReadableFile(atPath: cwd.path) else { return .failure(.workingDirectoryUnavailable) }
        guard let app = await runningApplication(bundle: "com.apple.Terminal", valid: valid) else { return .failure(.terminalUnavailable) }
        guard valid() else { return .failure(.cancelled) }
        let shell = Self.claudeShell(executable: executable.path, cwd: cwd.path, id: id)
        let launched = await terminal.run("""
        with timeout of 5 seconds
            tell application id "com.apple.Terminal"
                set createdTab to do script \(Self.appleScriptLiteral(shell))
                return tty of createdTab
            end tell
        end timeout
        """)
        guard valid() else { return .failure(.cancelled) }
        guard case .success(let tty) = launched, tty.hasPrefix("/dev/tty"), tty.count < 64 else {
            if case .failure(let code) = launched, code.code == -1743 { return .failure(.automationDenied) }
            return .failure(.terminalNotConfirmed)
        }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == origin || app.isActive else { return .failure(.focusChanged) }
        app.activate(options: [.activateIgnoringOtherApps])
        guard await wait(valid: valid, check: { app.isActive }) else { return .failure(.focusChanged) }
        let end = ProcessInfo.processInfo.systemUptime + 12
        while valid(), ProcessInfo.processInfo.systemUptime < end {
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else { return .failure(.focusChanged) }
            let state = await terminal.run(Self.terminalProbeScript(tty: tty))
            guard valid() else { return .failure(.cancelled) }
            if case .success(let text) = state, Self.terminalReady(text),
               NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier {
                return .success(.init(pid: app.processIdentifier, tty: tty))
            }
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
        return .failure(valid() ? .terminalNotConfirmed : .cancelled)
    }

    private func runningApplication(bundle: String, valid: @escaping () -> Bool) async -> NSRunningApplication? {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first { return app }
        guard valid(), let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else { return nil }
        let configuration = NSWorkspace.OpenConfiguration(); configuration.activates = false
        return await withCheckedContinuation { continuation in
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { app, _ in continuation.resume(returning: app) }
        }
    }

    private func wait(valid: @escaping () -> Bool, check: () -> Bool) async -> Bool {
        let end = ProcessInfo.processInfo.systemUptime + 5
        repeat {
            guard valid() else { return false }
            if check() { return true }
            try? await Task.sleep(nanoseconds: 80_000_000)
        } while ProcessInfo.processInfo.systemUptime < end
        return false
    }

    static func claudeExecutable() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [home.appendingPathComponent(".local/bin/claude"), URL(fileURLWithPath: "/opt/homebrew/bin/claude"), URL(fileURLWithPath: "/usr/local/bin/claude")]
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    static func shellQuote(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    static func appleScriptLiteral(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
    static func claudeShell(executable: String, cwd: String, id: UUID) -> String {
        "cd -- " + shellQuote(cwd) + " && exec " + shellQuote(executable) + " --session-id " + shellQuote(id.uuidString)
    }
    static func terminalReady(_ text: String) -> Bool {
        let parts = text.components(separatedBy: "\u{1f}")
        guard parts.count == 2, parts[0].lowercased().contains("claude") else { return false }
        // Only the newest prompt counts. An empty shell/CLI prompt above a
        // later trust choice or typed draft is not a recording destination.
        guard let prompt = parts[1].components(separatedBy: .newlines)
            .map({ $0.trimmingCharacters(in: .whitespaces) })
            .last(where: { $0.hasPrefix("❯") }) else { return false }
        let tail = prompt.dropFirst().trimmingCharacters(in: .whitespaces)
        return tail.isEmpty || tail.hasPrefix("Try ")
    }
    static func terminalProbeScript(tty: String) -> String {
        """
        with timeout of 2 seconds
            tell application id "com.apple.Terminal"
                set currentTab to selected tab of front window
                if tty of currentTab is not \(appleScriptLiteral(tty)) then error number -128
                set AppleScript's text item delimiters to ","
                set runningNames to processes of currentTab as text
                return runningNames & (ASCII character 31) & contents of currentTab
            end tell
        end timeout
        """
    }
}

/// Small, bounded AX checks reuse the focused-composer ownership pattern used
/// by Model Bar. No draft content is logged or retained beyond an empty check.
private struct WandComposerSnapshot: @unchecked Sendable {
    let input: AXUIElement?
    let empty: Bool
    let newChatWindow: Bool
    let ownsKeyboard: Bool
}

private enum WandComposerProbe {
    private static let queue = DispatchQueue(label: "com.ethan.agentic-mouse.wand-composer",qos:.userInitiated)
    static func snapshot(pid:pid_t) async -> WandComposerSnapshot {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: read(pid:pid)) }
        }
    }
    private static func attribute(_ element:AXUIElement,_ key:String)->CFTypeRef? {
        var value:CFTypeRef?
        return AXUIElementCopyAttributeValue(element,key as CFString,&value) == .success ? value:nil
    }
    private static func element(_ root:AXUIElement,_ key:String)->AXUIElement? {
        guard let raw=attribute(root,key),CFGetTypeID(raw)==AXUIElementGetTypeID() else{return nil}
        return unsafeBitCast(raw,to:AXUIElement.self)
    }
    private static func read(pid:pid_t)->WandComposerSnapshot {
        let app=AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app,0.1)
        // Same Chromium assistive-client opt-in used by the installed Model Bar.
        _=AXUIElementSetAttributeValue(app,"AXManualAccessibility" as CFString,kCFBooleanTrue)
        let window=element(app,kAXFocusedWindowAttribute)
        var input=element(app,kAXFocusedUIElementAttribute)
        if input.map({attribute($0,kAXRoleAttribute) as? String == kAXTextAreaRole as String}) != true {
            input=nil
            // Chromium sometimes gives app focus to a group while the actual
            // composer still has AXFocused. Search only that focused window.
            var nodes=window.map{[$0]} ?? [];var index=0
            let deadline=ProcessInfo.processInfo.systemUptime+0.35
            while index<nodes.count,index<2000,ProcessInfo.processInfo.systemUptime<deadline {
                let item=nodes[index];index+=1
                if attribute(item,kAXRoleAttribute) as? String == kAXTextAreaRole as String,
                   attribute(item,kAXFocusedAttribute) as? Bool == true {input=item;break}
                nodes += attribute(item,kAXChildrenAttribute) as? [AXUIElement] ?? []
            }
        }
        let value=input.flatMap{attribute($0,kAXValueAttribute) as? String}
        let placeholder=input.flatMap{attribute($0,kAXTitleAttribute) as? String}
        let empty=value.map{$0.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || $0 == placeholder} ?? false
        let title=window.flatMap{attribute($0,kAXTitleAttribute) as? String}?.lowercased() ?? ""
        var keyboardPID:pid_t=0
        let system=AXUIElementCreateSystemWide();AXUIElementSetMessagingTimeout(system,0.1)
        if let focused=element(system,kAXFocusedUIElementAttribute){_=AXUIElementGetPid(focused,&keyboardPID)}
        return WandComposerSnapshot(input:input,empty:empty,
            newChatWindow:title.hasPrefix("new chat") || title.hasPrefix("new task"),ownsKeyboard:keyboardPID==pid)
    }
}

/// Apple Events stay on one private queue, following the Spotify adapter.
/// No activation is embedded in a queued script: cancellation is checked on
/// the main actor before any explicit foreground activation.
private struct WandTerminalScriptFailure: Error { let code: Int }

private final class WandScriptTicket: @unchecked Sendable {
    private let lock=NSLock()
    private var cancelled=false
    func cancel(){lock.lock();cancelled=true;lock.unlock()}
    var isActive:Bool {lock.lock();defer{lock.unlock()};return !cancelled}
}

private final class WandTerminalAppleScript: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.ethan.agentic-mouse.wand-terminal")
    func run(_ source:String) async -> Result<String,WandTerminalScriptFailure> {
        let ticket=WandScriptTicket()
        return await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { continuation in
                queue.async {
                    guard ticket.isActive else {continuation.resume(returning:.failure(.init(code:-128)));return}
                    var error:NSDictionary?
                    let result=NSAppleScript(source:source)?.executeAndReturnError(&error)
                    if let code=error?["NSAppleScriptErrorNumber"] as? Int {continuation.resume(returning:.failure(.init(code:code)))}
                    else if let value=result?.stringValue {continuation.resume(returning:.success(value))}
                    else {continuation.resume(returning:.failure(.init(code:-1)))}
                }
            }
        },onCancel:{ticket.cancel()})
    }
}
