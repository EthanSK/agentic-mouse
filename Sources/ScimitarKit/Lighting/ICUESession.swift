import CICUEBridge
import Foundation

public enum ICUESessionState: Equatable, Sendable {
    case closed
    case connecting
    case connected
    case timedOut
    case connectionRefused
    case connectionLost

    init(rawState: Int32) {
        switch rawState {
        case Int32(SC_ICUE_SESSION_CONNECTING.rawValue): self = .connecting
        case Int32(SC_ICUE_SESSION_CONNECTED.rawValue): self = .connected
        case Int32(SC_ICUE_SESSION_TIMEOUT.rawValue): self = .timedOut
        case Int32(SC_ICUE_SESSION_CONNECTION_REFUSED.rawValue): self = .connectionRefused
        case Int32(SC_ICUE_SESSION_CONNECTION_LOST.rawValue): self = .connectionLost
        default: self = .closed
        }
    }

    public var isUsable: Bool { self == .connected }

    public var explanation: String {
        switch self {
        case .closed: return "Not connected to iCUE."
        case .connecting: return "Connecting to iCUE…"
        case .connected: return "Connected to iCUE."
        case .timedOut: return "iCUE did not respond. Is iCUE running?"
        case .connectionRefused:
            return "iCUE refused the connection. Enable Settings → 'Enable SDK' / third-party control in iCUE."
        case .connectionLost: return "iCUE closed the connection."
        }
    }
}

public struct ICUEDevice: Equatable, Sendable {
    /// Opaque identifier used for SDK calls. Never logged, never persisted.
    public let identifier: String
    public let model: String
    public let ledCount: Int
    public let channelCount: Int
    public let typeMask: Int32

    public var redactedIdentifier: String { Redaction.identifier(identifier) }
    public var safeModel: String { Redaction.model(model) }

    public var summary: LightingDeviceSummary {
        LightingDeviceSummary(model: safeModel, ledCount: ledCount, redactedIdentifier: redactedIdentifier)
    }
}

public struct ICUELed: Equatable, Sendable {
    public let luid: UInt32
    public let x: Double
    public let y: Double
}

public struct ICUEKeyEvent: Equatable, Sendable {
    public let deviceIdentifier: String
    public let macroKeyId: Int
    public let isPressed: Bool
}

public struct ICUEVersion: Equatable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int
    public var description: String { "\(major).\(minor).\(patch)" }
    public var isZero: Bool { major == 0 && minor == 0 && patch == 0 }
}

public struct ICUESessionDetails: Equatable, Sendable {
    public let client: ICUEVersion
    public let server: ICUEVersion
    public let host: ICUEVersion
}

/// The two access levels this project is permitted to ask for.
///
/// `CAL_ExclusiveLightingControl` (1) and
/// `CAL_ExclusiveLightingControlAndKeyEventsListening` (3) are not represented
/// here at all, and the C bridge rejects their raw values, so no code path in
/// the companion can request exclusive *lighting* control.
public enum ICUEAccessLevel: Int32, Sendable {
    case shared = 0
    /// Exclusive key events, shared lighting. Held only while multi-tap mode is
    /// active, and only for the one selected Scimitar.
    case exclusiveKeyEvents = 2
}

/// Swift face of the iCUE SDK.
///
/// This is a process-wide singleton because the underlying C API is: there is
/// exactly one `CorsairConnect` session and one event subscription per process.
/// Pretending otherwise would let two owners fight over the same global state.
///
/// Lighting is always written through the *shared* layer. Input control is a
/// separate axis: `requestKeyControl` can take `CAL_ExclusiveKeyEventsListening`
/// for one device id, which is documented as "exclusive key events, but shared
/// lightings" and is what makes multi-tap mode genuinely modal.
/// SDK entry points are used on the main thread. The vendor's callbacks may
/// arrive on arbitrary threads, but they copy their payload and dispatch it to
/// the main queue before touching this object's mutable Swift state.
public final class ICUESession: @unchecked Sendable {
    public static let shared = ICUESession()

