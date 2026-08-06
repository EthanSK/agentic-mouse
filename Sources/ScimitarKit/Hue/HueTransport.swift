import Foundation

public enum HueTransportError: Error, Equatable {
    case notConfigured(String)
    case unauthorised
    case http(Int)
    case network(String)
    case streamEnded
    /// Raised if anything ever tries to send a non-GET request. The Hue layer
    /// is read-only by contract and by construction; this is the guard rail.
    case writeAttemptBlocked(String)
}

/// The read-only surface this project is allowed to use against a Hue bridge.
///
/// There is deliberately no `put`, `post`, `delete` or `send` in this protocol.
/// A conforming type physically cannot be asked to change a light, so "never
/// write to Philips Hue lights" is enforced by the type system rather than by
/// discipline.
public protocol HueReadOnlyTransport: AnyObject {
    /// Performs `GET <bridge>/clip/v2/resource/<path>`.
    func get(resourcePath: String) async throws -> Data

    /// Subscribes to the bridge's server-sent event stream. Each element is one
    /// raw SSE `data:` payload. The stream finishes when the connection drops;
    /// the caller is responsible for reconnecting.
    func eventStream() -> AsyncThrowingStream<Data, Error>
}

/// In-memory transport for tests. Also proves the read-only contract: it
/// records every request so a test can assert nothing but GETs ever happen.
public final class StubHueTransport: HueReadOnlyTransport {
    public private(set) var requestedPaths: [String] = []
    public var responses: [String: Result<Data, Error>] = [:]
    public var defaultResponse: Result<Data, Error> = .failure(HueTransportError.notConfigured("no stub response"))
    /// Optional per-request delays (one-based request index), used to prove a
    /// periodic snapshot cannot overwrite a newer stream delta.
    public var responseDelays: [Int: UInt64] = [:]

    private var streamContinuation: AsyncThrowingStream<Data, Error>.Continuation?

    public init() {}

    public func get(resourcePath: String) async throws -> Data {
        requestedPaths.append(resourcePath)
        let requestIndex = requestedPaths.count
        let response = responses[resourcePath] ?? defaultResponse
        if let delay = responseDelays[requestIndex], delay > 0 {
            try await Task.sleep(nanoseconds: delay)
        }
        switch response {
        case .success(let data): return data
        case .failure(let error): throw error
        }
    }

    public func eventStream() -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            self.streamContinuation = continuation
        }
    }

    public func emit(_ data: Data) {
        streamContinuation?.yield(data)
    }

    public func finishStream(throwing error: Error? = nil) {
        if let error {
            streamContinuation?.finish(throwing: error)
        } else {
            streamContinuation?.finish()
        }
        streamContinuation = nil
    }
}
