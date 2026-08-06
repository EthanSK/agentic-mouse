import CICUEBridge
import Foundation

protocol ICUELightingSession: AnyObject {
    var isLibraryLoaded: Bool { get }
    var state: ICUESessionState { get }
    func devices(typeMask: Int32) -> [ICUEDevice]
    func leds(of deviceIdentifier: String) -> [ICUELed]
    func setLayerPriority(_ priority: UInt32) -> Int32
    func setColors(deviceIdentifier: String, colors: [(luid: UInt32, color: RGBColor)]) -> Int32
    func disconnectForLightingSafety()
}

extension ICUESession: ICUELightingSession {
    public func disconnectForLightingSafety() {
        // The same vendor guarantee used by failed input rollback: ending the
        // client session makes iCUE discard every shared layer owned by it.
        disconnectForRollbackSafety()
    }
}

/// Paints exactly one Corsair mouse through the iCUE SDK's *shared* lighting
/// layer.
///
/// Guarantees this type is responsible for:
///
///  * Only the device chosen by `DeviceMatcher` is ever written to. There is no
///    code path that writes to "all devices".
///  * This type never calls `CorsairRequestControl`, so lighting is always
///    written through the default *shared* layer. (Multi-tap mode does request
///    `CAL_ExclusiveKeyEventsListening` — access level 2 — but that is input
///    only and, per the SDK, leaves lighting shared. The two exclusive levels
///    that would include lighting, 1 and 3, are rejected inside the C bridge and
///    have no Swift representation at all.)
///  * `release()` sets every LED it owns to alpha 0, which makes this client's
///    layer fully translucent and hands the mouse straight back to iCUE. It is
///    called on exit, on failure, on disconnect and on process teardown.
public final class ICUELightingController: LightingController {
    private let session: ICUELightingSession
    private let matcher: DeviceMatcher
    private let layerPriority: UInt32
    private let log: Log

    private var selectedDevice: ICUEDevice?
    private var ledLuids: [UInt32] = []
    private var hasWrittenSinceSelection = false

    public private(set) var lastSelection: DeviceSelectionResult?

    public init(
        session: ICUESession = .shared,
        matcher: DeviceMatcher = .scimitar,
        layerPriority: UInt32 = 130,
        log: Log
    ) {
        self.session = session
        self.matcher = matcher
        self.layerPriority = layerPriority
        self.log = log
    }

    init(
        sessionFacade: ICUELightingSession,
        matcher: DeviceMatcher = .scimitar,
        layerPriority: UInt32 = 130,
        log: Log
    ) {
        self.session = sessionFacade
        self.matcher = matcher
        self.layerPriority = layerPriority
        self.log = log
    }

    public var device: LightingDeviceSummary? { selectedDevice?.summary }

    public var isAvailable: Bool {
        session.isLibraryLoaded && session.state.isUsable && selectedDevice != nil && !ledLuids.isEmpty
    }

    /// Finds the mouse and caches its LED ids. Safe to call repeatedly; it is
    /// how the controller recovers after a reconnect.
    @discardableResult
    public func refreshDevice(excluding excludedIdentifiers: Set<String> = []) -> DeviceSelectionResult {
        guard session.isLibraryLoaded, session.state.isUsable else {
            let result = DeviceSelectionResult.noMatch(candidateCount: 0)
            lastSelection = result
            forgetDevice()
            return result
        }

        let allDevices = session.devices(typeMask: Int32(SC_ICUE_DEVICE_TYPE_MOUSE))
        let reachableIdentifiers = Set(allDevices.map(\.identifier))
        let candidates = allDevices.filter { !excludedIdentifiers.contains($0.identifier) }
        let result = DeviceSelector.select(from: candidates, using: matcher)
        lastSelection = result

        guard let device = result.device else {
            log.notice(result.explanation)
            releasePreviousSelectionIfReachable(
                reachableIdentifiers: reachableIdentifiers,
                excludedIdentifiers: excludedIdentifiers
            )
            forgetDevice()
            return result
        }

        let reportedLuids = session.leds(of: device.identifier).map(\.luid)
        let recognisedLuids = reportedLuids.filter { MouseZone(rawValue: $0) != nil }
        guard !recognisedLuids.isEmpty else {
            log.notice("\(device.safeModel) reported no recognised mouse LEDs; lighting stays disabled.")
            releasePreviousSelectionIfReachable(
                reachableIdentifiers: reachableIdentifiers,
                excludedIdentifiers: excludedIdentifiers
            )
            forgetDevice()
            return .noMatch(candidateCount: 1)
        }

        let isSameSelection = selectedDevice?.identifier == device.identifier
        let topologyChanged = Set(ledLuids) != Set(recognisedLuids)
        if !isSameSelection || topologyChanged {
            let releaseSucceeded = releasePreviousSelectionIfReachable(
                reachableIdentifiers: reachableIdentifiers,
                excludedIdentifiers: excludedIdentifiers
            )
            guard releaseSucceeded else {
                forgetDevice()
                let failed = DeviceSelectionResult.noMatch(candidateCount: candidates.count)
                lastSelection = failed
                return failed
            }
        }

        selectedDevice = device
        ledLuids = recognisedLuids
        if !isSameSelection || topologyChanged { hasWrittenSinceSelection = false }

        let priorityError = session.setLayerPriority(layerPriority)
        if priorityError != Int32(SC_ICUE_SUCCESS.rawValue) {
            log.notice("could not set shared layer priority (code \(priorityError)); continuing at the default")
        }

        let recognised = ledLuids.compactMap(MouseZone.init(rawValue:))
        let ignored = reportedLuids.count - recognisedLuids.count
        log.info(
            "lighting target: \(device.safeModel), \(ledLuids.count) LEDs, \(device.redactedIdentifier); "
            + "zones \(recognised.map(\.displayName).joined(separator: "+"))"
            + (ignored > 0 ? " (+\(ignored) unrecognised left to iCUE)" : "")
        )
        return result
    }