    /// Where to look for the SDK, in order. The framework is proprietary and is
    /// never vendored into this repository.
    public static func defaultLibrarySearchPaths(bundlePath: String? = nil) -> [String] {
        var paths: [String] = []
        if let bundlePath {
            paths.append("\(bundlePath)/Contents/Frameworks/iCUESDK.framework/Versions/A/iCUESDK")
            paths.append("\(bundlePath)/Contents/Frameworks/iCUESDK.framework/iCUESDK")
            paths.append("\(bundlePath)/Contents/Frameworks/libiCUESDK.dylib")
        }
        paths.append(contentsOf: [
            "\(NSHomeDirectory())/.local/lib/iCUESDK.framework/Versions/A/iCUESDK",
            "\(NSHomeDirectory())/.local/lib/libiCUESDK.dylib",
            "/usr/local/lib/iCUESDK.framework/Versions/A/iCUESDK",
            "/usr/local/lib/libiCUESDK.dylib",
            "/Library/Frameworks/iCUESDK.framework/Versions/A/iCUESDK",
            // The mounted SDK disk image, useful during development only.
            "/Volumes/iCUESDK/iCUESDK.framework/Versions/A/iCUESDK",
            "/Volumes/iCUESDK/libiCUESDK.dylib"
        ])
        return paths
    }

    private var log: Log = Log(category: "icue", sink: NullLogSink())

    public private(set) var isLibraryLoaded = false
    public private(set) var resolvedLibraryPath: String?
    public private(set) var state: ICUESessionState = .closed

    /// Called on the main queue.
    public var onStateChange: ((ICUESessionState) -> Void)?
    public var onKeyEvent: ((ICUEKeyEvent) -> Void)?
    public var onDeviceConnectionChange: ((String, Bool) -> Void)?

    private var isConnected = false
    private var isSubscribed = false
    private var sessionCallbackGeneration: UInt64 = 0
    private var eventCallbackGeneration: UInt64 = 0

    /// Each C callback carries the generation of the registration that created
    /// it. A callback already queued on the main thread before reload is then
    /// harmless after a disconnect/reconnect instead of reaching new handlers.
    private final class CallbackContext {
        weak var session: ICUESession?
        let generation: UInt64

        init(session: ICUESession, generation: UInt64) {
            self.session = session
            self.generation = generation
        }
    }

    private var sessionCallbackContext: CallbackContext?
    private var eventCallbackContext: CallbackContext?
    /// The vendor API can fail to unregister. A callback context must therefore
    /// remain alive for the process lifetime even after its generation is
    /// invalidated; otherwise a late C callback could dereference freed memory
    /// before Swift has a chance to apply the generation guard.
    private var retiredCallbackContexts: [CallbackContext] = []

    private init() {}

    public func configure(log: Log) {
        self.log = log
    }

    // MARK: - Library

    @discardableResult
    public func loadLibrary(searchPaths: [String]) -> Result<String, LightingError> {
        if isLibraryLoaded, let resolvedLibraryPath {
            return .success(resolvedLibraryPath)
        }
        guard !searchPaths.isEmpty else {
            return .failure(.sdkUnavailable("no search paths configured"))
        }

        let compatibility = ICUELibraryCompatibility.validateExistingCandidates(searchPaths)
        guard !compatibility.accepted.isEmpty else {
            let message = ICUELibraryCompatibility.failureExplanation
            log.error("iCUE SDK not loadable: \(message)")
            return .failure(.sdkUnavailable(message))
        }

        var resolved = [CChar](repeating: 0, count: 1024)
        let cPaths = compatibility.accepted.map { strdup($0) }
        defer { cPaths.forEach { free($0) } }

        let loaded: Int32 = cPaths.withUnsafeBufferPointer { buffer -> Int32 in
            buffer.baseAddress!.withMemoryRebound(to: UnsafePointer<CChar>?.self, capacity: buffer.count) { rebound in
                Int32(sc_icue_load(rebound, Int32(buffer.count), &resolved, 1024))
            }
        }

        guard loaded == 1 else {
            let message = String(cString: sc_icue_last_error())
            log.error("iCUE SDK not loadable: \(message.isEmpty ? "unknown reason" : message)")
            return .failure(.sdkUnavailable(message.isEmpty ? "library not found" : message))
        }

        isLibraryLoaded = true
        resolvedLibraryPath = String(cString: resolved)
        log.info("iCUE SDK loaded from \(Redaction.tag(resolvedLibraryPath ?? ""))")
        return .success(resolvedLibraryPath ?? "")
    }

    // MARK: - Session

