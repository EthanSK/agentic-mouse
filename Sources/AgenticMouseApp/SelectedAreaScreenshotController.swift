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
    case screenshotNoLongerOnClipboard
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
        case .screenshotNoLongerOnClipboard:
            "The screenshot is no longer on the clipboard"
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
    var isCopyPending: Bool { get }
    func prepareForCapture()
    func discardPreparedCapture()
    func copyCompletedCapture(
        completion: @escaping (Result<URL, ScreenshotClipboardError>) -> Void
    )
    func pasteScreenshot() -> Result<Void, ScreenshotClipboardError>
    func cancel(clearOwnership: Bool)
}

/// Watches only the configured macOS Screenshot destination after the native
/// Shift-Command-4 interaction completes. This preserves the system's sound,
/// save destination and floating thumbnail while making that same saved image
/// available to ordinary Command-V targets without requesting screen capture
/// permission or taking a second screenshot.
@MainActor
final class NativeScreenshotClipboardCoordinator: ScreenshotClipboardCoordinating {
    typealias DirectoryResolver = @MainActor () -> URL?
    typealias DirectorySnapshotter = @MainActor (_ directoryURL: URL) -> Set<String>?
    typealias CandidateFinder = @MainActor (_ baseline: ScreenshotCaptureBaseline) -> [URL]
    typealias ScreenshotMetadataChecker = @MainActor (_ url: URL) -> Bool
    typealias PasteboardWriter = @MainActor (_ url: URL) -> Int?
    typealias PasteboardChangeCountProvider = @MainActor () -> Int
    typealias PasteEventPoster = @MainActor () -> Bool
    typealias AccessibilityTrustProvider = @MainActor () -> Bool
    typealias InputAllowedProvider = @MainActor () -> Bool

    static let pollInterval: TimeInterval = 0.10
    static let copyTimeout: TimeInterval = 60

    private let scheduler: TickScheduler
    private let clock: MonotonicClock
    private let now: @MainActor () -> Date
    private let resolveDirectory: DirectoryResolver
    private let snapshotDirectory: DirectorySnapshotter
    private let findCandidates: CandidateFinder
    private let metadataMarksScreenshot: ScreenshotMetadataChecker
    private let writeToPasteboard: PasteboardWriter
    private let pasteboardChangeCount: PasteboardChangeCountProvider
    private let postPaste: PasteEventPoster
    private let accessibilityTrusted: AccessibilityTrustProvider
    private let inputAllowed: InputAllowedProvider

    private var preparedBaseline: ScreenshotCaptureBaseline?
    private var copyCompletion: ((Result<URL, ScreenshotClipboardError>) -> Void)?
    private var copyDeadline: TimeInterval?
    private var ownedPasteboardChangeCount: Int?
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
        writeToPasteboard: @escaping PasteboardWriter =
            NativeScreenshotClipboardCoordinator.writeImageToPasteboard,
        pasteboardChangeCount: @escaping PasteboardChangeCountProvider = {
            NSPasteboard.general.changeCount
        },
        postPaste: @escaping PasteEventPoster =
            NativeScreenshotClipboardCoordinator.postCommandV,
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
        self.writeToPasteboard = writeToPasteboard
        self.pasteboardChangeCount = pasteboardChangeCount
        self.postPaste = postPaste
        self.accessibilityTrusted = accessibilityTrusted
        self.inputAllowed = inputAllowed
    }

    var hasPasteableScreenshot: Bool {
        guard let ownedPasteboardChangeCount else { return false }
        return pasteboardChangeCount() == ownedPasteboardChangeCount
    }

    var isCopyPending: Bool { copyCompletion != nil }

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

    func copyCompletedCapture(
        completion: @escaping (Result<URL, ScreenshotClipboardError>) -> Void
    ) {
        scheduler.stop()
        copyCompletion = completion
        copyDeadline = clock.now + Self.copyTimeout
        lastCandidateFailure = nil

        guard preparedBaseline != nil else {
            finishCopy(.failure(.screenshotDirectoryUnavailable))
            return
        }
        pollForSavedScreenshot()
        if isCopyPending {
            scheduler.start(interval: Self.pollInterval) { [weak self] in
                self?.pollForSavedScreenshot()
            }
        }
    }

    func pasteScreenshot() -> Result<Void, ScreenshotClipboardError> {
        guard inputAllowed() else { return .failure(.inputBlocked) }
        guard accessibilityTrusted() else {
            return .failure(.accessibilityPermissionMissing)
        }
        guard hasPasteableScreenshot else {
            ownedPasteboardChangeCount = nil
            return .failure(.screenshotNoLongerOnClipboard)
        }
        return postPaste() ? .success(()) : .failure(.pasteEventCreationFailed)
    }

    func cancel(clearOwnership: Bool) {
        scheduler.stop()
        preparedBaseline = nil
        copyCompletion = nil
        copyDeadline = nil
        lastCandidateFailure = nil
        if clearOwnership { ownedPasteboardChangeCount = nil }
    }

    private func pollForSavedScreenshot() {
        guard let baseline = preparedBaseline,
              copyCompletion != nil,
              let copyDeadline
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
            guard let changeCount = writeToPasteboard(candidate) else {
                lastCandidateFailure = .screenshotImageUnreadable
                if clock.now < copyDeadline { return }
                finishCopy(.failure(lastCandidateFailure ?? .screenshotImageUnreadable))
                return
            }
            ownedPasteboardChangeCount = changeCount
            finishCopy(.success(candidate))
            return
        }

        guard clock.now >= copyDeadline else { return }
        finishCopy(.failure(lastCandidateFailure ?? .screenshotFileNotFound))
    }

    private func finishCopy(_ result: Result<URL, ScreenshotClipboardError>) {
        scheduler.stop()
        let completion = copyCompletion
        copyCompletion = nil
        copyDeadline = nil
        preparedBaseline = nil
        lastCandidateFailure = nil
        completion?(result)
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

    static func writeImageToPasteboard(_ url: URL) -> Int? {
        guard let data = try? Data(contentsOf: url),
              let image = NSImage(data: data),
              let tiff = image.tiffRepresentation,
              let type = UTType(filenameExtension: url.pathExtension)
        else { return nil }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let originalWritten = pasteboard.setData(
            data,
            forType: NSPasteboard.PasteboardType(type.identifier)
        )
        let tiffWritten = pasteboard.setData(tiff, forType: .tiff)
        guard originalWritten, tiffWritten else { return nil }
        return pasteboard.changeCount
    }

    static func postCommandV() -> Bool {
        let commandKeyCode: CGKeyCode = 55
        let pasteKeyCode: CGKeyCode = 9
        let flags: CGEventFlags = [.maskCommand]
        return SyntheticKeyboardChordPoster.shared.post([
            .modifier(keyCode: commandKeyCode, flags: flags, at: 0),
            .key(keyCode: pasteKeyCode, flags: flags, isDown: true, at: 0.006),
            .key(keyCode: pasteKeyCode, flags: flags, isDown: false, at: 0.026),
            .modifier(keyCode: commandKeyCode, flags: [], at: 0.032),
        ])
    }

    private static func canonicalPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }
}

