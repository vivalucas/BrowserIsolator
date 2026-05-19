import Foundation

/// 通过 Chrome DevTools Protocol 注入 navigator 属性覆盖，实现各环境指纹差异化
actor FingerprintInjector {

    enum State: String {
        case idle       // 未开始
        case waiting    // 等待 CDP 就绪
        case injected   // 已成功注入
    }

    private let debugPort: Int
    private let fingerprintScript: String
    private(set) var state: State = .idle
    private var starting = false
    private var disconnected = false
    private var injectedTargetIDs: Set<String> = []
    private var attachingTargetIDs: Set<String> = []
    private var browserTask: URLSessionWebSocketTask?
    private var listenTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var reconnectAttempts = 0
    private var nextCommandID = 1
    private var pendingResponses: [Int: CheckedContinuation<Void, Error>] = [:]
    private static let cdpResponseTimeoutNanoseconds: UInt64 = 10_000_000_000
    private static let maximumReconnectAttempts = 5

    init(debugPort: Int, instanceNumber: Int) {
        self.debugPort = debugPort
        self.fingerprintScript = Self.generateScript(instanceNumber: instanceNumber)
    }

    // MARK: - 指纹值生成

    /// 根据环境编号生成固定但各环境不同的指纹值
    /// 同一 profile 每次启动值一致，不同 profile 值不同
    private static func generateScript(instanceNumber: Int) -> String {
        let cores = [4, 6, 8, 10]
        let memory = [4, 8, 16]
        let num = max(instanceNumber, 1)
        let core = cores[(num - 1) % cores.count]
        let mem = memory[(num - 1) % memory.count]
        return """
        Object.defineProperty(navigator, 'hardwareConcurrency', {get: () => \(core), configurable: true});
        Object.defineProperty(navigator, 'deviceMemory', {get: () => \(mem), configurable: true});
        """
    }

    // MARK: - 对外接口

    func currentState() -> State { state }

    /// 启动 browser-level CDP 监听。首次同步当前 page target，之后由 Target 事件驱动注入新 target。
    func startInjection() async {
        guard !starting, browserTask == nil, !disconnected else { return }
        starting = true
        state = .waiting
        defer { starting = false }

        do {
            let browserURL = try await pollBrowserWebSocketURL()
            let task = URLSession.shared.webSocketTask(with: browserURL)
            browserTask = task
            task.resume()
            listenTask = Task { await listenForBrowserEvents(task: task) }

            try await sendBrowserCommand(
                task: task,
                method: "Target.setDiscoverTargets",
                params: ["discover": true]
            )
            try await sendBrowserCommand(
                task: task,
                method: "Target.setAutoAttach",
                params: [
                    "autoAttach": true,
                    "waitForDebuggerOnStart": false,
                    "flatten": true
                ]
            )

            for target in try await pollPageTargets() {
                try await attachToTargetIfNeeded(target.id, task: task)
            }
            state = .injected
            reconnectAttempts = 0
            print("[Fingerprint] CDP 监听已启动 port=\(debugPort)")
        } catch {
            closeBrowserConnection()
            state = .idle
            if !disconnected {
                print("[Fingerprint] 注入监听启动失败 port=\(debugPort): \(error.localizedDescription)")
                scheduleReconnect()
            }
        }
    }

    /// 断开连接（profile 停止时调用）
    func disconnect() {
        disconnected = true
        state = .idle
        starting = false
        reconnectTask?.cancel()
        reconnectTask = nil
        closeBrowserConnection()
        injectedTargetIDs.removeAll()
        attachingTargetIDs.removeAll()
    }

    // MARK: - HTTP 轮询

    private struct CDPVersion: Decodable {
        let webSocketDebuggerUrl: String
    }

    private struct CDPTarget: Decodable {
        let id: String
        let type: String
        let webSocketDebuggerUrl: String?
    }

    /// 轮询 browser-level WebSocket 地址，等待 CDP 就绪（指数退避）。
    private func pollBrowserWebSocketURL() async throws -> URL {
        let url = URL(string: "http://127.0.0.1:\(debugPort)/json/version")!
        var delay: UInt64 = 200_000_000
        let maxDelay: UInt64 = 2_000_000_000
        for attempt in 1...15 {
            if disconnected { throw InjectorError.connectionClosed }
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { continue }
                let version = try JSONDecoder().decode(CDPVersion.self, from: data)
                guard let browserURL = URL(string: version.webSocketDebuggerUrl) else {
                    throw InjectorError.invalidURL
                }
                return browserURL
            } catch InjectorError.invalidURL {
                throw InjectorError.invalidURL
            } catch {
                // Chrome 还没就绪，继续等待
            }
            if attempt < 15 {
                try await Task.sleep(nanoseconds: delay)
                delay = min(delay * 2, maxDelay)
            }
        }
        throw InjectorError.cdpNotReady
    }

    /// 启动时同步一次当前 page target；后续新 target 由 browser WebSocket 事件驱动。
    private func pollPageTargets() async throws -> [CDPTarget] {
        let url = URL(string: "http://127.0.0.1:\(debugPort)/json")!
        if disconnected { throw InjectorError.connectionClosed }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw InjectorError.noPageTargets
        }
        return try JSONDecoder().decode([CDPTarget].self, from: data)
            .filter { $0.type == "page" }
    }

    // MARK: - Browser WebSocket 事件驱动注入

    private func listenForBrowserEvents(task: URLSessionWebSocketTask) async {
        while !disconnected {
            do {
                let data = try await receiveWebSocketMessageData(task)
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                await handleBrowserMessage(json, task: task)
            } catch {
                if !disconnected {
                    print("[Fingerprint] CDP 监听断开 port=\(debugPort): \(error.localizedDescription)")
                }
                break
            }
        }
        handleBrowserDisconnect()
    }

    private func handleBrowserMessage(_ json: [String: Any], task: URLSessionWebSocketTask) async {
        if let id = json["id"] as? Int,
           let continuation = pendingResponses.removeValue(forKey: id) {
            if let error = json["error"] as? [String: Any] {
                let message = error["message"] as? String ?? "CDP command failed"
                continuation.resume(throwing: InjectorError.cdpCommandFailed(message))
            } else {
                continuation.resume()
            }
            return
        }

        guard let method = json["method"] as? String,
              let params = json["params"] as? [String: Any] else { return }

        switch method {
        case "Target.attachedToTarget":
            guard let sessionID = params["sessionId"] as? String,
                  let targetInfo = params["targetInfo"] as? [String: Any],
                  targetInfo["type"] as? String == "page",
                  let targetID = targetInfo["targetId"] as? String else { return }
            Task {
                do {
                    try await self.injectSession(sessionID: sessionID, targetID: targetID, task: task)
                } catch {
                    self.logInjectionFailure(targetID: targetID, error: error)
                }
            }
        default:
            break
        }
    }

    private func handleBrowserDisconnect() {
        guard browserTask != nil else { return }
        closeBrowserConnection()
        if !disconnected {
            state = .idle
            scheduleReconnect()
        }
    }

    private func scheduleReconnect() {
        guard reconnectTask == nil,
              !starting,
              browserTask == nil,
              !disconnected,
              reconnectAttempts < Self.maximumReconnectAttempts else { return }

        reconnectAttempts += 1
        let delaySeconds = min(30, 1 << min(reconnectAttempts, 5))
        reconnectTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(delaySeconds) * 1_000_000_000)
            await self.runScheduledReconnect()
        }
    }

    private func runScheduledReconnect() async {
        reconnectTask = nil
        guard !disconnected, browserTask == nil else { return }
        await startInjection()
    }

    private func attachToTargetIfNeeded(_ targetID: String, task: URLSessionWebSocketTask) async throws {
        guard !injectedTargetIDs.contains(targetID),
              !attachingTargetIDs.contains(targetID),
              !disconnected else { return }
        attachingTargetIDs.insert(targetID)
        do {
            try await sendBrowserCommand(
                task: task,
                method: "Target.attachToTarget",
                params: [
                    "targetId": targetID,
                    "flatten": true
                ]
            )
        } catch {
            attachingTargetIDs.remove(targetID)
            throw error
        }
    }

    private func injectSession(sessionID: String, targetID: String, task: URLSessionWebSocketTask) async throws {
        if disconnected { throw InjectorError.connectionClosed }
        guard !injectedTargetIDs.contains(targetID) else { return }
        defer { attachingTargetIDs.remove(targetID) }

        try await sendBrowserCommand(
            task: task,
            method: "Page.addScriptToEvaluateOnNewDocument",
            params: ["source": fingerprintScript],
            sessionID: sessionID
        )
        try await sendBrowserCommand(
            task: task,
            method: "Runtime.evaluate",
            params: ["expression": fingerprintScript],
            sessionID: sessionID
        )
        injectedTargetIDs.insert(targetID)
        state = .injected
        print("[Fingerprint] 注入成功 port=\(debugPort) target=\(targetID)")
    }

    private func sendBrowserCommand(
        task: URLSessionWebSocketTask,
        method: String,
        params: [String: Any],
        sessionID: String? = nil
    ) async throws {
        if disconnected { throw InjectorError.connectionClosed }
        let id = nextCommandID
        nextCommandID += 1

        var payload: [String: Any] = ["id": id, "method": method, "params": params]
        if let sessionID {
            payload["sessionId"] = sessionID
        }
        let data = try JSONSerialization.data(withJSONObject: payload)
        let text = String(data: data, encoding: .utf8) ?? "{}"
        try await withCheckedThrowingContinuation { continuation in
            pendingResponses[id] = continuation
            Task {
                do {
                    try await task.send(.string(text))
                } catch {
                    self.finishPendingResponse(id: id, result: .failure(error))
                }
            }
            Task {
                try? await Task.sleep(nanoseconds: Self.cdpResponseTimeoutNanoseconds)
                self.finishPendingResponse(id: id, result: .failure(InjectorError.cdpResponseTimeout(id)))
            }
        }
    }

    private func finishPendingResponse(id: Int, result: Result<Void, Error>) {
        guard let continuation = pendingResponses.removeValue(forKey: id) else { return }
        switch result {
        case .success:
            continuation.resume()
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }

    private func receiveWebSocketMessageData(_ task: URLSessionWebSocketTask) async throws -> Data {
        let message = try await task.receive()
        switch message {
        case .data(let payload):
            return payload
        case .string(let text):
            return Data(text.utf8)
        @unknown default:
            throw InjectorError.connectionClosed
        }
    }

    private func closeBrowserConnection() {
        listenTask?.cancel()
        listenTask = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        browserTask?.cancel(with: .normalClosure, reason: nil)
        browserTask = nil
        for (_, continuation) in pendingResponses {
            continuation.resume(throwing: InjectorError.connectionClosed)
        }
        pendingResponses.removeAll()
    }

    private func logInjectionFailure(targetID: String, error: Error) {
        if !disconnected {
            print("[Fingerprint] 注入失败 port=\(debugPort) target=\(targetID): \(error.localizedDescription)")
        }
    }

    // MARK: - 错误定义

    enum InjectorError: LocalizedError {
        case cdpNotReady
        case invalidURL
        case noPageTargets
        case cdpCommandFailed(String)
        case cdpResponseTimeout(Int)
        case connectionClosed

        var errorDescription: String? {
            switch self {
            case .cdpNotReady: return "Chrome CDP 未就绪"
            case .invalidURL: return "无效的 WebSocket URL"
            case .noPageTargets: return "Chrome page target 未就绪"
            case .cdpCommandFailed(let message): return message
            case .cdpResponseTimeout(let id): return "等待 CDP 响应超时（command id: \(id)）"
            case .connectionClosed: return "连接已关闭"
            }
        }
    }
}
