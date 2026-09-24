// BridgeMobile.swift — Swift SDK for iOS / macOS
// 自動生成於 2026-08-06，從 lib/services/mobile_bridge_client.dart 同步
//
// 用法：
//   1. `pod install`
//   2. `import BridgeMobile`
//   3. `let client = BridgeClient(host: "192.168.x.x", port: 9123)`
//   4. `try await client.connect()`
//
// 完整文件見：packages/bridge-mobile/docs/

import Foundation
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Connection State

public enum BridgeConnectionState: String {
    case disconnected
    case connecting
    case connected
    case handshaking
    case ready
    case error
}

// MARK: - Connection Event

public struct BridgeConnectionEvent {
    public let state: BridgeConnectionState
    public let message: String?

    public init(state: BridgeConnectionState, message: String? = nil) {
        self.state = state
        self.message = message
    }
}

// MARK: - Bridge Message

public struct BridgeMessage {
    public let type: String
    public let taskId: String?
    public let payload: [String: Any]

    public init(type: String, taskId: String? = nil, payload: [String: Any]) {
        self.type = type
        self.taskId = taskId
        self.payload = payload
    }
}

// MARK: - Bridge Client

public actor BridgeClient {
    public let host: String
    public let port: Int
    public var state: BridgeConnectionState = .disconnected

    private var urlSession: URLSession?
    private var webSocketTask: URLSessionWebSocketTask?
    private var reconnectTask: Task<Void, Never>?

    private var onMessageHandlers: [(BridgeMessage) -> Void] = []
    private var onStateChangeHandlers: [(BridgeConnectionEvent) -> Void] = []

    public init(host: String, port: Int = 9123) {
        self.host = host
        self.port = port
    }

    // MARK: - Connection Lifecycle

    public func connect() async throws {
        await updateState(.connecting)

        let url = URL(string: "ws://\(host):\(port)")!
        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()

        await updateState(.connected)
        try await sendHello()

        receiveLoop()
    }

    public func disconnect() {
        reconnectTask?.cancel()
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        updateStateSync(.disconnected)
    }

    // MARK: - Sending

    private func sendHello() async throws {
        let deviceId: String = {
            #if canImport(UIKit)
            return UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
            #else
            return UUID().uuidString
            #endif
        }()
        let hello: [String: Any] = [
            "type": "hello",
            "deviceId": deviceId,
            "platform": "ios",
            "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        ]
        try await send(hello)
        await updateState(.handshaking)
    }

    public func sendTask(taskType: String, payload: [String: Any], taskId: String = UUID().uuidString) async throws {
        let msg: [String: Any] = [
            "type": "task.run",
            "taskId": taskId,
            "taskType": taskType,
            "payload": payload
        ]
        try await send(msg)
    }

    public func cancelTask(taskId: String) async throws {
        let msg: [String: Any] = [
            "type": "task.cancel",
            "taskId": taskId
        ]
        try await send(msg)
    }

    private func send(_ object: [String: Any]) async throws {
        let data = try JSONSerialization.data(withJSONObject: object)
        let str = String(data: data, encoding: .utf8)!
        try await webSocketTask?.send(.string(str))
    }

    // MARK: - Receiving

    private func receiveLoop() {
        Task { [weak self] in
            while let self = self {
                do {
                    guard let task = await self.webSocketTask else { break }
                    let message = try await task.receive()

                    switch message {
                    case .string(let text):
                        if let data = text.data(using: .utf8),
                           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            let bridgeMsg = BridgeMessage(
                                type: dict["type"] as? String ?? "",
                                taskId: dict["taskId"] as? String,
                                payload: (dict["payload"] as? [String: Any]) ?? [:]
                            )
                            await self.fireMessage(bridgeMsg)

                            if bridgeMsg.type == "hello_ack" {
                                await self.updateState(.ready)
                            }
                        }
                    default:
                        break
                    }
                } catch {
                    await self.handleDisconnect(error: error)
                    break
                }
            }
        }
    }

    private func handleDisconnect(error: Error) async {
        updateStateSync(.error)
        reconnectTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            try? await self.connect()
        }
    }

    // MARK: - Event Handlers

    public func onMessage(_ handler: @escaping (BridgeMessage) -> Void) {
        onMessageHandlers.append(handler)
    }

    public func onStateChange(_ handler: @escaping (BridgeConnectionEvent) -> Void) {
        onStateChangeHandlers.append(handler)
    }

    private func fireMessage(_ message: BridgeMessage) {
        for handler in onMessageHandlers {
            handler(message)
        }
    }

    private func updateState(_ newState: BridgeConnectionState) {
        state = newState
        let event = BridgeConnectionEvent(state: newState)
        for handler in onStateChangeHandlers {
            handler(event)
        }
    }

    nonisolated private func updateStateSync(_ newState: BridgeConnectionState) {
        Task { await self.updateState(newState) }
    }
}

// MARK: - UIColor Extension (85 BridgeDS Color Tokens)
