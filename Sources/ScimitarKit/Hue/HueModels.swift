import Foundation

/// The subset of a Hue v2 `light` resource this project cares about.
///
/// Everything here is read-only by construction. There is no encoder, no
/// mutation helper and no "apply" method anywhere in the Hue layer.
public struct HueLightState: Equatable, Sendable {
    /// CIE 1931 xy chromaticity, when the light reports a colour.
    public struct Chromaticity: Equatable, Sendable {
        public var x: Double
        public var y: Double
        public init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }
    }

    public var identifier: String
    public var isOn: Bool
    /// 0…100 as Hue reports it.
    public var brightnessPercent: Double?
    public var chromaticity: Chromaticity?
    /// Reciprocal megakelvin. Only meaningful when `mirekValid` is true.
    public var mirek: Int?
    public var mirekValid: Bool

    public init(
        identifier: String,
        isOn: Bool,
        brightnessPercent: Double? = nil,
        chromaticity: Chromaticity? = nil,
        mirek: Int? = nil,
        mirekValid: Bool = false
    ) {
        self.identifier = identifier
        self.isOn = isOn
        self.brightnessPercent = brightnessPercent
        self.chromaticity = chromaticity
        self.mirek = mirek
        self.mirekValid = mirekValid
    }

    /// Merges a partial event payload over a known state.
    ///
    /// Hue's event stream sends *deltas*: an event that only changes brightness
    /// carries no colour at all. Blindly replacing state with the delta would
    /// make the mouse flash white every time the lamp dims, so unspecified
    /// fields must be inherited.
    public func merging(_ delta: HueLightDelta) -> HueLightState {
        var merged = self
        if let isOn = delta.isOn { merged.isOn = isOn }
        if let brightness = delta.brightnessPercent { merged.brightnessPercent = brightness }
        if let chromaticity = delta.chromaticity {
            merged.chromaticity = chromaticity
            // A colour update supersedes any colour-temperature reading.
            merged.mirekValid = false
        }
        if let mirek = delta.mirek {
            merged.mirek = mirek
            merged.mirekValid = delta.mirekValid ?? true
            if delta.chromaticity == nil { merged.chromaticity = nil }
        }
        return merged
    }
}

/// A partial update from the event stream.
public struct HueLightDelta: Equatable, Sendable {
    public var identifier: String
    public var isOn: Bool?
    public var brightnessPercent: Double?
    public var chromaticity: HueLightState.Chromaticity?
    public var mirek: Int?
    public var mirekValid: Bool?

    public init(
        identifier: String,
        isOn: Bool? = nil,
        brightnessPercent: Double? = nil,
        chromaticity: HueLightState.Chromaticity? = nil,
        mirek: Int? = nil,
        mirekValid: Bool? = nil
    ) {
        self.identifier = identifier
        self.isOn = isOn
        self.brightnessPercent = brightnessPercent
        self.chromaticity = chromaticity
        self.mirek = mirek
        self.mirekValid = mirekValid
    }

    public var isEmpty: Bool {
        isOn == nil && brightnessPercent == nil && chromaticity == nil && mirek == nil
    }
}

// MARK: - Wire format

/// Decoders for the Hue CLIP v2 JSON. Kept separate from the domain model so a
/// firmware update that adds fields cannot break the domain logic.
public enum HueWireFormat {
    private struct ResourceEnvelope: Decodable {
        let data: [LightResource]?
        let errors: [ErrorEntry]?

        struct ErrorEntry: Decodable { let description: String? }
    }

    private struct LightResource: Decodable {
        struct OnState: Decodable { let on: Bool? }
        struct Dimming: Decodable { let brightness: Double? }
        struct XY: Decodable { let x: Double?; let y: Double? }
        struct Color: Decodable { let xy: XY? }
        struct ColorTemperature: Decodable { let mirek: Int?; let mirek_valid: Bool? }

        let id: String?
        let type: String?
        let metadata: Metadata?
        let on: OnState?
        let dimming: Dimming?
        let color: Color?
        let color_temperature: ColorTemperature?

        struct Metadata: Decodable { let name: String? }
    }

