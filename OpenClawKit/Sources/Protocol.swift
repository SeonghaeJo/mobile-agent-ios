import Foundation

public enum JSONValue: Codable, Sendable, Equatable {
    case object([String: JSONValue]), array([JSONValue]), string(String), number(Double), bool(Bool), null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([String: JSONValue].self) { self = .object(value) }
        else { self = .array(try container.decode([JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self { case .object(let v): try container.encode(v); case .array(let v): try container.encode(v); case .string(let v): try container.encode(v); case .number(let v): try container.encode(v); case .bool(let v): try container.encode(v); case .null: try container.encodeNil() }
    }

    public var object: [String: JSONValue]? { if case .object(let value) = self { return value }; return nil }
    public var string: String? { if case .string(let value) = self { return value }; return nil }
    public var double: Double? { if case .number(let value) = self { return value }; return nil }
    public var bool: Bool? { if case .bool(let value) = self { return value }; return nil }
    public subscript(_ key: String) -> JSONValue? { object?[key] }
}

public struct RequestFrame: Codable, Sendable { public let type: String; public let id: String; public let method: String; public let params: JSONValue? }
public struct ErrorShape: Codable, Sendable { public let code: String?; public let message: String; public let details: JSONValue? }
public struct ResponseFrame: Codable, Sendable { public let type: String; public let id: String; public let ok: Bool; public let payload: JSONValue?; public let error: ErrorShape? }
public struct EventFrame: Codable, Sendable { public let type: String; public let event: String; public let payload: JSONValue?; public let seq: Int? }

public struct OpenClawSession: Codable, Sendable, Identifiable, Equatable {
    public let key: String
    public let sessionId: String?
    public let agentId: String?
    public let displayName: String?
    public let label: String?
    public let updatedAt: Double?
    public let channel: String?
    public let model: String?
    public let lastMessagePreview: String?
    public let running: Bool?
    public var id: String { key }

    enum CodingKeys: String, CodingKey { case key, sessionId, agentId, displayName, label, updatedAt, channel, model, lastMessagePreview, running, sessionKey, sessionIdSnake = "session_id", agentIdSnake = "agent_id", updatedAtSnake = "updated_at", lastMessage = "lastMessage" }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decodeIfPresent(String.self, forKey: .key) ?? (try c.decodeIfPresent(String.self, forKey: .sessionKey)) ?? "unknown"
        sessionId = try c.decodeIfPresent(String.self, forKey: .sessionId) ?? (try c.decodeIfPresent(String.self, forKey: .sessionIdSnake))
        agentId = try c.decodeIfPresent(String.self, forKey: .agentId) ?? (try c.decodeIfPresent(String.self, forKey: .agentIdSnake))
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName); label = try c.decodeIfPresent(String.self, forKey: .label)
        updatedAt = try c.decodeIfPresent(Double.self, forKey: .updatedAt) ?? (try c.decodeIfPresent(Double.self, forKey: .updatedAtSnake))
        channel = try c.decodeIfPresent(String.self, forKey: .channel); model = try c.decodeIfPresent(String.self, forKey: .model)
        lastMessagePreview = try c.decodeIfPresent(String.self, forKey: .lastMessagePreview) ?? (try c.decodeIfPresent(String.self, forKey: .lastMessage))
        running = try c.decodeIfPresent(Bool.self, forKey: .running)
    }
    public init(key: String, sessionId: String? = nil, agentId: String? = nil, displayName: String? = nil, label: String? = nil, updatedAt: Double? = nil, channel: String? = nil, model: String? = nil, lastMessagePreview: String? = nil, running: Bool? = nil) { self.key = key; self.sessionId = sessionId; self.agentId = agentId; self.displayName = displayName; self.label = label; self.updatedAt = updatedAt; self.channel = channel; self.model = model; self.lastMessagePreview = lastMessagePreview; self.running = running }
}

public enum GatewayConnectionState: Equatable, Sendable { case disconnected, connecting, authenticating, waitingForApproval(requestId: String?), connected, reconnecting, error(String) }
public enum GatewayError: LocalizedError, Sendable { case invalidURL, disconnected, timeout, rejected(String), pairingRequired(String?), protocolError(String); public var errorDescription: String? { switch self { case .invalidURL: "Enter a valid ws:// or wss:// URL."; case .disconnected: "Gateway is disconnected."; case .timeout: "Gateway request timed out."; case .rejected(let m): m; case .pairingRequired(let id): "Device approval is required. Request: \(id ?? "unknown")"; case .protocolError(let m): "Protocol error: \(m)" } } }
