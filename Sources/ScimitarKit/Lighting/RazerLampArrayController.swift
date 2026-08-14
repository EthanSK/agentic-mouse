import Foundation

public protocol RazerLampArrayTransport: AnyObject {
    func open() throws
    func reportDescriptor() throws -> [UInt8]
    func readFeatureReport(id: UInt8, maximumLength: Int) throws -> [UInt8]
    func writeFeatureReport(_ report: [UInt8]) throws
    func close()
}

/// Owns one temporary, standards-based LampArray session.
///
/// The device stays open for the mode lease so colour changes do not repeatedly
/// enumerate USB. `release()` restores autonomous firmware lighting and closes
/// the interface. Any failed colour write follows the same rollback path.
public final class RazerLampArrayController {
    private let transport: RazerLampArrayTransport
    private let log: Log
    private let sleepMicroseconds: (UInt32) -> Void

    private var attributes: LampArrayAttributes?
    private var autonomousModeDisabled = false
    private var lastLampWriteUptime: TimeInterval?

    public var onProblem: ((String) -> Void)?

    public init(
        transport: RazerLampArrayTransport,
        log: Log = Log(category: "razer-lamparray", sink: NullLogSink()),
        sleepMicroseconds: @escaping (UInt32) -> Void = { microseconds in
            guard microseconds > 0 else { return }
            Thread.sleep(forTimeInterval: TimeInterval(microseconds) / 1_000_000)
        }
    ) {
        self.transport = transport
        self.log = log
        self.sleepMicroseconds = sleepMicroseconds
    }

    deinit {
        release()
    }

    /// Opens and validates the exact interface without changing lamp state.
    /// The caller must invoke `release()` (or let this controller deallocate)
    /// to close the read-only probe session.
    public func probe() throws -> LampArrayAttributes {
        try prepareIfNeeded()
    }

    /// Reads the current standard report-3 lamp record without changing any
    /// selector, lighting state, or device mode.
    public func readCurrentLampAttributes() throws -> LampAttributes {
        _ = try prepareIfNeeded()
        return try LampAttributes.parse(
            transport.readFeatureReport(
                id: 3,
                maximumLength: RazerNagaLampArray.maximumFeatureReportLength
            )
        )
    }

    /// Reads standard report 6 without writing AutonomousMode.
    public func readAutonomousMode() throws -> Bool {
        _ = try prepareIfNeeded()
        return try RazerLampArrayReport.parseAutonomousMode(
            transport.readFeatureReport(
                id: 6,
                maximumLength: RazerNagaLampArray.maximumFeatureReportLength
            )
        )
    }

    @discardableResult
    public func setColor(_ color: RGBColor?) -> Bool {
        guard let color, color.alpha > 0 else {
            release()
            return false
        }

        do {
            let attributes = try prepareIfNeeded()
            if !autonomousModeDisabled {
                try transport.writeFeatureReport(RazerLampArrayReport.autonomousMode(false))
                autonomousModeDisabled = true
            }
            respectMinimumUpdateInterval(attributes.minimumUpdateIntervalMicroseconds)
            try transport.writeFeatureReport(
                RazerLampArrayReport.solidColor(color, lampCount: attributes.lampCount)
            )
            lastLampWriteUptime = ProcessInfo.processInfo.systemUptime
            return true
        } catch {
            log.notice("Razer LampArray colour failed: \(error)")
            release()
            return false
        }
    }

    /// Writes one RGB value per audited lamp and commits the frame on the last
    /// range update. This remains within standard HID LampArray report 5.
    @discardableResult
    public func setFrame(_ colors: [RGBColor]) -> Bool {
        do {
            let attributes = try prepareIfNeeded()
            guard colors.count == Int(attributes.lampCount) else {
                throw RazerLampArrayError.unsupportedDevice(
                    "expected \(attributes.lampCount) frame colours, got \(colors.count)"
                )
            }
            if !autonomousModeDisabled {
                try transport.writeFeatureReport(RazerLampArrayReport.autonomousMode(false))
                autonomousModeDisabled = true
            }
            for (index, color) in colors.enumerated() {
                respectMinimumUpdateInterval(attributes.minimumUpdateIntervalMicroseconds)
                let lamp = UInt16(index)
                try transport.writeFeatureReport(
                    RazerLampArrayReport.color(
                        color,
                        fromLamp: lamp,
                        throughLamp: lamp,
                        lampCount: attributes.lampCount,
                        updateComplete: index == colors.count - 1
                    )
                )
                lastLampWriteUptime = ProcessInfo.processInfo.systemUptime
            }
            return true
        } catch {
            log.notice("Razer LampArray frame failed: \(error)")
            release()
            return false
        }
    }

    public func release() {
        if autonomousModeDisabled {
            var lastError: Error?
            for _ in 0..<3 {
                do {
                    try transport.writeFeatureReport(RazerLampArrayReport.autonomousMode(true))
                    lastError = nil
                    break
                } catch {
                    lastError = error
                }
            }
            if let lastError {
                let message = "Razer lighting could not restore its autonomous rainbow: \(lastError)"
                log.notice(message)
                onProblem?(message)
            }
        }
        autonomousModeDisabled = false
        attributes = nil
        lastLampWriteUptime = nil
        transport.close()
    }

    private func prepareIfNeeded() throws -> LampArrayAttributes {
        if let attributes { return attributes }

        try transport.open()
        let descriptor = try transport.reportDescriptor()
        guard descriptor == RazerNagaLampArray.expectedReportDescriptor else {
            throw RazerLampArrayError.unsupportedDevice("feature-report descriptor does not match the audited layout")
        }
        let report = try transport.readFeatureReport(
            id: 1,
            maximumLength: RazerNagaLampArray.maximumFeatureReportLength
        )
        let attributes = try LampArrayAttributes.parse(report)
        guard attributes.lampCount == RazerNagaLampArray.expectedLampCount else {
            throw RazerLampArrayError.unsupportedDevice(
                "expected \(RazerNagaLampArray.expectedLampCount) lamps, got \(attributes.lampCount)"
            )
        }
        guard attributes.kind == RazerNagaLampArray.mouseKind else {
            throw RazerLampArrayError.unsupportedDevice(
                "expected mouse kind \(RazerNagaLampArray.mouseKind), got \(attributes.kind)"
            )
        }
        self.attributes = attributes
        return attributes
    }

    private func respectMinimumUpdateInterval(_ minimumMicroseconds: UInt32) {
        guard minimumMicroseconds > 0, let lastLampWriteUptime else { return }
        let elapsed = ProcessInfo.processInfo.systemUptime - lastLampWriteUptime
        let remaining = TimeInterval(minimumMicroseconds) / 1_000_000 - elapsed
        guard remaining > 0 else { return }
        sleepMicroseconds(UInt32((remaining * 1_000_000).rounded(.up)))
    }
}
