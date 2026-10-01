import Foundation

public actor GatewayClient {
    public let url: URL
    private let bootstrapToken: String
    private let store: SecureStore
    private var socket: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var pending: [String: CheckedContinuation<JSONValue, Error>] = [:]
    private var challenge: (nonce: String, timestamp: Int64)?
    private var identity: DeviceIdentity?
    private var stopped = false
    private var retry = 0
    private let encoder = JSONEncoder(); private let decoder = JSONDecoder()
    public var onState: (@Sendable (GatewayConnectionState) -> Void)?
    public var onSessions: (@Sendable ([OpenClawSession]) -> Void)?

    public init(url: URL, bootstrapToken: String, store: SecureStore = .shared) { self.url = url; self.bootstrapToken = bootstrapToken; self.store = store }
    public func start() { stopped = false; Task { await connect() } }
    public func stop() { stopped = true; reconnectTask?.cancel(); receiveTask?.cancel(); socket?.cancel(with: .goingAway, reason: nil); failPending(GatewayError.disconnected); socket = nil; emit(.disconnected) }
    public func reconnectNow() { reconnectTask?.cancel(); Task { await connect() } }

    private func emit(_ state: GatewayConnectionState) { onState?(state) }
    private func connect() async { guard !stopped else { return }; challenge = nil; emit(retry == 0 ? .connecting : .reconnecting); let task = URLSession.shared.webSocketTask(with: url); socket = task; task.resume(); receiveTask = Task { [weak self] in await self?.receiveLoop(task) }; do { try await waitForChallenge(); emit(.authenticating); try await authenticate(); _ = try await call("health"); let value = try await call("sessions.list", params: .object(["includeGlobal":.bool(true), "includeUnknown":.bool(false), "includeLastMessage":.bool(true)])); publishSessions(value); _ = try await call("sessions.subscribe"); retry = 0; emit(.connected) } catch { guard !stopped else { return }; if let gatewayError = error as? GatewayError, case .pairingRequired(let requestId) = gatewayError { emit(.waitingForApproval(requestId: requestId)) } else { emit(.error(error.localizedDescription)) }; scheduleReconnect() } }
    private func waitForChallenge() async throws { for _ in 0..<60 { if challenge != nil { return }; try? await Task.sleep(for: .milliseconds(100)); if Task.isCancelled { throw GatewayError.disconnected } }; throw GatewayError.timeout }
    private func authenticate() async throws { guard let challenge else { throw GatewayError.timeout }; let id = store.identity(); identity = id; let signedAt = challenge.timestamp; let credential = store.string(for: "device-token-\(url.absoluteString)") ?? bootstrapToken; store.set(bootstrapToken, for: "bootstrap-token-\(url.absoluteString)"); let payload = ["v2", id.deviceId, "openclaw-ios", "ui", "operator", "operator.read", String(signedAt), credential, challenge.nonce].joined(separator: "|"); guard let signature = store.sign(payload, identity: id), let publicData = Data(base64Encoded: id.publicKey) else { throw GatewayError.protocolError("cannot create device signature") }; let publicKey = publicData.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: ""); let device: JSONValue = .object(["id":.string(id.deviceId), "publicKey":.string(publicKey), "signature":.string(signature), "signedAt":.number(Double(signedAt)), "nonce":.string(challenge.nonce)]); let params: JSONValue = .object(["minProtocol":.number(4), "maxProtocol":.number(4), "client":.object(["id":.string("openclaw-ios"), "version":.string("1.0"), "platform":.string("ios"), "mode":.string("ui")]), "role":.string("operator"), "scopes":.array([.string("operator.read")]), "auth":.object(["token":.string(credential)]), "device":device, "locale":.string(Locale.current.identifier)]); do { let result = try await call("connect", params: params); if result["type"]?.string != "hello-ok" { throw GatewayError.protocolError("missing hello-ok") }; if let token = result["auth"]?["deviceToken"]?.string { store.set(token, for: "device-token-\(url.absoluteString)") } } catch let error as GatewayError { if case .rejected(let message) = error, message.localizedStandardContains("pair") || message.localizedStandardContains("approv") { throw GatewayError.pairingRequired(nil) }; throw error } }
    public func call(_ method: String, params: JSONValue? = nil) async throws -> JSONValue { guard socket != nil else { throw GatewayError.disconnected }; let id = UUID().uuidString; let frame = RequestFrame(type: "req", id: id, method: method, params: params); let data = try encoder.encode(frame); guard let socket else { throw GatewayError.disconnected }; try await socket.send(.data(data)); return try await withCheckedThrowingContinuation { continuation in pending[id] = continuation; Task { try? await Task.sleep(for: .seconds(15)); await self.timeout(id: id) } } }
    private func timeout(id: String) { if let c = pending.removeValue(forKey: id) { c.resume(throwing: GatewayError.timeout) } }
    private func receiveLoop(_ task: URLSessionWebSocketTask) async { while !stopped { do { let message = try await task.receive(); let data: Data; switch message { case .data(let d): data = d; case .string(let s): data = Data(s.utf8); @unknown default: continue }; try handle(data) } catch { if !stopped { failPending(error); scheduleReconnect() }; return } } }
    private func handle(_ data: Data) throws { let raw = try decoder.decode(JSONValue.self, from: data); guard let object = raw.object, let type = object["type"]?.string else { throw GatewayError.protocolError("invalid frame") }; if type == "event", let event = object["event"]?.string { let payload = object["payload"]; if event == "connect.challenge", let nonce = payload?["nonce"]?.string, let ts = payload?["ts"]?.double { challenge = (nonce, Int64(ts)); return }; if event == "sessions.changed" { Task { if let value = try? await call("sessions.list", params: .object(["includeGlobal":.bool(true), "includeUnknown":.bool(false), "includeLastMessage":.bool(true)])) { publishSessions(value) } }; return } }; if type == "res", let id = object["id"]?.string, let continuation = pending.removeValue(forKey:id) { if object["ok"]?.bool == true { continuation.resume(returning: object["payload"] ?? .null) } else { continuation.resume(throwing: GatewayError.rejected(object["error"]?["message"]?.string ?? "Gateway rejected request")) } } }
    private func publishSessions(_ value: JSONValue) { let array = value["sessions"]?.arrayValue ?? value.arrayValue ?? []; let sessions = array.compactMap { try? JSONDecoder().decode(OpenClawSession.self, from: JSONEncoder().encode($0)) }; onSessions?(sessions) }
    private func scheduleReconnect() { guard !stopped, reconnectTask == nil else { return }; retry = min(retry + 1, 6); let delay = min(pow(2.0, Double(retry - 1)), 32); reconnectTask = Task { try? await Task.sleep(for: .seconds(delay)); await self.clearReconnectAndConnect() } }
    private func clearReconnectAndConnect() { reconnectTask = nil; Task { await connect() } }
    private func failPending(_ error: Error) { pending.values.forEach { $0.resume(throwing: error) }; pending.removeAll() }
}

private extension JSONValue { var arrayValue: [JSONValue]? { if case .array(let value) = self { return value }; return nil } }
