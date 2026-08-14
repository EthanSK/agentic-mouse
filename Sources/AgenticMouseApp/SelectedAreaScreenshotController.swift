import Foundation

@MainActor
protocol InteractiveScreenshotProcess: AnyObject {
    var isRunning: Bool { get }
    var onTermination: (() -> Void)? { get set }
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
        process.onTermination = { [weak self] in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == token else { return }
                self.activeProcess = nil
                self.onCapturingChange?(false)
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

/// Uses macOS's own interactive selection command with the user's normal
/// screenshot preferences. The process stays alive until capture or Escape,
/// giving Agentic Mouse a real lifecycle to cancel on the second mouse press.
@MainActor
private final class NativeInteractiveScreenshotProcess: InteractiveScreenshotProcess {
    private let process = Process()
    var onTermination: (() -> Void)?

    var isRunning: Bool { process.isRunning }

    init() {
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-p"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { [weak self] in self?.onTermination?() }
        }
    }

    func run() throws { try process.run() }

    func cancel() { process.terminate() }
}
