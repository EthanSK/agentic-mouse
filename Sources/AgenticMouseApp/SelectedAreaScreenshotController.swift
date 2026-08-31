import AppKit
import ApplicationServices
import Foundation
import ScimitarKit
import UniformTypeIdentifiers

enum InteractiveScreenshotResult: Equatable {
    case completed
    case cancelled
    case failed(String)
}

@MainActor
protocol InteractiveScreenshotProcess: AnyObject {
    var isRunning: Bool { get }
    var onTermination: ((InteractiveScreenshotResult) -> Void)? { get set }
    func run() throws
    func cancel()
}

enum ScreenshotClipboardError: Error, Equatable, LocalizedError {
    case screenshotDirectoryUnavailable
    case screenshotFileNotFound
    case screenshotFileAmbiguous
    case screenshotImageUnreadable
    case screenshotNoLongerAvailable
    case pasteTargetUnavailable
    case inputBlocked
    case accessibilityPermissionMissing
    case pasteEventCreationFailed

    var errorDescription: String? {
        switch self {
        case .screenshotDirectoryUnavailable:
            "Could not read the configured Screenshot folder"
        case .screenshotFileNotFound:
            "Screenshot saved, but its image could not be found to copy"
        case .screenshotFileAmbiguous:
            "Screenshot saved, but more than one new image was found"
        case .screenshotImageUnreadable:
            "Screenshot saved, but its image was not ready to copy"
        case .screenshotNoLongerAvailable:
            "The saved screenshot is no longer available"
        case .pasteTargetUnavailable:
            "Could not find the current app to paste into"
        case .inputBlocked:
            "Mouse commands are disabled while macOS is locked"
        case .accessibilityPermissionMissing:
            "Accessibility permission is required to paste the screenshot"
        case .pasteEventCreationFailed:
            "Could not send Paste"
        }
    }
}

struct ScreenshotCaptureBaseline: Equatable {
    let directoryURL: URL
    let existingPaths: Set<String>
    let startedAt: Date
}

@MainActor
protocol ScreenshotClipboardCoordinating: AnyObject {
    var hasPasteableScreenshot: Bool { get }
    var isCapturePending: Bool { get }
    func prepareForCapture()
    func discardPreparedCapture()
    func resolveCompletedCapture(
        completion: @escaping (Result<URL, ScreenshotClipboardError>) -> Void
    )
    func pasteScreenshot() -> Result<Void, ScreenshotClipboardError>
    func cancel(clearOwnership: Bool)
}

/// Watches only the configured macOS Screenshot destination after the native
/// Shift-Command-4 interaction completes. It remembers the exact saved path
/// without occupying the pasteboard, then uses a short restoring paste lease
/// only when the user explicitly double-presses the screenshot button.
@MainActor
final class NativeScreenshotClipboardCoordinator: ScreenshotClipboardCoordinating {
    typealias DirectoryResolver = @MainActor () -> URL?
    typealias DirectorySnapshotter = @MainActor (_ directoryURL: URL) -> Set<String>?
    typealias CandidateFinder = @MainActor (_ baseline: ScreenshotCaptureBaseline) -> [URL]
    typealias ScreenshotMetadataChecker = @MainActor (_ url: URL) -> Bool
    typealias PasteboardWriter = @MainActor (
        _ pasteboard: NSPasteboard,
        _ url: URL,
        _ identifier: String
    ) -> Int?
    typealias PasteEventPoster = @MainActor (_ processIdentifier: pid_t) -> Bool
    typealias FrontmostProcessIdentifierProvider = @MainActor () -> pid_t?
    typealias RestoreScheduler = @MainActor (
        _ action: @escaping @MainActor @Sendable () -> Void
    ) -> Void
    typealias AccessibilityTrustProvider = @MainActor () -> Bool
    typealias InputAllowedProvider = @MainActor () -> Bool

