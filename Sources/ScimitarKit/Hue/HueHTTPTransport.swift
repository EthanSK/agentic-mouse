import Foundation

/// Connection details for the local bridge.
///
/// Neither field is ever written to this repository: `host` and
/// `applicationKey` come from the user's local config / Keychain, and both are
/// redacted everywhere they are logged.
public struct HueBridgeCredentials: Equatable, Sendable {
    public var host: String
    public var applicationKey: String

    public init(host: String, applicationKey: String) {
        self.host = host
        self.applicationKey = applicationKey
    }

    public var isConfigured: Bool {
        !host.isEmpty
            && !applicationKey.isEmpty
            && !host.hasPrefix("REPLACE_ME")
            && !applicationKey.hasPrefix("REPLACE_ME")
    }

    public var redactedDescription: String {
        "\(Redaction.host(host)) key=\(Redaction.secret(applicationKey))"
    }
}

/// Read-only HTTPS client for a local Hue bridge.
///
/// Three properties are enforced structurally rather than by convention:
///
///  * **Only GET.** `perform(_:)` is private and hard-codes `httpMethod =
///    "GET"`. There is no code path in this type — or anywhere else in the
///    library — that can issue PUT, POST or DELETE against a bridge.
///  * **Local only.** The bridge is reached directly on the LAN. Nothing is
///    sent to Philips' cloud, and no remote API is contacted.
///  * **Host-scoped trust exception.** Hue bridges present a certificate signed by Philips'
///    own root whose common name is the bridge id, which system trust rejects.
///    The delegate accepts the presented trust only for the exact configured
///    host. This is not certificate or public-key pinning and does not defend
///    against an attacker on the LAN who can impersonate that host.
public final class HueHTTPTransport: NSObject, HueReadOnlyTransport, @unchecked Sendable {
    private let credentials: HueBridgeCredentials
    private let log: Log
    private let timeout: TimeInterval
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        // The event stream is deliberately long-lived; the resource timeout
        // must not cut it off.
        configuration.timeoutIntervalForResource = .infinity
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    public init(credentials: HueBridgeCredentials, log: Log, timeout: TimeInterval = 8) {
        self.credentials = credentials
        self.log = log
        self.timeout = timeout
        super.init()
    }

    // MARK: - Read-only API

    public func get(resourcePath: String) async throws -> Data {
        guard credentials.isConfigured else {
            throw HueTransportError.notConfigured("Hue bridge host or application key is not set.")
        }
        let trimmed = resourcePath.hasPrefix("/") ? String(resourcePath.dropFirst()) : resourcePath
        guard let url = URL(string: "https://\(credentials.host)/clip/v2/resource/\(trimmed)") else {
            throw HueTransportError.notConfigured("Could not build a URL for the configured bridge host.")
        }
        return try await perform(url: url, accept: "application/json")
    }

    public func eventStream() -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard self.credentials.isConfigured else {
                        throw HueTransportError.notConfigured("Hue bridge host or application key is not set.")
                    }
                    guard let url = URL(string: "https://\(self.credentials.host)/eventstream/clip/v2") else {
                        throw HueTransportError.notConfigured("Could not build the event-stream URL.")
                    }

                    var request = URLRequest(url: url)
                    request.httpMethod = "GET"
                    request.setValue(self.credentials.applicationKey, forHTTPHeaderField: "hue-application-key")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.timeoutInterval = .infinity

                    let (bytes, response) = try await self.session.bytes(for: request)
                    if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                        throw http.statusCode == 401 || http.statusCode == 403
                            ? HueTransportError.unauthorised
                            : HueTransportError.http(http.statusCode)
                    }

                    // Minimal SSE framing: accumulate `data:` lines until a
                    // blank line terminates the event.
                    var payload = ""
                    for try await line in bytes.lines {
                        if line.isEmpty {
                            if !payload.isEmpty {
                                continuation.yield(Data(payload.utf8))
                                payload = ""
                            }
                            continue
                        }
                        if line.hasPrefix("data:") {
                            let chunk = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                            if !payload.isEmpty { payload += "\n" }
                            payload += chunk
                        }
                        // `id:`, `:` heartbeats and any other field are ignored.
                    }
                    if !payload.isEmpty {
                        continuation.yield(Data(payload.utf8))
                    }
                    continuation.finish(throwing: HueTransportError.streamEnded)
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Request plumbing

    /// The only place a network request is constructed. Hard-wired to GET.
    private func perform(url: URL, accept: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.httpBody = nil
        request.setValue(credentials.applicationKey, forHTTPHeaderField: "hue-application-key")
        request.setValue(accept, forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw HueTransportError.network("Unexpected response type.")
            }
            switch http.statusCode {
            case 200...299:
                return data
            case 401, 403:
                throw HueTransportError.unauthorised
            default:
                throw HueTransportError.http(http.statusCode)
            }
        } catch let error as HueTransportError {
            throw error
        } catch {
            throw HueTransportError.network(error.localizedDescription)
        }
    }
}

// MARK: - Certificate handling

extension HueHTTPTransport: URLSessionDelegate {
    public func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // Hue bridges serve a certificate signed by Philips' private root with
        // the bridge id as the common name, so system evaluation fails. This
        // host check limits the trust exception to the configured request host,
        // but does not authenticate the certificate itself (it is not pinning).
        guard challenge.protectionSpace.host == credentials.host else {
            log.error("rejected TLS challenge for an unexpected host")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}
