import Foundation

/// Applies one transient colour through the exact Naga's 1×3 custom matrix.
/// Custom mode is activated once; later colours are one acknowledged frame so
/// the firmware effect engine cannot cross-fade between Static effect states.
public final class RazerVendorLightingController {
    private let transport: RazerVendorTransport
    private let log: Log
    private let idleColor: RGBColor?
    private let idleOutputColor: RGBColor?
    private let brightnessScale: Double
    private let retryDelay: (TimeInterval) -> Void
    private var hasAppliedRuntimeColor = false

    public var onProblem: ((String) -> Void)?

    public init(
        transport: RazerVendorTransport,
        idleColor: RGBColor? = nil,
        idleOutputColor: RGBColor? = nil,
        brightnessScale: Double = 1.0,
        log: Log = Log(category: "razer-vendor", sink: NullLogSink()),
        retryDelay: @escaping (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }
    ) {
        self.transport = transport
        self.idleColor = idleColor
        self.idleOutputColor = idleOutputColor
        self.brightnessScale = max(0, min(1, brightnessScale))
        self.log = log
        self.retryDelay = retryDelay
    }

    deinit { release() }

    @discardableResult
    public func setColor(_ color: RGBColor?) -> Bool {
        guard let color, color.alpha > 0 else {
            return restoreIdle()
        }

        return applyRuntimeColor(color)
    }

    /// Uses the exact Naga's three zones without pretending the twelve side
    /// buttons are individually addressable. Wheel and logo show the mode;
    /// the complete thumb-grid zone shows the last action. A rejected distinct
    /// frame falls back to the proven uniform mode frame.
    @discardableResult
    public func setModeAppearance(modeColor: RGBColor?, actionColor: RGBColor?) -> Bool {
        guard let modeColor, modeColor.alpha > 0 else { return restoreIdle() }
        let scaledMode = modeColor.scaledBrightness(brightnessScale)
        let scaledAction = (actionColor ?? modeColor).scaledBrightness(brightnessScale)
        if applyOutputFrame(
            RazerVendorReport.customFrame(
                scrollWheel: scaledMode,
                logo: scaledMode,
                thumbGrid: scaledAction
            )
        ) {
            return true
        }
        log.notice("Razer distinct-zone frame failed; retrying the proven uniform mode frame")
        return applyOutputColor(scaledMode)
    }

    /// Restores the configured in-process baseline without leaving custom
    /// effect mode. A controller with no idle colour retains the legacy
    /// release-to-Spectrum behaviour.
    @discardableResult
    public func restoreIdle() -> Bool {
        guard let idleColor, idleColor.alpha > 0 else {
            release()
            return false
        }

        if let idleOutputColor, idleOutputColor.alpha > 0 {
            return applyOutputColor(idleOutputColor)
        }

        return applyRuntimeColor(idleColor)
    }

    private func applyRuntimeColor(_ color: RGBColor) -> Bool {
        applyOutputColor(color.scaledBrightness(brightnessScale))
    }

    /// Writes an already-calibrated transient frame. The idle override uses
    /// this path so exact-device white-point correction cannot alter mode
    /// colour proportions or their shared brightness scale.
    private func applyOutputColor(_ color: RGBColor) -> Bool {
        applyOutputFrame(RazerVendorReport.customFrame(color))
    }

    private func applyOutputFrame(_ report: [UInt8]) -> Bool {
        do {
            try transport.open()
            if !hasAppliedRuntimeColor {
                try sendAcknowledged(RazerVendorReport.activateCustomEffect())
            }
            try sendAcknowledged(
                report
            )
            hasAppliedRuntimeColor = true
            return true
        } catch {
            log.notice("Razer vendor colour failed: \(error)")
            restoreSpectrumAfterFailure()
            return false
        }
    }

    public func release() {
        guard hasAppliedRuntimeColor else {
            transport.close()
            return
        }

        var failure: Error?
        for zone in RazerNagaVendorProtocol.Zone.allCases {
            do {
                try sendAcknowledged(RazerVendorReport.spectrum(zone: zone))
            } catch {
                failure = failure ?? error
            }
        }
        hasAppliedRuntimeColor = false
        transport.close()

        if let failure {
            let message = "Razer lighting could not restore spectrum cycling: \(failure)"
            log.notice(message)
            onProblem?(message)
        }
    }

    private func sendAcknowledged(_ request: [UInt8]) throws {
        for attempt in 0..<5 {
            let response = try RazerVendorResponse.parse(
                transport.exchange(request),
                matching: request
            )
            switch response.status {
            case .successful:
                return
            case .busy where attempt < 4:
                retryDelay(0.010)
            default:
                throw RazerVendorError.commandFailed(response.status)
            }
        }
        throw RazerVendorError.commandFailed(.busy)
    }

    private func restoreSpectrumAfterFailure() {
        // A partial three-zone write is possible. Best-effort restoration keeps
        // the existing visible baseline coherent, then always releases USB.
        for zone in RazerNagaVendorProtocol.Zone.allCases {
            try? sendAcknowledged(RazerVendorReport.spectrum(zone: zone))
        }
        hasAppliedRuntimeColor = false
        transport.close()
    }
}