    static let pollInterval: TimeInterval = 0.10
    static let captureResolutionTimeout: TimeInterval = 60
    static let pasteboardRestoreDelay: TimeInterval = 0.25
    private static let markerType = NSPasteboard.PasteboardType(
        "com.ethansk.agentic-mouse.screenshot-paste-session"
    )

    private struct PasteLease {
        let identifier: String
        let changeCount: Int
        let snapshot: PasteboardSnapshot

        @MainActor
        func isOwned(on pasteboard: NSPasteboard) -> Bool {
            guard pasteboard.changeCount == changeCount else { return false }
            return pasteboard.string(forType: NativeScreenshotClipboardCoordinator.markerType)
                == identifier
        }
    }

    private let scheduler: TickScheduler
    private let clock: MonotonicClock
    private let now: @MainActor () -> Date
    private let resolveDirectory: DirectoryResolver
    private let snapshotDirectory: DirectorySnapshotter
    private let findCandidates: CandidateFinder
    private let metadataMarksScreenshot: ScreenshotMetadataChecker
    private let pasteboard: NSPasteboard
    private let writeToPasteboard: PasteboardWriter
    private let postPaste: PasteEventPoster
    private let frontmostProcessIdentifier: FrontmostProcessIdentifierProvider
    private let scheduleRestore: RestoreScheduler
    private let accessibilityTrusted: AccessibilityTrustProvider
    private let inputAllowed: InputAllowedProvider

    private var preparedBaseline: ScreenshotCaptureBaseline?
    private var captureResolutionCompletion: ((Result<URL, ScreenshotClipboardError>) -> Void)?
    private var captureResolutionDeadline: TimeInterval?
    private var pasteableScreenshotURL: URL?
    private var activePasteLease: PasteLease?
    private var lastCandidateFailure: ScreenshotClipboardError?

    init(
        scheduler: TickScheduler = DispatchTickScheduler(),
        clock: MonotonicClock = SystemMonotonicClock(),
        now: @escaping @MainActor () -> Date = Date.init,
        resolveDirectory: @escaping DirectoryResolver =
            NativeScreenshotClipboardCoordinator.configuredScreenshotDirectory,
        snapshotDirectory: @escaping DirectorySnapshotter =
            NativeScreenshotClipboardCoordinator.snapshotDirectory,
        findCandidates: @escaping CandidateFinder =
            NativeScreenshotClipboardCoordinator.findCandidateImages,
        metadataMarksScreenshot: @escaping ScreenshotMetadataChecker =
            NativeScreenshotClipboardCoordinator.metadataMarksScreenshot,
        pasteboard: NSPasteboard = .general,
        writeToPasteboard: @escaping PasteboardWriter =
            NativeScreenshotClipboardCoordinator.writeImageToPasteboard,
        postPaste: @escaping PasteEventPoster =
            NativeScreenshotClipboardCoordinator.postCommandV,
        frontmostProcessIdentifier: @escaping FrontmostProcessIdentifierProvider = {
            NSWorkspace.shared.frontmostApplication?.processIdentifier
        },
        scheduleRestore: @escaping RestoreScheduler = { action in
            DispatchQueue.main.asyncAfter(
                deadline: .now() + NativeScreenshotClipboardCoordinator.pasteboardRestoreDelay,
                execute: action
            )
        },
        accessibilityTrusted: @escaping AccessibilityTrustProvider = AXIsProcessTrusted,
        inputAllowed: @escaping InputAllowedProvider = { true }
    ) {
        self.scheduler = scheduler
        self.clock = clock
        self.now = now
        self.resolveDirectory = resolveDirectory
        self.snapshotDirectory = snapshotDirectory
        self.findCandidates = findCandidates
        self.metadataMarksScreenshot = metadataMarksScreenshot
        self.pasteboard = pasteboard
        self.writeToPasteboard = writeToPasteboard
        self.postPaste = postPaste
        self.frontmostProcessIdentifier = frontmostProcessIdentifier
        self.scheduleRestore = scheduleRestore
        self.accessibilityTrusted = accessibilityTrusted
        self.inputAllowed = inputAllowed
    }

