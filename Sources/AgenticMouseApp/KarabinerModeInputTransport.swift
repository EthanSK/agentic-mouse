import Foundation
import ScimitarKit

/// Adapts the already exact-device, expiring Karabiner mode stream to the
/// existing MultiTapCoordinator. Karabiner owns interception; this transport
/// never requests a second iCUE or event-tap input path.
final class KarabinerModeInputTransport: InputTransport {
    weak var delegate: InputTransportDelegate?
    let name = "Karabiner exact-device mode stream"
    private(set) var isRunning = false
    private(set) var isInterceptionEnabled = false

    func start() throws { isRunning = true }

    func stop() {
        endInterception()
        isRunning = false
    }

    func preflight() -> InputTransportReadiness {
        isRunning ? .ready : .notReady(["Karabiner mode input is not running."])
    }

    func beginInterception() throws {
        guard isRunning else {
            throw InputTransportError.notAvailable("Karabiner mode input is not running")
        }
        isInterceptionEnabled = true
    }

    func endInterception() { isInterceptionEnabled = false }

    func deliver(
        source: MouseSource,
        cell: PhysicalCell,
        phase: ModePickerCommand.Phase,
        at timestamp: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) {
        guard isRunning, isInterceptionEnabled else { return }
        let inputPhase: PhysicalInputEvent.Phase = phase == .press ? .press : .release
        delegate?.inputTransport(
            self,
            didReceive: PhysicalInputEvent(
                binding: .icueMacroKey(cell.rawValue),
                phase: inputPhase,
                timestamp: timestamp
            )
        )
    }
}
