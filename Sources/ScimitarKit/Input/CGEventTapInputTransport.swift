#if canImport(CoreGraphics)
import CoreGraphics
import Foundation

/// **Fallback transport only. Not the default, and not device-safe.**
///
/// The primary route is `ICUEMacroKeyTransport`, which receives raw
/// `CorsairKeyEvent`s attributed to one exact device id and suppresses the
/// normal side-button actions through `CorsairConfigureKeyEvent` under
/// `CAL_ExclusiveKeyEventsListening`.
///
/// This CGEvent tap exists for one situation: the iCUE SDK is unavailable or
/// key interception has been switched off in iCUE's settings, and Ethan has
/// deliberately configured the side buttons to emit distinguishable mouse
/// buttons or keystrokes. It carries limitations that the primary route does
/// not, and the companion states them rather than hiding them:
///
///  * **No device attribution.** A CGEvent carries no device identity, so a
///    matching button on the Logitech would be indistinguishable from the
///    Scimitar. Anything this transport sees, it treats as the Scimitar.
///  * **It cannot see a button that iCUE consumes.** A side button assigned to
///    "Next Track" arrives as a media event, not a mouse button, so it will not
///    be recognised.
///  * **It needs Accessibility permission** to exist at all, whereas the
///    primary route only needs it to type.
///
/// Because of the first point this transport is never selected automatically.
/// It must be opted into with `input.transport = "cgEventTap"`.
public final class CGEventTapInputTransport: InputTransport {
    public weak var delegate: InputTransportDelegate?
    public var name: String { "cgEventTap (fallback)" }

    public private(set) var isInterceptionEnabled = false
    public private(set) var isRunning = false

    private let clock: MonotonicClock
    private let permission: AccessibilityPermissionChecking
    private let log: Log
    private let runLoop: CFRunLoop
    /// Converts an unattributed fallback CGEvent into the same logical key
    /// representation as the primary iCUE transport.
    private let logicalKeyByBinding: [InputBinding: MultiTapKey]
    private var observedBindings: Set<InputBinding> { Set(logicalKeyByBinding.keys) }
    /// Swallowed even when interception is off, because pressing it is what
    /// turns interception on. Normally just the mode toggle.
    private let alwaysInterceptedBindings: Set<InputBinding>

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let stateLock = NSLock()

    public init(
        logicalKeyByBinding: [InputBinding: MultiTapKey],
        alwaysInterceptedBindings: Set<InputBinding> = [],
        permission: AccessibilityPermissionChecking = AccessibilityPermission(),
        clock: MonotonicClock = SystemMonotonicClock(),
        log: Log,
        runLoop: CFRunLoop = CFRunLoopGetMain()
    ) {
        self.logicalKeyByBinding = logicalKeyByBinding
        self.alwaysInterceptedBindings = alwaysInterceptedBindings
        self.permission = permission
        self.clock = clock
        self.log = log
        self.runLoop = runLoop
    }

    deinit { stop() }

    // MARK: - Lifecycle

    public func start() throws {
        guard !isRunning else { return }
        guard permission.isTrusted else { throw InputTransportError.accessibilityPermissionMissing }

        let mask = Self.eventMask(for: observedBindings)
        guard mask != 0 else { throw InputTransportError.notAvailable("no bindings to observe") }

        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let transport = Unmanaged<CGEventTapInputTransport>.fromOpaque(refcon).takeUnretainedValue()
                return transport.handle(type: type, event: event)
            },
            userInfo: context
        ) else {
            throw InputTransportError.eventTapCreationFailed
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else {
            throw InputTransportError.eventTapCreationFailed
        }

        CFRunLoopAddSource(runLoop, source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)

        tap = port
        runLoopSource = source
        isRunning = true
        log.notice("FALLBACK event tap started; device attribution is not available on this route")
    }

    public func stop() {
        endInterception()
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(runLoop, runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        isRunning = false
        log.info("event tap stopped; all input restored to normal")
    }

    public func preflight() -> InputTransportReadiness {
        var reasons: [String] = []
        if !permission.isTrusted {
            reasons.append("Accessibility permission is required for the event-tap fallback.")
        }
        if !isRunning {
            reasons.append("Event tap is not running.")
        }
        if observedBindings.isEmpty {
            reasons.append("No input bindings are configured for the fallback transport.")
        }
        return reasons.isEmpty ? .ready : .notReady(reasons)
    }

    public func beginInterception() throws {
        guard isRunning else { throw InputTransportError.notAvailable("event tap not running") }
        stateLock.lock()
        isInterceptionEnabled = true
        stateLock.unlock()
        log.info("fallback interception enabled")
    }

    public func endInterception() {
        stateLock.lock()
        let changed = isInterceptionEnabled
        isInterceptionEnabled = false
        stateLock.unlock()
        if changed { log.info("fallback interception disabled; pass-through restored") }
    }

    // MARK: - Tap callback

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            log.notice("event tap was disabled by the system; re-enabled")
            delegate?.inputTransport(self, didFailWith: InputTransportError.notAvailable("tap disabled"))
            return Unmanaged.passUnretained(event)
        }

        guard let (binding, phase) = Self.decode(type: type, event: event),
              let logicalKey = logicalKeyByBinding[binding]
        else {
            return Unmanaged.passUnretained(event)
        }

        delegate?.inputTransport(
            self,
            didReceive: PhysicalInputEvent(
                binding: .icueMacroKey(logicalKey.rawValue),
                phase: phase,
                timestamp: clock.now
            )
        )

        stateLock.lock()
        let interceptionOn = isInterceptionEnabled
        stateLock.unlock()

        let shouldSwallow = alwaysInterceptedBindings.contains(binding) || interceptionOn
        return shouldSwallow ? nil : Unmanaged.passUnretained(event)
    }

    // MARK: - Encoding helpers

    static func eventMask(for bindings: Set<InputBinding>) -> CGEventMask {
        var mask: CGEventMask = 0
        if bindings.contains(where: \.isMouseButton) {
            mask |= (1 << CGEventType.otherMouseDown.rawValue)
            mask |= (1 << CGEventType.otherMouseUp.rawValue)
        }
        if bindings.contains(where: \.isKeyCode) {
            mask |= (1 << CGEventType.keyDown.rawValue)
            mask |= (1 << CGEventType.keyUp.rawValue)
        }
        return mask
    }

    static func decode(type: CGEventType, event: CGEvent) -> (InputBinding, PhysicalInputEvent.Phase)? {
        switch type {
        case .otherMouseDown:
            return (.mouseButton(Int(event.getIntegerValueField(.mouseEventButtonNumber))), .press)
        case .otherMouseUp:
            return (.mouseButton(Int(event.getIntegerValueField(.mouseEventButtonNumber))), .release)
        case .keyDown, .keyUp:
            if type == .keyDown, event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return nil }
            let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            return (
                .keyCode(code, modifiers: modifierSet(from: event.flags)),
                type == .keyDown ? .press : .release
            )
        default:
            return nil
        }
    }

    static func modifierSet(from flags: CGEventFlags) -> ModifierSet {
        var set: ModifierSet = []
        if flags.contains(.maskCommand) { set.insert(.command) }
        if flags.contains(.maskAlternate) { set.insert(.option) }
        if flags.contains(.maskControl) { set.insert(.control) }
        if flags.contains(.maskShift) { set.insert(.shift) }
        if flags.contains(.maskSecondaryFn) { set.insert(.function) }
        return set
    }
}
#endif