    var hasPasteableScreenshot: Bool {
        pasteableScreenshotURL != nil
    }

    var isCapturePending: Bool { captureResolutionCompletion != nil }

    func prepareForCapture() {
        preparedBaseline = nil
        guard let directoryURL = resolveDirectory(),
              let paths = snapshotDirectory(directoryURL)
        else { return }
        preparedBaseline = ScreenshotCaptureBaseline(
            directoryURL: directoryURL,
            existingPaths: paths,
            startedAt: now()
        )
    }

    func discardPreparedCapture() {
        preparedBaseline = nil
    }

    func resolveCompletedCapture(
        completion: @escaping (Result<URL, ScreenshotClipboardError>) -> Void
    ) {
        scheduler.stop()
        captureResolutionCompletion = completion
        captureResolutionDeadline = clock.now + Self.captureResolutionTimeout
        lastCandidateFailure = nil

        guard preparedBaseline != nil else {
            finishCaptureResolution(.failure(.screenshotDirectoryUnavailable))
            return
        }
        pollForSavedScreenshot()
        if isCapturePending {
            scheduler.start(interval: Self.pollInterval) { [weak self] in
                self?.pollForSavedScreenshot()
            }
        }
    }

    func pasteScreenshot() -> Result<Void, ScreenshotClipboardError> { // Keeping only the saved path avoids VoiceInk or another copy replacing a long-lived screenshot clipboard; the double-click takes a short ownership-marked lease, pastes to the then-frontmost app, and restores only if nothing else changed the clipboard. (Codex task: 01a039f7-873c-7c30-b3dc-af8a6724ace5)
        guard inputAllowed() else { return .failure(.inputBlocked) }
        guard accessibilityTrusted() else {
            return .failure(.accessibilityPermissionMissing)
        }
        guard let screenshotURL = pasteableScreenshotURL else {
            return .failure(.screenshotNoLongerAvailable)
        }
        guard let processIdentifier = frontmostProcessIdentifier() else {
            return .failure(.pasteTargetUnavailable)
        }

        let snapshot: PasteboardSnapshot
        if let activePasteLease, activePasteLease.isOwned(on: pasteboard) {
            snapshot = activePasteLease.snapshot
        } else {
            let firstSnapshot = PasteboardSnapshot(capturing: pasteboard)
            snapshot = firstSnapshot.sourceChangeCount == pasteboard.changeCount
                ? firstSnapshot
                : PasteboardSnapshot(capturing: pasteboard)
        }
        let identifier = UUID().uuidString
        guard let changeCount = writeToPasteboard(pasteboard, screenshotURL, identifier) else {
            pasteableScreenshotURL = nil
            return .failure(.screenshotImageUnreadable)
        }
        let lease = PasteLease(
            identifier: identifier,
            changeCount: changeCount,
            snapshot: snapshot
        )
        guard lease.isOwned(on: pasteboard) else {
            return .failure(.screenshotNoLongerAvailable)
        }
        activePasteLease = lease
        guard postPaste(processIdentifier) else {
            restoreIfOwned(lease)
            return .failure(.pasteEventCreationFailed)
        }
        scheduleRestore { [weak self] in self?.restoreIfOwned(lease) }
        return .success(())
    }

    func cancel(clearOwnership: Bool) {
        scheduler.stop()
        preparedBaseline = nil
        captureResolutionCompletion = nil
        captureResolutionDeadline = nil
        lastCandidateFailure = nil
        if let activePasteLease { restoreIfOwned(activePasteLease) }
        if clearOwnership { pasteableScreenshotURL = nil }
    }

