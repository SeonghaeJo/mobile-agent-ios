# OpenClaw Mobile for iOS

Native SwiftUI control-plane client for one remote OpenClaw Gateway. Milestone 1 is intentionally limited to connection, authentication, pairing guidance, health, session listing/subscription, and reconnect behavior. It does not implement chat, runs, tools, artifacts, terminal, notifications, or other runtimes.

## Architecture

`SwiftUI App` → `GatewayClient` actor → `URLSessionWebSocketTask` → `Tailscale HTTPS/WSS` → OpenClaw Gateway. `OpenClawKit` contains protocol, secure storage, and transport code and has no SwiftUI dependency.

```
OpenClawMobile/
  App.swift                 # onboarding and sessions UI
OpenClawKit/Sources/
  Protocol.swift            # JSON values, frames, session models, state
  GatewayClient.swift       # WebSocket, handshake, RPC, events, reconnect
  SecureStore.swift         # Keychain, Ed25519 identity and signing
```

## Protocol investigation (OpenClaw 2026.9.6)

The implementation was checked against the [Gateway protocol](https://docs.openclaw.ai/gateway/protocol), [handshake](https://docs.openclaw.ai/gateway/protocol/handshake), [auth](https://docs.openclaw.ai/gateway/protocol/auth), [bootstrap/events](https://docs.openclaw.ai/gateway/protocol/rpc-bootstrap-and-events), [session control](https://docs.openclaw.ai/gateway/protocol/rpc-session-control), and the `v2026.9.6` source checkout at [openclaw/openclaw](https://github.com/openclaw/openclaw):

* Gateway uses the supplied `ws://`/`wss://` URL and sends `connect.challenge` first, with `payload.nonce` and `payload.ts`.
* Operator clients negotiate protocol 4 (`minProtocol: 4`, `maxProtocol: 4`), send `role: operator`, and request the least scope used here: `operator.read`.
* Connect is a `req` frame with `id`, `method: connect`, and `params`. Device identity uses an Ed25519 keypair; the reference operator client signs the canonical v2 payload `v2|deviceId|clientId|clientMode|role|scopes|signedAtMs|token|nonce`, using URL-safe base64 for public key/signature.
* Frames are `req`/`res`/`event`; responses use `id`, `ok`, `payload` or `error`. Successful connect returns a `hello-ok` payload and may issue `auth.deviceToken`.
* After authentication the app calls `health`, `sessions.list` (requesting only fields the Gateway returns), and `sessions.subscribe`. `sessions.changed` triggers a fresh `sessions.list`.

## Credentials and pairing

Enter the Gateway's Tailscale-reachable `wss://` URL and bootstrap Gateway token on the first screen. The bootstrap token is never logged and is only held in memory for this session. The Ed25519 private key, device identity, and issued device token are stored in Keychain; no secret is written to UserDefaults. If the Gateway rejects the device pending approval, the UI shows the pairing state/request identifier and a reconnect button. Approve the request using the Gateway's device approval command, then tap reconnect.

## Reconnect and lifecycle

The client reconnects after WebSocket close or temporary Gateway failure with exponential backoff (1–32 seconds), fails pending RPC continuations on socket failure, and reconnects when the app returns to foreground. The Gateway remains the execution plane; the iOS app only observes and controls the connection.

## Run and verify

Open `OpenClawMobile.xcodeproj` in Xcode 15+ on macOS, select an iOS 17+ simulator/device, and run. `Package.swift` exposes `OpenClawKit` for unit-testable protocol code. In this environment Xcode, iOS SDK, Swift compiler, and a live Gateway were unavailable, so build, simulator execution, live handshake, pairing, health, session data, Tailscale/WSS, and reconnect behavior could not be executed here. Static source review and protocol comparison against the checked-out reference source were performed.

## Next milestone

Add session detail/read-only observation, chat and streaming, run/tool timeline, artifacts, approvals, and push notifications only after Milestone 1 is validated against the real Gateway.