    private struct EventEnvelope: Decodable {
        let type: String?
        let data: [LightResource]?
    }

    public enum DecodingFailure: Error, Equatable {
        case notJSON
        case bridgeError(String)
        case lightNotFound
    }

    /// Parses a `GET /clip/v2/resource/light/<id>` response.
    public static func parseLight(_ data: Data) throws -> HueLightState {
        let decoder = JSONDecoder()
        guard let envelope = try? decoder.decode(ResourceEnvelope.self, from: data) else {
            throw DecodingFailure.notJSON
        }
        if let errors = envelope.errors, let first = errors.first?.description, !first.isEmpty {
            throw DecodingFailure.bridgeError(first)
        }
        guard let resource = envelope.data?.first, let identifier = resource.id else {
            throw DecodingFailure.lightNotFound
        }
        return HueLightState(
            identifier: identifier,
            isOn: resource.on?.on ?? false,
            brightnessPercent: resource.dimming?.brightness,
            chromaticity: chromaticity(from: resource.color),
            mirek: resource.color_temperature?.mirek,
            mirekValid: resource.color_temperature?.mirek_valid ?? false
        )
    }

    /// Parses a `GET /clip/v2/resource/light` response into the full state of
    /// every light the bridge returned. This is the snapshot the event-stream
    /// deltas are merged onto.
    public static func parseLightStates(_ data: Data) throws -> [HueLightState] {
        let decoder = JSONDecoder()
        guard let envelope = try? decoder.decode(ResourceEnvelope.self, from: data) else {
            throw DecodingFailure.notJSON
        }
        if let errors = envelope.errors, let first = errors.first?.description, !first.isEmpty {
            throw DecodingFailure.bridgeError(first)
        }
        return (envelope.data ?? []).compactMap { resource in
            guard let identifier = resource.id else { return nil }
            return HueLightState(
                identifier: identifier,
                isOn: resource.on?.on ?? false,
                brightnessPercent: resource.dimming?.brightness,
                chromaticity: chromaticity(from: resource.color),
                mirek: resource.color_temperature?.mirek,
                mirekValid: resource.color_temperature?.mirek_valid ?? false
            )
        }
    }

    /// Parses a `GET /clip/v2/resource/light` response into every light found,
    /// used by the setup CLI to let the user pick the living-room lamps.
    public static func parseLightSummaries(_ data: Data) throws -> [(id: String, name: String)] {
        let decoder = JSONDecoder()
        guard let envelope = try? decoder.decode(ResourceEnvelope.self, from: data) else {
            throw DecodingFailure.notJSON
        }
        if let errors = envelope.errors, let first = errors.first?.description, !first.isEmpty {
            throw DecodingFailure.bridgeError(first)
        }
        return (envelope.data ?? []).compactMap { resource in
            guard let id = resource.id else { return nil }
            return (id: id, name: resource.metadata?.name ?? "(unnamed)")
        }
    }

    /// Parses one server-sent-event payload (a JSON array of event envelopes)
    /// and returns the deltas that concern lights.
    public static func parseEventDeltas(_ data: Data) -> [HueLightDelta] {
        let decoder = JSONDecoder()
        guard let events = try? decoder.decode([EventEnvelope].self, from: data) else { return [] }

        return events.flatMap { event -> [HueLightDelta] in
            guard event.type == "update" || event.type == nil else { return [] }
            return (event.data ?? []).compactMap { resource -> HueLightDelta? in
                guard let id = resource.id, resource.type == "light" || resource.type == nil else { return nil }
                let delta = HueLightDelta(
                    identifier: id,
                    isOn: resource.on?.on,
                    brightnessPercent: resource.dimming?.brightness,
                    chromaticity: chromaticity(from: resource.color),
                    mirek: resource.color_temperature?.mirek,
                    mirekValid: resource.color_temperature?.mirek_valid
                )
                return delta.isEmpty ? nil : delta
            }
        }
    }

    private static func chromaticity(from color: LightResource.Color?) -> HueLightState.Chromaticity? {
        guard let xy = color?.xy, let x = xy.x, let y = xy.y else { return nil }
        return HueLightState.Chromaticity(x: x, y: y)
    }
}
