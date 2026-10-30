import Foundation
import ScimitarKit

/// One bounded, cancellable move-and-restore transaction across both mice.
@MainActor
final class OrganizeWindowsController {
    struct Operations {
        var capture: () throws -> ChromeSpaceRestorer.Target?
        var move: (ChromeSpaceRestorer.Target) throws -> Void
        var membership: (UInt32) throws -> [UInt64]
        var destinationStillVisible: (ChromeSpaceRestorer.Target) throws -> Bool
        var restore: () -> Bool
    }
    private let operations: Operations
    private let inputAllowed: () -> Bool
    private var task: Task<Void, Never>?
    private var owner: MouseSource?
    private var generation = 0
    var onCompletion: ((MouseSource, Bool) -> Void)?
    var onDiagnostic: ((String) -> Void)?

    init(operations: Operations, inputAllowed: @escaping () -> Bool) {
        self.operations = operations
        self.inputAllowed = inputAllowed
    }

    @discardableResult
    func start(source: MouseSource) -> Bool {
        guard inputAllowed(), task == nil else { return false }
        owner = source
        generation += 1
        let token = generation
        onDiagnostic?("Organize Windows requested")
        task = Task { [weak self] in
            guard let self else { return }
            var succeeded = false
            do {
                try self.check(token)
                let target: ChromeSpaceRestorer.Target?
                do {
                    target = try self.operations.capture()
                } catch ChromeSpaceRestorer.Failure.ambiguousWindow {
                    // Several off-Space Chrome windows must not be moved by
                    // guesswork, but they must not block Stay's saved layout.
                    self.onDiagnostic?("Multiple off-Space Chrome windows; skipping Chrome Space move and requesting Stay restore")
                    target = nil
                }
                if let target {
                    try self.check(token)
                    try self.operations.move(target)
                    var arrived = false
                    for _ in 0..<40 {
                        try self.check(token)
                        guard try self.operations.destinationStillVisible(target) else { throw ChromeSpaceRestorer.Failure.spaceChanged }
                        if try self.operations.membership(target.window) == [target.destination] { arrived = true; break }
                        try await Task.sleep(nanoseconds: 25_000_000)
                    }
                    guard arrived else { throw ChromeSpaceRestorer.Failure.moveFailed }
                }
                try self.check(token)
                succeeded = self.operations.restore()
                self.onDiagnostic?(succeeded ? "Stay restore shortcut posted" : "Stay shortcut could not be posted")
            } catch {
                self.onDiagnostic?("Organize Windows failed: \(String(describing: error))")
            }
            guard self.generation == token else { return }
            self.task = nil
            self.owner = nil
            self.onCompletion?(source, succeeded)
        }
        return true
    }

    func cancel(source: MouseSource? = nil) {
        guard source == nil || source == owner else { return }
        generation += 1
        task?.cancel()
        task = nil
        owner = nil
    }

    private func check(_ token: Int) throws {
        guard token == generation, inputAllowed(), !Task.isCancelled else { throw CancellationError() }
    }
}