    public func connect() -> Result<Void, LightingError> {
        guard isLibraryLoaded else { return .failure(.sdkUnavailable("SDK not loaded")) }
        guard !isConnected else { return .success(()) }

        sessionCallbackGeneration &+= 1
        let callbackContext = CallbackContext(session: self, generation: sessionCallbackGeneration)
        sessionCallbackContext = callbackContext
        let context = Unmanaged.passUnretained(callbackContext).toOpaque()
        let error = sc_icue_connect({ context, event in
            guard let context, let event else { return }
            let callback = Unmanaged<CallbackContext>.fromOpaque(context).takeUnretainedValue()
            callback.session?.handleSessionState(
                Int32(event.pointee.state),
                generation: callback.generation
            )
        }, context)

        guard error == Int32(SC_ICUE_SUCCESS.rawValue) else {
            sessionCallbackContext = nil
            log.error("CorsairConnect failed with code \(error)")
            return .failure(.writeFailed(error))
        }
        isConnected = true
        return .success(())
    }

    public func subscribeToEvents() -> Result<Void, LightingError> {
        guard isLibraryLoaded else { return .failure(.sdkUnavailable("SDK not loaded")) }
        guard !isSubscribed else { return .success(()) }

        eventCallbackGeneration &+= 1
        let callbackContext = CallbackContext(session: self, generation: eventCallbackGeneration)
        eventCallbackContext = callbackContext
        let context = Unmanaged.passUnretained(callbackContext).toOpaque()
        let error = sc_icue_subscribe_for_events({ context, event in
            guard let context, let event else { return }
            let callback = Unmanaged<CallbackContext>.fromOpaque(context).takeUnretainedValue()
            callback.session?.handleEvent(event.pointee, generation: callback.generation)
        }, context)

        guard error == Int32(SC_ICUE_SUCCESS.rawValue) else {
            eventCallbackContext = nil
            log.error("CorsairSubscribeForEvents failed with code \(error)")
            return .failure(.writeFailed(error))
        }
        isSubscribed = true
        log.info("subscribed to iCUE macro-key events (shared access level)")
        return .success(())
    }

    public func unsubscribeFromEvents() {
        guard isSubscribed else { return }
        eventCallbackGeneration &+= 1
        let oldContext = eventCallbackContext
        _ = sc_icue_unsubscribe_from_events()
        isSubscribed = false
        eventCallbackContext = nil
        if let oldContext { retiredCallbackContexts.append(oldContext) }
    }

    public func disconnect() {
        unsubscribeFromEvents()
        guard isConnected else { return }
        sessionCallbackGeneration &+= 1
        let oldContext = sessionCallbackContext
        _ = sc_icue_disconnect()
        isConnected = false
        state = .closed
        sessionCallbackContext = nil
        if let oldContext { retiredCallbackContexts.append(oldContext) }
    }

    public func sessionDetails() -> ICUESessionDetails? {
        guard isLibraryLoaded else { return nil }
        var raw = sc_icue_session_details()
        guard sc_icue_get_session_details(&raw) == Int32(SC_ICUE_SUCCESS.rawValue) else { return nil }
        func convert(_ version: sc_icue_version) -> ICUEVersion {
            ICUEVersion(major: Int(version.major), minor: Int(version.minor), patch: Int(version.patch))
        }
        return ICUESessionDetails(
            client: convert(raw.client_version),
            server: convert(raw.server_version),
            host: convert(raw.server_host_version)
        )
    }

    // MARK: - Devices

    /// Enumerates devices matching `typeMask` (default: mice only).
    public func devices(typeMask: Int32 = Int32(SC_ICUE_DEVICE_TYPE_MOUSE)) -> [ICUEDevice] {
        guard isLibraryLoaded, state.isUsable else { return [] }
        var filter = sc_icue_device_filter(device_type_mask: typeMask)
        var count: Int32 = 0
        var buffer = [sc_icue_device_info](repeating: sc_icue_device_info(), count: Int(SC_ICUE_DEVICE_COUNT_MAX))

        let error = sc_icue_get_devices(&filter, Int32(SC_ICUE_DEVICE_COUNT_MAX), &buffer, &count)
        guard error == Int32(SC_ICUE_SUCCESS.rawValue), count > 0 else { return [] }

        return (0..<Int(count)).map { index in
            var info = buffer[index]
            return ICUEDevice(
                identifier: Self.string(from: &info.id),
                model: Self.string(from: &info.model),
                ledCount: Int(info.led_count),
                channelCount: Int(info.channel_count),
                typeMask: info.type
            )
        }
    }

