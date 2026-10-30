import AppKit
import ApplicationServices

/// Optional SkyLight adapter. Normal Spaces only; never activates Chrome or
/// changes the visible Space. Every submitted move requires membership readback.
@MainActor
final class ChromeSpaceRestorer {
    struct Target: Equatable {
        let window: UInt32
        let source: UInt64
        let destination: UInt64
    }
    enum Failure: Error { case unavailable, ambiguousWindow, spaceChanged, moveFailed }
    private let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)

    private func symbol<T>(_ name: String, _ type: T.Type) throws -> T {
        guard handle != nil, let pointer = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) else {
            throw Failure.unavailable
        }
        return unsafeBitCast(pointer, to: type)
    }

    func membership(_ window: UInt32) throws -> [UInt64] {
        let connection = try symbol("SLSMainConnectionID", (@convention(c) () -> Int32).self)()
        let copy = try symbol("SLSCopySpacesForWindows", (@convention(c) (Int32, UInt64, CFArray) -> Unmanaged<CFArray>?).self)
        guard let values = copy(connection, 7, [NSNumber(value: window)] as CFArray)?.takeRetainedValue() as? [NSNumber] else {
            throw Failure.unavailable
        }
        return values.map(\.uint64Value)
    }

    /// Select the current desktop on the display owning the source Space,
    /// rather than NSScreen.main (which belongs to the foreground application).
    static func target(window: UInt32, membership: [UInt64], displays: [[String: Any]]) throws -> Target? {
        guard membership.count == 1, let source = membership.first else { throw Failure.ambiguousWindow }
        guard let display = displays.first(where: {
            ($0["Spaces"] as? [[String: Any]] ?? []).contains { ($0["ManagedSpaceID"] as? NSNumber)?.uint64Value == source }
        }), let spaces = display["Spaces"] as? [[String: Any]],
        let original = spaces.first(where: { ($0["ManagedSpaceID"] as? NSNumber)?.uint64Value == source }),
        let current = display["Current Space"] as? [String: Any],
        (original["type"] as? NSNumber)?.intValue == 0,
        (current["type"] as? NSNumber)?.intValue == 0,
        let destination = (current["ManagedSpaceID"] as? NSNumber)?.uint64Value else { throw Failure.unavailable }
        return source == destination ? nil : Target(window: window, source: source, destination: destination)
    }

    func inventory() throws -> [[String: Any]] {
        let connection = try symbol("SLSMainConnectionID", (@convention(c) () -> Int32).self)()
        let copy = try symbol("SLSCopyManagedDisplaySpaces", (@convention(c) (Int32) -> Unmanaged<CFArray>?).self)
        guard let values = copy(connection)?.takeRetainedValue() as? [[String: Any]] else { throw Failure.unavailable }
        return values
    }

    func capture() throws -> Target? {
        guard let chrome = NSRunningApplication.runningApplications(withBundleIdentifier: "com.google.Chrome").first else { return nil }
        let displays = try inventory()
        let normalSpaces = displays.flatMap { $0["Spaces"] as? [[String: Any]] ?? [] }
            .filter { ($0["type"] as? NSNumber)?.intValue == 0 }
            .compactMap { $0["ManagedSpaceID"] as? NSNumber }
        let connection = try symbol("SLSMainConnectionID", (@convention(c) () -> Int32).self)()
        typealias CopyWindows = @convention(c) (Int32, UInt32, CFArray, UInt32, UnsafeMutablePointer<UInt64>, UnsafeMutablePointer<UInt64>) -> Unmanaged<CFArray>?
        let copyWindows = try symbol("SLSCopyWindowsWithOptionsAndTags", CopyWindows.self)
        var setTags: UInt64 = 0
        var clearTags: UInt64 = 0
        // Option 2 excludes minimized windows while including other desktops.
        // ABI reference: Hammerspoon extensions/spaces/libspaces.m.
        guard let eligible = copyWindows(connection, 0, normalSpaces as CFArray, 2, &setTags, &clearTags)?.takeRetainedValue() as? [NSNumber],
              let rows = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { throw Failure.unavailable }
        let eligibleIDs = Set(eligible.map(\.uint32Value))
        var targets: [Target] = []
        for row in rows {
            guard (row[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == chrome.processIdentifier,
                  (row[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let id = (row[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  eligibleIDs.contains(id),
                  let bounds = row[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds),
                  frame.width >= 300, frame.height >= 200 else { continue }
            // Only a single ordinary Space is eligible: no fullscreen or
            // all-desktop windows, popovers, PiP, or invisible helper surfaces.
            if let target = try? Self.target(window: id, membership: membership(id), displays: displays) {
                targets.append(target)
            }
        }
        // AXWindows omits off-Space Chrome windows. WindowServer discovery
        // works there without activating Chrome or requiring window titles.
        guard targets.count <= 1 else { throw Failure.ambiguousWindow }
        return targets.first
    }

    func destinationStillVisible(_ target: Target) throws -> Bool {
        try inventory().contains { display in
            let current = display["Current Space"] as? [String: Any]
            return (current?["ManagedSpaceID"] as? NSNumber)?.uint64Value == target.destination
                && (current?["type"] as? NSNumber)?.intValue == 0
                && (display["Spaces"] as? [[String: Any]] ?? []).contains {
                    ($0["ManagedSpaceID"] as? NSNumber)?.uint64Value == target.source
                }
        }
    }

    func move(_ target: Target) throws {
        guard try capture() == target else { throw Failure.spaceChanged }
        try submit(window: target.window, destination: target.destination)
    }

    /// The bridged operation survives current macOS with SIP enabled. Older
    /// SLSMoveWindowsToManagedSpace/compat-ID calls can silently do nothing.
    /// ABI reference: DockDoor Utilities/PrivateApis.swift, bridged operation.
    func submit(window: UInt32, destination: UInt64) throws {
        guard handle != nil,
              let cls = NSClassFromString("SLSBridgedMoveWindowsToManagedSpaceOperation"),
              let allocated = (cls as AnyObject).perform(NSSelectorFromString("alloc"))?.takeUnretainedValue() else { throw Failure.unavailable }
        let initializer = NSSelectorFromString("initWithWindows:spaceID:")
        let perform = NSSelectorFromString("performWithWMBridgeDelegate")
        guard allocated.responds(to: initializer) else { throw Failure.unavailable }
        typealias Initialize = @convention(c) (AnyObject, Selector, NSArray, UInt64) -> Unmanaged<AnyObject>
        let initialize = unsafeBitCast(allocated.method(for: initializer), to: Initialize.self)
        let operation = initialize(allocated, initializer, [NSNumber(value: window)] as NSArray, destination).takeRetainedValue()
        guard operation.responds(to: perform) else { throw Failure.unavailable }
        typealias Perform = @convention(c) (AnyObject, Selector) -> Void
        unsafeBitCast(operation.method(for: perform), to: Perform.self)(operation, perform)
    }
}
