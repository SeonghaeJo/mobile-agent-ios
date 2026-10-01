import SwiftUI

@main struct OpenClawMobileApp: App { var body: some Scene { WindowGroup { RootView() } } }

@MainActor final class AppModel: ObservableObject {
    @Published var url = "wss://"
    @Published var token = ""
    @Published var state: GatewayConnectionState = .disconnected
    @Published var sessions: [OpenClawSession] = []
    @Published var showSetup = true
    private var client: GatewayClient?

    func connect() {
        guard let gatewayURL = URL(string: url), gatewayURL.scheme == "wss" || gatewayURL.scheme == "ws", !token.isEmpty else { state = .error("Enter a valid Gateway URL and token."); return }
        let client = GatewayClient(url: gatewayURL, bootstrapToken: token)
        self.client = client
        Task { await client.setCallbacks(state: { [weak self] value in Task { @MainActor in self?.state = value } }, sessions: { [weak self] value in Task { @MainActor in self?.sessions = value; self?.showSetup = false } }); await client.start() }
    }
    func reconnect() { Task { await client?.reconnectNow() } }
    func disconnect() { Task { await client?.stop() }; state = .disconnected }
}

struct RootView: View {
    @StateObject private var model = AppModel()
    var body: some View { NavigationStack { Group { if model.showSetup { SetupView(model: model) } else { SessionsView(model: model) } }.navigationTitle("OpenClaw") }.onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in model.reconnect() } }
}

struct SetupView: View {
    @ObservedObject var model: AppModel
    var body: some View { Form { Section("Gateway") { TextField("wss://gateway.example", text: $model.url).keyboardType(.URL).textInputAutocapitalization(.never); SecureField("Gateway token", text: $model.token) }
        Section { Button("Connect") { model.connect() }.disabled(model.token.isEmpty) }
        StatusView(state: model.state)
        if case .waitingForApproval(let requestId) = model.state { Section("Device approval required") { Text("Approve this device in the Gateway, then reconnect."); if let requestId { Text("Request ID: \(requestId)").textSelection(.enabled) }; Text("Use the Gateway's device approval command for this request.").font(.footnote).foregroundStyle(.secondary); Button("Reconnect") { model.reconnect() } } }
    }.onAppear { if case .connected = model.state { model.showSetup = false } } }
}

struct SessionsView: View {
    @ObservedObject var model: AppModel
    var body: some View { List { if model.sessions.isEmpty { ContentUnavailableView("No sessions", systemImage: "rectangle.stack", description: Text("The Gateway returned no sessions.")) } else { ForEach(model.sessions) { session in VStack(alignment: .leading, spacing: 5) { Text(session.displayName ?? session.label ?? session.key).font(.headline); Text(session.key).font(.caption).foregroundStyle(.secondary); HStack { if let agentId = session.agentId { Label(agentId, systemImage: "cpu") }; if let modelName = session.model { Label(modelName, systemImage: "brain") }; if session.running == true { Label("Running", systemImage: "play.circle.fill") } }.font(.caption); if let preview = session.lastMessagePreview { Text(preview).font(.subheadline).lineLimit(2) } } } } }.refreshable { model.reconnect() }.toolbar { ToolbarItem(placement: .topBarLeading) { StatusView(state: model.state) }; ToolbarItem(placement: .topBarTrailing) { Button("Settings", systemImage: "gear") { model.showSetup = true } } } }
}

struct StatusView: View { let state: GatewayConnectionState; var body: some View { Label(title, systemImage: icon).foregroundStyle(color).font(.subheadline); }
    private var title: String { switch state { case .connecting: "Connecting"; case .authenticating: "Authenticating"; case .waitingForApproval: "Waiting for approval"; case .connected: "Connected"; case .reconnecting: "Reconnecting"; case .error(let value): value; case .disconnected: "Disconnected" } }
    private var icon: String { switch state { case .connected: "checkmark.circle.fill"; case .error: "exclamationmark.triangle.fill"; default: "circle.dotted" } }
    private var color: Color { switch state { case .connected: .green; case .error: .red; case .waitingForApproval: .orange; default: .secondary } }
}

private extension GatewayClient {
    func setCallbacks(state: @escaping @Sendable (GatewayConnectionState) -> Void, sessions: @escaping @Sendable ([OpenClawSession]) -> Void) { onState = state; onSessions = sessions }
}
