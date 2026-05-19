import Foundation

/// 通过 Chrome DevTools Protocol 注入 navigator 属性覆盖，实现各环境指纹差异化
actor FingerprintInjector {

    enum State: String {
        case idle       // 未开始
        case waiting    // 轮询等待 CDP 就绪
        case injected   // 已成功注入
    }

    private let debugPort: Int
    private let fingerprintScript: String
    private(set) var state: State = .idle
    private var injecting = false
    private var disconnected = false
    private var injectedTargetIDs: Set<String> = []
    private static let cdpResponseTimeoutNanoseconds: UInt64 = 10_000_000_000

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

    /// 同步所有 page target 的注入状态。幂等：已注入过的 target 会跳过。
    func startInjection() async {
        guard !injecting, !disconnected else { return }
        injecting = true
        state = .waiting
        defer { injecting = false }

        do {
            let targets = try await pollPageTargets()
            var injectedCount = 0
            for target in targets where !injectedTargetIDs.contains(target.id) {
                guard !disconnected else {
                    state = .idle
                    return
                }
                try await inject(target: target)
                injectedTargetIDs.insert(target.id)
                injectedCount += 1
            }
            state = .injected
            if injectedCount > 0 {
                print("[Fingerprint] 注入成功 port=\(debugPort) targets=\(injectedCount)")
            }
        } catch {
            state = .idle
            print("[Fingerprint] 注入失败 port=\(debugPort): \(error.localizedDescription)")
        }
    }

    /// 断开连接（profile 停止时调用）
    func disconnect() {
        disconnected = true
        state = .idle
        injecting = false
        injectedTargetIDs.removeAll()
    }

    // MARK: - HTTP 轮询

    private struct CDPTarget: Decodable {
        let id: String
        let type: String
        let webSocketDebuggerUrl: String?
    }

    /// 轮询 CDP HTTP 端点，等待至少一个 page target 就绪（指数退避）
    private func pollPageTargets() async throws -> [CDPTarget] {
        let url = URL(string: "http://127.0.0.1:\(debugPort)/json")!
        var delay: UInt64 = 200_000_000 // 200ms
        let maxDelay: UInt64 = 2_000_000_000 // 2s
        for attempt in 1...15 {
            if disconnected { throw InjectorError.connectionClosed }
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { continue }
                let targets = try JSONDecoder().decode([CDPTarget].self, from: data)
                    .filter { $0.type == "page" && $0.webSocketDebuggerUrl != nil }
                if !targets.isEmpty {
                    return targets
                }
            } catch {
                // Chrome 还没就绪，继续等待
            }
            if attempt < 15 {
                try await Task.sleep(nanoseconds: delay)
                delay = min(delay * 2, maxDelay)
            }
        }
        throw InjectorError.noPageTargets
    }

    // MARK: - WebSocket 连接 + CDP 注入

    private func inject(target: CDPTarget) async throws {
        if disconnected { throw InjectorError.connectionClosed }
        guard let wsURL = target.webSocketDebuggerUrl,
              let url = URL(string: wsURL) else {
            throw InjectorError.invalidURL
        }

        let task = URLSession.shared.webSocketTask(with: url)
        task.resume()
        defer { task.cancel(with: .normalClosure, reason: nil) }

        try await sendCDPCommand(
            task: task,
            id: 1,
            method: "Page.addScriptToEvaluateOnNewDocument",
            params: ["source": fingerprintScript]
        )
        try await sendCDPCommand(
            task: task,
            id: 2,
            method: "Runtime.evaluate",
            params: ["expression": fingerprintScript]
        )
    }

    private func sendCDPCommand(
        task: URLSessionWebSocketTask,
        id: Int,
        method: String,
        params: [String: Any]
    ) async throws {
        if disconnected { throw InjectorError.connectionClosed }
        let payload: [String: Any] = [
            "id": id,
            "method": method,
            "params": params
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let text = String(data: data, encoding: .utf8) ?? "{}"
        try await task.send(.string(text))
        try await waitForCDPResponse(task: task, id: id)
    }

    private func waitForCDPResponse(task: URLSessionWebSocketTask, id: Int) async throws {
        while true {
            let data = try await receiveCDPMessageData(task: task, id: id)

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  json["id"] as? Int == id else {
                continue
            }
            if let error = json["error"] as? [String: Any] {
                let message = error["message"] as? String ?? "CDP command failed"
                throw InjectorError.cdpCommandFailed(message)
            }
            return
        }
    }

    private func receiveCDPMessageData(task: URLSessionWebSocketTask, id: Int) async throws -> Data {
        try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask {
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
            group.addTask {
                try await Task.sleep(nanoseconds: Self.cdpResponseTimeoutNanoseconds)
                throw InjectorError.cdpResponseTimeout(id)
            }

            guard let data = try await group.next() else {
                throw InjectorError.cdpResponseTimeout(id)
            }
            group.cancelAll()
            return data
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