    /// LEDs of a device, sorted front-to-back then top-to-bottom so that an
    /// `AccentSelector` always picks the same physical zone.
    public func leds(of deviceIdentifier: String) -> [ICUELed] {
        guard isLibraryLoaded, state.isUsable else { return [] }
        var count: Int32 = 0
        var buffer = [sc_icue_led_position](
            repeating: sc_icue_led_position(),
            count: Int(SC_ICUE_DEVICE_LEDCOUNT_MAX)
        )
        let error = deviceIdentifier.withCString { pointer in
            sc_icue_get_led_positions(pointer, Int32(SC_ICUE_DEVICE_LEDCOUNT_MAX), &buffer, &count)
        }
        guard error == Int32(SC_ICUE_SUCCESS.rawValue), count > 0 else { return [] }

        return (0..<Int(count))
            .map { ICUELed(luid: buffer[$0].id, x: buffer[$0].cx, y: buffer[$0].cy) }
            .sorted { lhs, rhs in
                if lhs.y != rhs.y { return lhs.y < rhs.y }
                if lhs.x != rhs.x { return lhs.x < rhs.x }
                return lhs.luid < rhs.luid
            }
    }

    /// Reads the programmable macro (G/M/S) keys a device reports, if any.
    ///
    /// This is the honest answer to "does the Scimitar expose its side buttons
    /// to the SDK?". An empty result means it does not, on this firmware, with
    /// this iCUE profile — in which case the event-tap transport is the only
    /// workable input route.
    public func macroKeyIdentifiers(of deviceIdentifier: String) -> [Int] {
        guard isLibraryLoaded, state.isUsable else { return [] }
        var property = sc_icue_make_empty_property()
        let error = deviceIdentifier.withCString { pointer in
            sc_icue_read_device_property(
                pointer,
                Int32(SC_ICUE_PROPERTY_MACRO_KEY_ARRAY.rawValue),
                0,
                &property
            )
        }
        guard error == Int32(SC_ICUE_SUCCESS.rawValue) else { return [] }
        defer { _ = sc_icue_free_property(&property) }

        guard property.type == Int32(SC_ICUE_DATA_INT32_ARRAY.rawValue) else { return [] }
        let array = property.value.array
        guard let items = array.items, array.count > 0 else { return [] }
        let typed = items.assumingMemoryBound(to: Int32.self)
        return (0..<Int(array.count)).map { Int(typed[$0]) }
    }

    public func batteryLevel(of deviceIdentifier: String) -> Int? {
        guard isLibraryLoaded, state.isUsable else { return nil }
        var property = sc_icue_make_empty_property()
        let error = deviceIdentifier.withCString { pointer in
            sc_icue_read_device_property(
                pointer,
                Int32(SC_ICUE_PROPERTY_BATTERY_LEVEL.rawValue),
                0,
                &property
            )
        }
        guard error == Int32(SC_ICUE_SUCCESS.rawValue) else { return nil }
        defer { _ = sc_icue_free_property(&property) }
        guard property.type == Int32(SC_ICUE_DATA_INT32.rawValue) else { return nil }
        return Int(property.value.int32)
    }

    // MARK: - Lighting (shared layer only)

    /// Sets this client's shared layer priority. iCUE itself sits at 127 and
    /// other shared clients default to 128, so a slightly higher value puts the
    /// companion on top without ever asking for exclusive control.
    @discardableResult
    public func setLayerPriority(_ priority: UInt32) -> Int32 {
        guard isLibraryLoaded else { return Int32(SC_ICUE_LIBRARY_NOT_LOADED.rawValue) }
        return sc_icue_set_layer_priority(min(priority, UInt32(SC_ICUE_LAYER_PRIORITY_MAX)))
    }

    public func setColors(deviceIdentifier: String, colors: [(luid: UInt32, color: RGBColor)]) -> Int32 {
        guard isLibraryLoaded else { return Int32(SC_ICUE_LIBRARY_NOT_LOADED.rawValue) }
        guard !colors.isEmpty else { return Int32(SC_ICUE_SUCCESS.rawValue) }

        let payload = colors.map {
            sc_icue_led_color(
                id: $0.luid,
                r: $0.color.red,
                g: $0.color.green,
                b: $0.color.blue,
                a: $0.color.alpha
            )
        }
        return deviceIdentifier.withCString { pointer in
            payload.withUnsafeBufferPointer { buffer in
                sc_icue_set_led_colors(pointer, Int32(buffer.count), buffer.baseAddress)
            }
        }
    }

    // MARK: - Key control (input only)