    private func pollForSavedScreenshot() {
        guard let baseline = preparedBaseline,
              captureResolutionCompletion != nil,
              let captureResolutionDeadline
        else { return }

        let candidates = findCandidates(baseline)
        let marked = candidates.filter(metadataMarksScreenshot)
        let candidate: URL?
        if marked.count == 1 {
            candidate = marked[0]
        } else if marked.count > 1 {
            candidate = nil
            lastCandidateFailure = .screenshotFileAmbiguous
        } else if candidates.count == 1 {
            candidate = candidates[0]
        } else {
            candidate = nil
            if candidates.count > 1 {
                lastCandidateFailure = .screenshotFileAmbiguous
            }
        }

        if let candidate {
            pasteableScreenshotURL = candidate
            finishCaptureResolution(.success(candidate))
            return
        }

        guard clock.now >= captureResolutionDeadline else { return }
        finishCaptureResolution(.failure(lastCandidateFailure ?? .screenshotFileNotFound))
    }

    private func finishCaptureResolution(_ result: Result<URL, ScreenshotClipboardError>) {
        scheduler.stop()
        let completion = captureResolutionCompletion
        captureResolutionCompletion = nil
        captureResolutionDeadline = nil
        preparedBaseline = nil
        lastCandidateFailure = nil
        completion?(result)
    }

    private func restoreIfOwned(_ lease: PasteLease) {
        guard lease.isOwned(on: pasteboard) else { return }
        lease.snapshot.restore(to: pasteboard)
        if activePasteLease?.identifier == lease.identifier { activePasteLease = nil }
    }

    static func configuredScreenshotDirectory() -> URL? {
        let rawLocation = UserDefaults(suiteName: "com.apple.screencapture")?
            .string(forKey: "location")
        if let rawLocation, !rawLocation.isEmpty {
            let expanded = NSString(string: rawLocation).expandingTildeInPath
            return URL(fileURLWithPath: expanded, isDirectory: true)
                .standardizedFileURL
                .resolvingSymlinksInPath()
        }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)
            .first?
            .standardizedFileURL
            .resolvingSymlinksInPath()
    }

    static func snapshotDirectory(_ directoryURL: URL) -> Set<String>? {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return nil }
        return Set(urls.map(canonicalPath))
    }

    static func findCandidateImages(_ baseline: ScreenshotCaptureBaseline) -> [URL] {
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .creationDateKey,
            .contentModificationDateKey,
            .fileSizeKey,
        ]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: baseline.directoryURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return urls.filter { url in
            guard !baseline.existingPaths.contains(canonicalPath(url)),
                  let type = UTType(filenameExtension: url.pathExtension),
                  type.conforms(to: .image),
                  let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true,
                  (values.fileSize ?? 0) > 0
            else { return false }
            let writtenAt = values.contentModificationDate ?? values.creationDate ?? .distantPast
            return writtenAt >= baseline.startedAt.addingTimeInterval(-1)
        }
    }

    static func metadataMarksScreenshot(_ url: URL) -> Bool {
        guard let item = MDItemCreate(kCFAllocatorDefault, url.path as CFString),
              let value = MDItemCopyAttribute(
                item,
                "kMDItemIsScreenCapture" as CFString
              )
        else { return false }
        return (value as? NSNumber)?.boolValue == true
    }

    static func writeImageToPasteboard(
        _ pasteboard: NSPasteboard,
        _ url: URL,
        _ identifier: String
    ) -> Int? {
        guard let data = try? Data(contentsOf: url),
              let image = NSImage(data: data),
              let tiff = image.tiffRepresentation,
              let type = UTType(filenameExtension: url.pathExtension)
        else { return nil }

        let item = NSPasteboardItem()
        item.setData(data, forType: NSPasteboard.PasteboardType(type.identifier))
        item.setData(tiff, forType: .tiff)
        item.setString(url.absoluteString, forType: .fileURL)
        item.setString(identifier, forType: markerType)
        pasteboard.clearContents()
        guard pasteboard.writeObjects([item]) else { return nil }
        return pasteboard.changeCount
    }

    static func postCommandV(to processIdentifier: pid_t) -> Bool {
        let commandKeyCode: CGKeyCode = 55
        let pasteKeyCode: CGKeyCode = 9
        let flags: CGEventFlags = [.maskCommand]
        return SyntheticKeyboardChordPoster.shared.post([
            .modifier(keyCode: commandKeyCode, flags: flags, at: 0),
            .key(keyCode: pasteKeyCode, flags: flags, isDown: true, at: 0.006),
            .key(keyCode: pasteKeyCode, flags: flags, isDown: false, at: 0.026),
            .modifier(keyCode: commandKeyCode, flags: [], at: 0.032),
        ], to: processIdentifier)
    }

    private static func canonicalPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }
}