    /// The zones this device actually exposes. Empty until `refreshDevice()`
    /// has succeeded.
    public var availableZones: [MouseZone] {
        ledLuids.compactMap(MouseZone.init(rawValue:))
    }

    public func apply(_ frame: LightingFrame) throws {
        guard let device = selectedDevice, !ledLuids.isEmpty else {
            throw LightingError.deviceNotFound
        }
        guard session.state.isUsable else {
            throw LightingError.notConnected
        }

        let payload = frame.resolve(availableLuids: ledLuids)
        let error = session.setColors(deviceIdentifier: device.identifier, colors: payload)
        guard error == Int32(SC_ICUE_SUCCESS.rawValue) else {
            if error == Int32(SC_ICUE_DEVICE_NOT_FOUND.rawValue) {
                // The mouse went to sleep or dropped its wireless link. Forget
                // it so the next refresh re-selects cleanly instead of writing
                // into a stale identifier.
                forgetDevice()
                throw LightingError.deviceNotFound
            }
            if error == Int32(SC_ICUE_NOT_CONNECTED.rawValue) {
                throw LightingError.notConnected
            }
            throw LightingError.writeFailed(error)
        }
        hasWrittenSinceSelection = true
    }

    /// Hands the mouse back to iCUE.
    ///
    /// Alpha 0 means "this layer is completely translucent", which is the
    /// documented way for a *shared* client to stop contributing. It is not the
    /// same as writing black, which would leave the mouse dark.
    public func release() throws {
        guard let device = selectedDevice, !ledLuids.isEmpty else { return }
        guard session.state.isUsable else {
            // Nothing to release: with no session, our layer no longer exists
            // and iCUE is already back in charge.
            hasWrittenSinceSelection = false
            return
        }
        let payload = ledLuids.map { (luid: $0, color: RGBColor.transparent) }
        let error = session.setColors(deviceIdentifier: device.identifier, colors: payload)
        hasWrittenSinceSelection = false
        guard error == Int32(SC_ICUE_SUCCESS.rawValue) else {
            // Do not leave a stale Hue/mode colour visible for the rest of a
            // healthy-looking session. Ending this SDK client is the vendor's
            // fail-safe guarantee that iCUE discards its shared layer; the app
            // lifecycle reconnects without re-entering multi-tap mode.
            log.error("release() returned code \(error); disconnecting the SDK session for safety")
            session.disconnectForLightingSafety()
            return
        }
        log.info("lighting layer released; ordinary iCUE lighting restored")
    }

    private func forgetDevice() {
        selectedDevice = nil
        ledLuids = []
        hasWrittenSinceSelection = false
    }

    /// Clears a layer only when the old identifier is still enumerated. A
    /// disconnect notification can race stale enumeration, so explicitly
    /// excluded identifiers are never written to even if they remain listed.
    @discardableResult
    private func releasePreviousSelectionIfReachable(
        reachableIdentifiers: Set<String>,
        excludedIdentifiers: Set<String>
    ) -> Bool {
        guard hasWrittenSinceSelection,
              let previous = selectedDevice,
              !ledLuids.isEmpty,
              session.state.isUsable,
              reachableIdentifiers.contains(previous.identifier),
              !excludedIdentifiers.contains(previous.identifier)
        else { return true }

        let payload = ledLuids.map { (luid: $0, color: RGBColor.transparent) }
        let error = session.setColors(deviceIdentifier: previous.identifier, colors: payload)
        hasWrittenSinceSelection = false
        if error == Int32(SC_ICUE_SUCCESS.rawValue) {
            log.info("released the previous mouse lighting layer before changing selection")
            return true
        } else {
            log.error("previous mouse lighting release returned code \(error); disconnecting the SDK session for safety")
            session.disconnectForLightingSafety()
            return false
        }
    }
}
