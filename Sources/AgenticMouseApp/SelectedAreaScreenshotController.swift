import Foundation

enum InteractiveScreenshotResult: Equatable {
    case saved(URL)
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

/// Owns one native selected-area screenshot interaction. A second toggle
/// cancels the exact still-running interaction instead of guessing from a
/// timer or leaving a stale Karabiner variable after a completed capture.
@MainActor
final class SelectedAreaScreenshotController {
    enum ToggleResult: Equatable {
        case started
        case cancelled
        case blocked
        case failed(String)
    }

    typealias ProcessFactory = @MainActor () -> InteractiveScreenshotProcess
    typealias InputAllowedProvider = @MainActor () -> Bool

    private let makeProcess: ProcessFactory
    private let inputAllowed: InputAllowedProvider
    private var activeProcess: InteractiveScreenshotProcess?
    private var generation: UInt64 = 0
    var onCapturingChange: ((Bool) -> Void)?
    var onCompletion: ((InteractiveScreenshotResult) -> Void)?

    init(
        makeProcess: ProcessFactory? = nil,
        inputAllowed: @escaping InputAllowedProvider = { true }
    ) {
        self.makeProcess = makeProcess ?? { NativeInteractiveScreenshotProcess() }
        self.inputAllowed = inputAllowed
    }

    var isCapturing: Bool { activeProcess?.isRunning == true }

    func toggle() -> ToggleResult {
        guard inputAllowed() else { return .blocked }

        if let process = activeProcess {
            generation &+= 1
            activeProcess = nil
            if process.isRunning { process.cancel() }
            onCapturingChange?(false)
            return .cancelled
        }

        let process = makeProcess()
        generation &+= 1
        let token = generation
        process.onTermination = { [weak self] result in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == token else { return }
                self.activeProcess = nil
                self.onCapturingChange?(false)
                self.onCompletion?(result)
            }
        }
        activeProcess = process
        do {
            try process.run()
            onCapturingChange?(true)
            return .started
        } catch {
            if generation == token { activeProcess = nil }
            onCapturingChange?(false)
            return .failed(error.localizedDescription)
        }
    }

    func cancel() {
        generation &+= 1
        let process = activeProcess
        activeProcess = nil
        if process?.isRunning == true { process?.cancel() }
        if process != nil { onCapturingChange?(false) }
    }
}

/// Resolves the user's configured Screenshot directory, but gives the native
/// command an explicit output file. This avoids `screencapture -p`, which
/// delegates saving to opaque UI preferences, ignores explicit paths, and can
/// finish without leaving Agentic Mouse any success or failure evidence.
struct ScreenshotDestinationResolver {
    var configuredLocation: () -> String? = {
        CFPreferencesCopyAppValue(
            "location" as CFString,
            "com.apple.screencapture" as CFString
        ) as? String
    }
    var homeDirectory = FileManager.default.homeDirectoryForCurrentUser
    var now: () -> Date = Date.init
    var fileManager = FileManager.default

    func nextURL() -> URL {
        let directory = preferredDirectory()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let stem = "screenshot-\(formatter.string(from: now()))"

        for suffix in 0...999 {
            let name = suffix == 0 ? stem : "\(stem)-\(suffix + 1)"
            let candidate = directory.appendingPathComponent("\(name).png")
            if !fileManager.fileExists(atPath: candidate.path) { return candidate }
        }

        return directory.appendingPathComponent("\(stem)-\(UUID().uuidString).png")
    }

    private func preferredDirectory() -> URL {
        if let configuredLocation = configuredLocation()?.trimmingCharacters(in: .whitespacesAndNewlines),
           !configuredLocation.isEmpty
        {
            let expanded: String
            if configuredLocation == "~" {
                expanded = homeDirectory.path
            } else if configuredLocation.hasPrefix("~/") {
                expanded = homeDirectory
                    .appendingPathComponent(String(configuredLocation.dropFirst(2)), isDirectory: true)
                    .path
            } else {
                expanded = (configuredLocation as NSString).expandingTildeInPath
            }
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: expanded, isDirectory: &isDirectory),
               isDirectory.boolValue,
               fileManager.isWritableFile(atPath: expanded)
            {
                return URL(fileURLWithPath: expanded, isDirectory: true)
            }
        }

        let desktop = homeDirectory.appendingPathComponent("Desktop", isDirectory: true)
        if fileManager.fileExists(atPath: desktop.path), fileManager.isWritableFile(atPath: desktop.path) {
            return desktop
        }
        return homeDirectory
    }
}

/// Uses macOS's own selected-area crosshair and saves directly to an explicit
/// file. The process stays alive until capture or Escape, giving Agentic Mouse
/// a real lifecycle to cancel on the second mouse press.
@MainActor
final class NativeInteractiveScreenshotProcess: InteractiveScreenshotProcess {
    private let process = Process()
    private let destinationURL: URL
    private let standardError = Pipe()
    var onTermination: ((InteractiveScreenshotResult) -> Void)?

    var isRunning: Bool { process.isRunning }

    init(destinationURL: URL = ScreenshotDestinationResolver().nextURL()) {
        self.destinationURL = destinationURL
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = Self.arguments(destinationURL: destinationURL)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = standardError
        process.terminationHandler = { [weak self] process in
            guard let self else { return }
            let errorData = self.standardError.fileHandleForReading.readDataToEndOfFile()
            let errorText = String(decoding: errorData, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let result = Self.result(
                terminationStatus: process.terminationStatus,
                destinationURL: self.destinationURL,
                errorText: errorText
            )
            DispatchQueue.main.async { [weak self] in self?.onTermination?(result) }
        }
    }

    nonisolated static func arguments(destinationURL: URL) -> [String] {
        ["-i", "-s", "-t", "png", destinationURL.path]
    }

    nonisolated static func result(
        terminationStatus: Int32,
        destinationURL: URL,
        errorText: String,
        fileManager: FileManager = .default
    ) -> InteractiveScreenshotResult {
        if terminationStatus == 0,
           let size = try? destinationURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           size > 0
        {
            return .saved(destinationURL)
        }
        if terminationStatus == 1, errorText.isEmpty,
           !fileManager.fileExists(atPath: destinationURL.path)
        {
            return .cancelled
        }
        let detail = errorText.isEmpty
            ? "screencapture exited with status \(terminationStatus) without creating \(destinationURL.lastPathComponent)"
            : errorText
        return .failed(detail)
    }

    func run() throws { try process.run() }

    func cancel() { process.terminate() }
}