/// Owns one native selected-area screenshot interaction plus the bounded
/// single/double-press classification for its shared physical button. A single
/// press starts the native capture after the short classifier window. A rapid
/// second press from the same mouse pastes the screenshot Agentic Mouse most
/// recently saved. Once the native crosshair is running, the next press keeps
/// its established meaning and sends Escape to cancel that exact interaction.
@MainActor
final class SelectedAreaScreenshotController {
    enum TriggerResult: Equatable {
        case awaitingSinglePress
        case started
        case cancelled
        case pasteQueued
        case pasted
        case blocked
        case failed(String)
    }

    enum ButtonState: Equatable {
        case screenshot
        case cancelScreenshot
        case copyingScreenshot
        case screenshotReadyToPaste
    }

    typealias ProcessFactory = @MainActor () -> InteractiveScreenshotProcess
    typealias InputAllowedProvider = @MainActor () -> Bool

    static let doublePressInterval: TimeInterval = 0.28

    private let makeProcess: ProcessFactory
    private let inputAllowed: InputAllowedProvider
    private let gestureScheduler: TickScheduler
    private let clipboardCoordinator: ScreenshotClipboardCoordinating
    private var activeProcess: InteractiveScreenshotProcess?
    private var activeSource: MouseSource?
    private var pendingSource: MouseSource?
    private var pasteWhenCaptureResolvesForSource: MouseSource?
    private var generation: UInt64 = 0
    var onStateChange: (() -> Void)?
    var onCompletion: ((InteractiveScreenshotResult) -> Void)?
    var onAsynchronousResult: ((MouseSource, TriggerResult) -> Void)?
    var onScreenshotReady: ((MouseSource, Result<URL, ScreenshotClipboardError>) -> Void)?

    init(
        makeProcess: ProcessFactory? = nil,
        gestureScheduler: TickScheduler = DispatchTickScheduler(),
        clipboardCoordinator: ScreenshotClipboardCoordinating? = nil,
        inputAllowed: @escaping InputAllowedProvider = { true }
    ) {
        self.makeProcess = makeProcess ?? { NativeInteractiveScreenshotProcess() }
        self.gestureScheduler = gestureScheduler
        self.clipboardCoordinator = clipboardCoordinator
            ?? NativeScreenshotClipboardCoordinator(inputAllowed: inputAllowed)
        self.inputAllowed = inputAllowed
    }

    var isCapturing: Bool { activeProcess?.isRunning == true }

    var buttonState: ButtonState {
        if isCapturing { return .cancelScreenshot }
        if clipboardCoordinator.isCapturePending { return .copyingScreenshot }
        if clipboardCoordinator.hasPasteableScreenshot { return .screenshotReadyToPaste }
        return .screenshot
    }

    var presentationState: ScreenshotActionPresentationState {
        switch buttonState {
        case .screenshot: return .idle
        case .cancelScreenshot: return .capturing
        case .copyingScreenshot: return .copying
        case .screenshotReadyToPaste: return .pasteReady
        }
    }