/// Owns one native selected-area screenshot interaction plus the bounded
/// single/double-press classification for its shared physical button. A single
/// press starts the native capture after the short classifier window. A rapid
/// second press from the same mouse pastes the screenshot Agentic Mouse most
/// recently copied. Once the native crosshair is running, the next press keeps
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
    private var pasteWhenCopyCompletesForSource: MouseSource?
    private var generation: UInt64 = 0
    var onStateChange: (() -> Void)?
    var onCompletion: ((InteractiveScreenshotResult) -> Void)?
    var onAsynchronousResult: ((MouseSource, TriggerResult) -> Void)?
    var onClipboardCopy: ((MouseSource, Result<URL, ScreenshotClipboardError>) -> Void)?

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
        if clipboardCoordinator.isCopyPending { return .copyingScreenshot }
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

            if clipboardCoordinator.isCopyPending {
                pasteWhenCopyCompletesForSource = source
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
        pasteWhenCopyCompletesForSource = nil
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
                    self.clipboardCoordinator.copyCompletedCapture { [weak self] copyResult in
                        guard let self, self.generation == token else { return }
                        if case .success = copyResult,
                           let pasteSource = self.pasteWhenCopyCompletesForSource {
                            self.pasteWhenCopyCompletesForSource = nil
                            let pasteResult = self.pasteScreenshot()
                            self.onAsynchronousResult?(pasteSource, pasteResult)
                        } else if case .failure = copyResult {
                            self.pasteWhenCopyCompletesForSource = nil
                        }
                        self.onStateChange?()
                        self.onClipboardCopy?(completedSource, copyResult)
                    }
                } else {
                    self.clipboardCoordinator.discardPreparedCapture()
                }
                self.onStateChange?()
                self.onCompletion?(result)
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
/// monitor tracks the selection mouse-up or Escape; the next mouse toggle sends
/// Escape to cancel only the interaction Agentic Mouse started.
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

    static let screenshotKeyCode: CGKeyCode = 21 // ANSI 4
    static let escapeKeyCode: CGKeyCode = 53
    static let screenshotFlags: CGEventFlags = [.maskCommand, .maskShift]

    private let postEvent: EventPoster
    private let startLifecycleMonitor: LifecycleMonitor
    private let removeLifecycleMonitor: MonitorRemover
    private var lifecycleMonitor: Any?
    var onTermination: ((InteractiveScreenshotResult) -> Void)?
    private(set) var isRunning = false

    init(
        postEvent: @escaping EventPoster = NativeInteractiveScreenshotProcess.postKeyboardEvent,
        startLifecycleMonitor: @escaping LifecycleMonitor = NativeInteractiveScreenshotProcess.installLifecycleMonitor,
        removeLifecycleMonitor: @escaping MonitorRemover = NSEvent.removeMonitor
    ) {
        self.postEvent = postEvent
        self.startLifecycleMonitor = startLifecycleMonitor
        self.removeLifecycleMonitor = removeLifecycleMonitor
    }

    func run() throws {
        guard !isRunning else { return }
        guard let monitor = startLifecycleMonitor({ [weak self] result in
            self?.finish(with: result)
        }) else {
            throw NativeScreenshotShortcutError.lifecycleMonitorUnavailable
        }
        lifecycleMonitor = monitor
        isRunning = true

        let down = postEvent(Self.screenshotKeyCode, Self.screenshotFlags, true)
        let up = postEvent(Self.screenshotKeyCode, Self.screenshotFlags, false)
        guard down, up else {
            stopMonitoring()
            isRunning = false
            throw NativeScreenshotShortcutError.eventCreationFailed
        }
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
        if let lifecycleMonitor { removeLifecycleMonitor(lifecycleMonitor) }
        lifecycleMonitor = nil
    }

    private static func installLifecycleMonitor(
        handler: @escaping @MainActor (InteractiveScreenshotResult) -> Void
    ) -> Any? {
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp, .keyDown]) { event in
            let result: InteractiveScreenshotResult?
            if event.type == .leftMouseUp {
                result = .completed
            } else if event.type == .keyDown, event.keyCode == Self.escapeKeyCode {
                result = .cancelled
            } else {
                result = nil
            }
            guard let result else { return }
            Task { @MainActor in handler(result) }
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
