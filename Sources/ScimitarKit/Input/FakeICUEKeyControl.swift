import Foundation

/// A scriptable stand-in for the iCUE session's key-control surface.
///
/// Lives in the library rather than the test bundle so that `agentic-mouse-doctor
/// simulate` can drive the entire coordinator, HUD and lighting pipeline on a
/// machine with no iCUE, no SDK and no mouse.
public final class FakeICUEKeyControl: ICUEKeyControlling {
    public enum Call: Equatable {
        case subscribe
        case readMacroKeys
        case requestControl(level: Int32)
        case releaseControl
        case configure(key: Int, intercepted: Bool)
        case disconnectForSafety
    }

    public var isSessionUsable: Bool
    public var onMacroKeyEvent: ((ICUEKeyEvent) -> Void)?

    public var deviceIdentifier: String
    /// What `CDPI_MacroKeyArray` reports. Default matches the audited Scimitar.
    public var macroKeys: [Int] = Array(1...12)

    public var subscribeResult: Result<Void, LightingError> = .success(())
    /// Raw SDK code returned by `requestKeyControl`. 0 = success.
    public var requestControlCode: Int32 = 0
    public var releaseControlCode: Int32 = 0
    /// Per-key override for `configureKeyEvent`; anything absent returns 0.
    public var configureCodes: [Int: Int32] = [:]
    public var unconfigureCodes: [Int: Int32] = [:]

    public private(set) var calls: [Call] = []
    /// Keys currently marked intercepted, so tests can assert clean rollback.
    public private(set) var interceptedKeys: Set<Int> = []
    public private(set) var currentAccessLevel: ICUEAccessLevel = .shared

    public init(deviceIdentifier: String = "fake-scimitar", isSessionUsable: Bool = true) {
        self.deviceIdentifier = deviceIdentifier
        self.isSessionUsable = isSessionUsable
    }

    public func subscribeToMacroKeyEvents() -> Result<Void, LightingError> {
        calls.append(.subscribe)
        return subscribeResult
    }

    public func macroKeyIdentifiers(of deviceIdentifier: String) -> [Int] {
        calls.append(.readMacroKeys)
        guard deviceIdentifier == self.deviceIdentifier else { return [] }
        return macroKeys
    }

    public func requestKeyControl(deviceIdentifier: String, level: ICUEAccessLevel) -> Int32 {
        calls.append(.requestControl(level: level.rawValue))
        guard requestControlCode == 0 else { return requestControlCode }
        currentAccessLevel = level
        return 0
    }

    @discardableResult
    public func releaseControl(deviceIdentifier: String) -> Int32 {
        calls.append(.releaseControl)
        guard releaseControlCode == 0 else { return releaseControlCode }
        currentAccessLevel = .shared
        interceptedKeys.removeAll()
        return 0
    }

    @discardableResult
    public func configureKeyEvent(deviceIdentifier: String, macroKeyId: Int, intercepted: Bool) -> Int32 {
        calls.append(.configure(key: macroKeyId, intercepted: intercepted))
        if intercepted, let code = configureCodes[macroKeyId], code != 0 {
            return code
        }
        if !intercepted, let code = unconfigureCodes[macroKeyId], code != 0 { return code }
        if intercepted {
            interceptedKeys.insert(macroKeyId)
        } else {
            interceptedKeys.remove(macroKeyId)
        }
        return 0
    }

    public func disconnectForRollbackSafety() {
        calls.append(.disconnectForSafety)
        interceptedKeys.removeAll()
        currentAccessLevel = .shared
        isSessionUsable = false
    }

    // MARK: - Simulation

    /// Emits a raw macro-key event as iCUE would.
    public func emit(macroKeyId: Int, isPressed: Bool, from device: String? = nil) {
        onMacroKeyEvent?(
            ICUEKeyEvent(
                deviceIdentifier: device ?? deviceIdentifier,
                macroKeyId: macroKeyId,
                isPressed: isPressed
            )
        )
    }

    public func emitTap(macroKeyId: Int) {
        emit(macroKeyId: macroKeyId, isPressed: true)
        emit(macroKeyId: macroKeyId, isPressed: false)
    }

    public func resetCalls() {
        calls.removeAll()
    }

    /// True when nothing is intercepted and the device is back on shared access.
    public var isFullyReleased: Bool {
        interceptedKeys.isEmpty && currentAccessLevel == .shared
    }
}