    func handlePress(from source: MouseSource) -> TriggerResult {
        guard inputAllowed() else { return .blocked }

        if let process = activeProcess {
            generation &+= 1
            activeProcess = nil
            activeSource = nil
            if process.isRunning { process.cancel() }
            onStateChange?()
            return .cancelled
        }

        if let pendingSource {
            gestureScheduler.stop()
            self.pendingSource = nil

            guard pendingSource == source else {
                let result = startCapture(from: pendingSource)
                onAsynchronousResult?(pendingSource, result)
                onStateChange?()
                return .awaitingSinglePress
            }

            if clipboardCoordinator.isCapturePending {
                pasteWhenCaptureResolvesForSource = source
                onStateChange?()
                return .pasteQueued
            }
            if clipboardCoordinator.hasPasteableScreenshot {
                let result = pasteScreenshot()
                onStateChange?()
                return result
            }
            let result = startCapture(from: source)
            onStateChange?()
            return result
        }

        pendingSource = source
        gestureScheduler.start(interval: Self.doublePressInterval) { [weak self] in
            guard let self, let source = self.pendingSource else { return }
            self.gestureScheduler.stop()
            self.pendingSource = nil
            let result = self.startCapture(from: source)
            self.onAsynchronousResult?(source, result)
            self.onStateChange?()
        }
        onStateChange?()
        return .awaitingSinglePress
    }

    func cancel() {
        generation &+= 1
        gestureScheduler.stop()
        pendingSource = nil
        pasteWhenCaptureResolvesForSource = nil
        let process = activeProcess
        activeProcess = nil
        activeSource = nil
        if process?.isRunning == true { process?.cancel() }
        clipboardCoordinator.cancel(clearOwnership: true)
        onStateChange?()
    }

    private func startCapture(from source: MouseSource) -> TriggerResult {
        guard inputAllowed() else { return .blocked }

        let process = makeProcess()
        clipboardCoordinator.prepareForCapture()
        generation &+= 1
        let token = generation
        process.onTermination = { [weak self] result in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == token else { return }
                let completedSource = self.activeSource ?? source
                self.activeProcess = nil
                self.activeSource = nil

                if result == .completed {
                    self.clipboardCoordinator.resolveCompletedCapture { [weak self] resolutionResult in
                        guard let self, self.generation == token else { return }
                        if case .success = resolutionResult,
                           let pasteSource = self.pasteWhenCaptureResolvesForSource {
                            self.pasteWhenCaptureResolvesForSource = nil
                            let pasteResult = self.pasteScreenshot()
                            self.onAsynchronousResult?(pasteSource, pasteResult)
                        } else if case .failure = resolutionResult {
                            self.pasteWhenCaptureResolvesForSource = nil
                        }
                        self.onStateChange?()
                        switch resolutionResult {
                        case .success:
                            self.onScreenshotReady?(completedSource, resolutionResult)
                            self.onCompletion?(.completed)
                        case .failure(.screenshotFileNotFound):
                            self.onCompletion?(.cancelled)
                        case .failure(let error):
                            self.onScreenshotReady?(completedSource, resolutionResult)
                            self.onCompletion?(.failed(error.localizedDescription))
                        }
                    }
                } else {
                    self.clipboardCoordinator.discardPreparedCapture()
                    self.onCompletion?(result)
                }
                self.onStateChange?()
            }
        }
        activeProcess = process
        activeSource = source
        do {
            try process.run()
            onStateChange?()
            return .started
        } catch {
            if generation == token {
                activeProcess = nil
                activeSource = nil
            }
            clipboardCoordinator.discardPreparedCapture()
            onStateChange?()
            return .failed(error.localizedDescription)
        }
    }

    private func pasteScreenshot() -> TriggerResult {
        switch clipboardCoordinator.pasteScreenshot() {
        case .success:
            return .pasted
        case .failure(let error):
            return .failed(error.localizedDescription)
        }
    }
}

enum NativeScreenshotShortcutError: Error, LocalizedError {
    case lifecycleMonitorUnavailable
    case eventCreationFailed