    /// Requests an access level for **one** device id.
    ///
    /// Returns the raw SDK error code so the caller can distinguish the cases
    /// that matter operationally:
    ///   * `CE_NotAllowed` (7)  — key interception is switched off in iCUE.
    ///   * `CE_NoControl` (2)   — another SDK client already holds it.
    ///   * `CE_DeviceNotFound`  — the mouse went away mid-transaction.
    public func requestKeyControl(deviceIdentifier: String, level: ICUEAccessLevel) -> Int32 {
        guard isLibraryLoaded else { return Int32(SC_ICUE_LIBRARY_NOT_LOADED.rawValue) }
        return deviceIdentifier.withCString { sc_icue_request_key_control($0, level.rawValue) }
    }

    /// Returns the device to the default shared access level. Safe to call even
    /// if control was never granted; the SDK treats it as a no-op.
    @discardableResult
    public func releaseControl(deviceIdentifier: String) -> Int32 {
        guard isLibraryLoaded else { return Int32(SC_ICUE_LIBRARY_NOT_LOADED.rawValue) }
        return deviceIdentifier.withCString { sc_icue_release_control($0) }
    }

    /// Marks one macro key as intercepted (`true`) or released back to all SDK
    /// clients (`false`).
    @discardableResult
    public func configureKeyEvent(
        deviceIdentifier: String,
        macroKeyId: Int,
        intercepted: Bool
    ) -> Int32 {
        guard isLibraryLoaded else { return Int32(SC_ICUE_LIBRARY_NOT_LOADED.rawValue) }
        var config = sc_icue_key_event_configuration(
            key_id: Int32(macroKeyId),
            is_intercepted: intercepted
        )
        return deviceIdentifier.withCString { pointer in
            sc_icue_configure_key_event(pointer, &config)
        }
    }

    // MARK: - Callbacks

    private func handleSessionState(_ rawState: Int32, generation: UInt64) {
        let newState = ICUESessionState(rawState: rawState)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard generation == self.sessionCallbackGeneration else { return }
            guard newState != self.state else { return }
            self.state = newState
            switch newState {
            case .closed, .timedOut, .connectionRefused, .connectionLost:
                // The vendor session is terminal. Retire callback registrations
                // before the app is told, so its reconnect attempt creates a
                // genuinely new C session/subscription rather than hitting the
                // local `isConnected`/`isSubscribed` guards.
                self.isConnected = false
                self.isSubscribed = false
                self.sessionCallbackGeneration &+= 1
                self.eventCallbackGeneration &+= 1
                if let context = self.sessionCallbackContext {
                    self.retiredCallbackContexts.append(context)
                }
                if let context = self.eventCallbackContext {
                    self.retiredCallbackContexts.append(context)
                }
                self.sessionCallbackContext = nil
                self.eventCallbackContext = nil
            case .connecting, .connected:
                break
            }
            self.log.info("iCUE session: \(String(describing: newState))")
            self.onStateChange?(newState)
        }
    }

    private func handleEvent(_ event: sc_icue_event, generation: UInt64) {
        switch event.id {
        case Int32(SC_ICUE_EVENT_KEY.rawValue):
            guard let keyPointer = event.data.key else { return }
            var raw = keyPointer.pointee
            let payload = ICUEKeyEvent(
                deviceIdentifier: Self.string(from: &raw.device_id),
                macroKeyId: Int(raw.key_id),
                isPressed: raw.is_pressed
            )
            DispatchQueue.main.async { [weak self] in
                guard let self, generation == self.eventCallbackGeneration else { return }
                self.onKeyEvent?(payload)
            }

        case Int32(SC_ICUE_EVENT_DEVICE_CONNECTION_STATUS_CHANGED.rawValue):
            guard let pointer = event.data.device_connection else { return }
            var raw = pointer.pointee
            let identifier = Self.string(from: &raw.device_id)
            let connected = raw.is_connected
            DispatchQueue.main.async { [weak self] in
                guard let self, generation == self.eventCallbackGeneration else { return }
                self.onDeviceConnectionChange?(identifier, connected)
            }

        default:
            break
        }
    }

    // MARK: - Helpers

    /// Reads a fixed-size C char array as a Swift string without over-reading.
    static func string<T>(from tuple: inout T) -> String {
        withUnsafeBytes(of: &tuple) { rawBytes in
            let bytes = rawBytes.bindMemory(to: UInt8.self)
            let end = bytes.firstIndex(of: 0) ?? bytes.endIndex
            return String(decoding: bytes[..<end], as: UTF8.self)
        }
    }
}