    var errorDescription: String? {
        switch self {
        case .lifecycleMonitorUnavailable:
            "Could not observe the native Screenshot interaction"
        case .eventCreationFailed:
            "Could not send Shift-Command-4"
        }
    }
}

/// Sends the exact system Shift-Command-4 shortcut so macOS owns the configured
/// destination, sound and floating-thumbnail experience. A short-lived global
/// monitor tracks the selection mouse-up or Escape, while public window-owner
/// polling detects native Screenshot UI that disappeared without either event.
@MainActor
final class NativeInteractiveScreenshotProcess: InteractiveScreenshotProcess {
    typealias EventPoster = @MainActor (
        _ keyCode: CGKeyCode,
        _ flags: CGEventFlags,
        _ isDown: Bool
    ) -> Bool
    typealias LifecycleMonitor = @MainActor (
        _ handler: @escaping @MainActor (InteractiveScreenshotResult) -> Void
    ) -> Any?
    typealias MonitorRemover = @MainActor (_ monitor: Any) -> Void
    typealias InteractionActiveProvider = @MainActor () -> Bool

    static let screenshotKeyCode: CGKeyCode = 21 // ANSI 4
    static let escapeKeyCode: CGKeyCode = 53
    static let screenshotFlags: CGEventFlags = [.maskCommand, .maskShift]
    static let lifecyclePollInterval: TimeInterval = 0.25
    static let activationPollLimit = 8

    private let postEvent: EventPoster
    private let startLifecycleMonitor: LifecycleMonitor
    private let removeLifecycleMonitor: MonitorRemover
    private let lifecycleScheduler: TickScheduler
    private let interactionIsActive: InteractionActiveProvider
    private var lifecycleMonitor: Any?
    private var observedActiveInteraction = false
    private var observedSelectionMouseUp = false
    private var activationPollCount = 0
    var onTermination: ((InteractiveScreenshotResult) -> Void)?
    private(set) var isRunning = false

    init(
        postEvent: @escaping EventPoster = NativeInteractiveScreenshotProcess.postKeyboardEvent,
        startLifecycleMonitor: @escaping LifecycleMonitor = NativeInteractiveScreenshotProcess.installLifecycleMonitor,
        removeLifecycleMonitor: @escaping MonitorRemover = NSEvent.removeMonitor,
        lifecycleScheduler: TickScheduler = DispatchTickScheduler(),
        interactionIsActive: @escaping InteractionActiveProvider =
            NativeInteractiveScreenshotProcess.screenshotInteractionIsActive
    ) {
        self.postEvent = postEvent
        self.startLifecycleMonitor = startLifecycleMonitor
        self.removeLifecycleMonitor = removeLifecycleMonitor
        self.lifecycleScheduler = lifecycleScheduler
        self.interactionIsActive = interactionIsActive
    }

    func run() throws {
        guard !isRunning else { return }
        guard let monitor = startLifecycleMonitor({ [weak self] result in
            guard let self else { return }
            switch result {
            case .completed:
                self.observedSelectionMouseUp = true
                self.pollInteractionState()
            case .cancelled, .failed:
                self.finish(with: result)
            }
        }) else {
            throw NativeScreenshotShortcutError.lifecycleMonitorUnavailable
        }
        lifecycleMonitor = monitor
        isRunning = true
        observedActiveInteraction = false
        observedSelectionMouseUp = false
        activationPollCount = 0

        let down = postEvent(Self.screenshotKeyCode, Self.screenshotFlags, true)
        let up = postEvent(Self.screenshotKeyCode, Self.screenshotFlags, false)
        guard down, up else {
            stopMonitoring()
            isRunning = false
            throw NativeScreenshotShortcutError.eventCreationFailed
        }
        lifecycleScheduler.start(interval: Self.lifecyclePollInterval) { [weak self] in
            self?.pollInteractionState()
        }
        pollInteractionState()
    }

    func cancel() {
        guard isRunning else { return }
        _ = postEvent(Self.escapeKeyCode, [], true)
        _ = postEvent(Self.escapeKeyCode, [], false)
        finish(with: .cancelled)
    }

    private func finish(with result: InteractiveScreenshotResult) {
        guard isRunning else { return }
        isRunning = false
        stopMonitoring()
        onTermination?(result)
    }

    private func stopMonitoring() {
        lifecycleScheduler.stop()
        if let lifecycleMonitor { removeLifecycleMonitor(lifecycleMonitor) }
        lifecycleMonitor = nil
    }

    private func pollInteractionState() {
        guard isRunning else { return }
        if interactionIsActive() {
            observedActiveInteraction = true
            return
        }
        if observedActiveInteraction || observedSelectionMouseUp {
            finish(with: observedSelectionMouseUp ? .completed : .cancelled)
            return
        }
        activationPollCount += 1
        if activationPollCount >= Self.activationPollLimit {
            finish(with: .failed(NativeScreenshotShortcutError.lifecycleMonitorUnavailable.localizedDescription))
        }
    }

    private static func installLifecycleMonitor(
        handler: @escaping @MainActor (InteractiveScreenshotResult) -> Void
    ) -> Any? {
        var selectionMouseDownLocation: NSPoint?
        var observedSelectionDrag = false
        return NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .keyDown]
        ) { event in
            let result = classifyLifecycleEvent(
                event.type,
                keyCode: event.keyCode,
                location: event.locationInWindow,
                selectionMouseDownLocation: &selectionMouseDownLocation,
                observedSelectionDrag: &observedSelectionDrag
            )
            guard let result else { return }
            Task { @MainActor in handler(result) }
        }
    }

    static func classifyLifecycleEvent(
        _ eventType: NSEvent.EventType,
        keyCode: UInt16,
        location: NSPoint,
        selectionMouseDownLocation: inout NSPoint?,
        observedSelectionDrag: inout Bool
    ) -> InteractiveScreenshotResult? {
        switch eventType {
        case .leftMouseDown:
            selectionMouseDownLocation = location
            observedSelectionDrag = false
            return nil
        case .leftMouseDragged:
            observedSelectionDrag = true
            return nil
        case .leftMouseUp:
            let moved = selectionMouseDownLocation.map {
                abs(location.x - $0.x) >= 1 || abs(location.y - $0.y) >= 1
            } ?? false
            selectionMouseDownLocation = nil
            defer { observedSelectionDrag = false }
            return observedSelectionDrag || moved ? .completed : .cancelled // macOS can swallow every global drag event while still delivering the selection down/up; compare their positions so that real captures complete, while an unmoved click still cancels. (Codex task: 01a039f7-873c-7c30-b3dc-af8a6724ace5)
        case .keyDown where keyCode == Self.escapeKeyCode:
            selectionMouseDownLocation = nil
            observedSelectionDrag = false
            return .cancelled
        default:
            return nil
        }
    }

    private static func screenshotInteractionIsActive() -> Bool { // A click can dismiss selected-area capture without reaching the global NSEvent monitor; poll the public window list for macOS's exact `screencapture` tracking surface so the HUD cannot stay on Cancel screenshot. (Codex task: 01a039f7-873c-7c30-b3dc-af8a6724ace5)
        let options: CGWindowListOption = [.optionAll, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID)
            as? [[String: Any]] else { return false }
        return windows.contains { window in
            window[kCGWindowOwnerName as String] as? String == "screencapture"
        }
    }

    private static func postKeyboardEvent(
        keyCode: CGKeyCode,
        flags: CGEventFlags,
        isDown: Bool
    ) -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let event = CGEvent(
                keyboardEventSource: source,
                virtualKey: keyCode,
                keyDown: isDown
              ) else { return false }
        event.flags = flags
        event.post(tap: .cghidEventTap)
        return true
    }
}
