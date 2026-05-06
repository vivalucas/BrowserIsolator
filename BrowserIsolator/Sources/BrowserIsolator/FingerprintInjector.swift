import Foundation
import Network

/// 线程安全的一次性恢复标记，用于 withCheckedThrowingContinuation
private final class ResumptionFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false

    /// 尝试标记为已恢复。若未恢复过，执行 body 并返回 true
    func tryResume(_ body: () -> Void) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if resumed { return false }
        resumed = true
        body()
        return true
    }
}

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
    private var connection: NWConnection?

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

    /// 开始注入流程。幂等：已注入或正在注入时调用会跳过
    func startInjection() async {
        guard !injecting, state != .injected else { return }
        injecting = true
        state = .waiting
        connection?.cancel()
        connection = nil

        do {
            let wsURL = try await pollCDPReady()
            try await connectAndInject(wsURL: wsURL)
            state = .injected
            print("[Fingerprint] 注入成功 port=\(debugPort)")
        } catch {
            state = .idle
            print("[Fingerprint] 注入失败 port=\(debugPort): \(error.localizedDescription)")
        }
        injecting = false
    }

    /// 断开连接（profile 停止时调用）
    func disconnect() {
        state = .idle
        injecting = false
        connection?.cancel()
        connection = nil
    }

    // MARK: - HTTP 轮询

    /// 轮询 CDP HTTP 端点，等待 Chrome 就绪（指数退避）
    private func pollCDPReady() async throws -> String {
        let url = URL(string: "http://127.0.0.1:\(debugPort)/json")!
        var delay: UInt64 = 200_000_000 // 200ms
        let maxDelay: UInt64 = 2_000_000_000 // 2s
        for attempt in 1...15 {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { continue }
                if let wsURL = try parseWebSocketURL(from: data) {
                    return wsURL
                }
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

    /// 从 /json 响应中解析 webSocketDebuggerUrl
    private func parseWebSocketURL(from data: Data) throws -> String? {
        guard let pages = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return nil
        }
        // 优先取 Browser 类型的 target（主调试端点），否则取第一个可用的
        let browserTarget = pages.first { $0["type"] as? String == "browser" }
        let target = browserTarget ?? pages.first
        return target?["webSocketDebuggerUrl"] as? String
    }

    // MARK: - WebSocket 连接 + CDP 注入

    /// 连接 WebSocket 并发送 CDP 注入命令
    private func connectAndInject(wsURL: String) async throws {
        guard let url = URL(string: wsURL),
              let host = url.host else {
            throw InjectorError.invalidURL
        }
        let port = UInt16(url.port ?? 80)

        return try await withCheckedThrowingContinuation { continuation in
            let conn = NWConnection(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(rawValue: port)!,
                using: .tcp
            )
            self.connection = conn
            let flag = ResumptionFlag()

            conn.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    Task { [weak self] in
                        guard let self else { return }
                        do {
                            try await self.performHandshakeAndInject(conn: conn, path: url.path)
                            _ = flag.tryResume { continuation.resume() }
                        } catch {
                            conn.cancel()
                            _ = flag.tryResume { continuation.resume(throwing: error) }
                        }
                    }
                case .failed(let error):
                    _ = flag.tryResume { continuation.resume(throwing: error) }
                case .cancelled:
                    _ = flag.tryResume { continuation.resume(throwing: InjectorError.connectionClosed) }
                default:
                    break
                }
            }
            conn.start(queue: .global())
        }
    }

    /// WebSocket 握手 + 发送 CDP 命令
    private func performHandshakeAndInject(conn: NWConnection, path: String) async throws {
        // 1. 发送握手请求
        let key = generateWebSocketKey()
        let request = "GET \(path) HTTP/1.1\r\nHost: 127.0.0.1\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: \(key)\r\nSec-WebSocket-Version: 13\r\n\r\n"

        try await sendUTF(conn: conn, text: request)

        // 2. 接收握手响应
        let responseData = try await read(conn: conn, minLength: 12, maxLength: 4096)
        guard let response = String(data: responseData, encoding: .utf8),
              response.hasPrefix("HTTP/1.1 101"),
              response.lowercased().contains("upgrade: websocket") else {
            throw InjectorError.handshakeFailed
        }

        // 3. 发送 CDP 注入命令
        let command = """
        {"id":1,"method":"Page.addScriptToEvaluateOnNewDocument","params":{"source":"\(escapeJSON(fingerprintScript))"}}
        """
        let frame = encodeTextFrame(command)
        try await sendData(conn: conn, data: frame)

        // 4. 读取 CDP 确认响应（不解析，只要确认有响应）
        _ = try? await read(conn: conn, minLength: 2, maxLength: 4096)

        // 5. 连接保持不断开，Chrome 重启或连接断开时触发重连
        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                Task { [weak self] in
                    await self?.handleDisconnect()
                }
            default:
                break
            }
        }
    }

    private func handleDisconnect() {
        state = .idle
        injecting = false
        connection = nil
        print("[Fingerprint] 连接断开 port=\(debugPort)")
    }

    // MARK: - WebSocket 帧编解码

    /// 编码一个 WebSocket 文本帧（客户端帧需要 mask）
    private func encodeTextFrame(_ text: String) -> Data {
        let payload = Data(text.utf8)
        var frame = Data()

        // FIN=1, opcode=1 (text)
        frame.append(0x81)

        let len = payload.count
        if len < 126 {
            frame.append(UInt8(0x80 | len)) // mask bit set
        } else if len < 65536 {
            frame.append(UInt8(0x80 | 126))
            frame.append(UInt8((len >> 8) & 0xFF))
            frame.append(UInt8(len & 0xFF))
        } else {
            frame.append(UInt8(0x80 | 127))
            for i in stride(from: 56, through: 0, by: -8) {
                frame.append(UInt8((len >> i) & 0xFF))
            }
        }

        // Masking key
        var maskKey = UInt32.random(in: 0...UInt32.max)
        let maskBytes = withUnsafeBytes(of: &maskKey) { Data($0) }
        frame.append(maskBytes)

        // Masked payload
        let maskArray = [UInt8](maskBytes)
        for i in 0..<payload.count {
            frame.append(payload[i] ^ maskArray[i % 4])
        }

        return frame
    }

    // MARK: - TCP I/O

    private func sendData(conn: NWConnection, data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            conn.send(content: data, completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            })
        }
    }

    private func sendUTF(conn: NWConnection, text: String) async throws {
        try await sendData(conn: conn, data: Data(text.utf8))
    }

    private func read(conn: NWConnection, minLength: Int, maxLength: Int) async throws -> Data {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            conn.receive(minimumIncompleteLength: minLength, maximumLength: maxLength) { data, _, _, error in
                if let error { continuation.resume(throwing: error) }
                else if let data { continuation.resume(returning: data) }
                else { continuation.resume(throwing: InjectorError.connectionClosed) }
            }
        }
    }

    // MARK: - 工具方法

    private func generateWebSocketKey() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, 16, &bytes)
        return Data(bytes).base64EncodedString()
    }

    private func escapeJSON(_ string: String) -> String {
        var result = ""
        result.reserveCapacity(string.count)
        for char in string {
            switch char {
            case "\\": result.append("\\\\")
            case "\"": result.append("\\\"")
            case "\n": result.append("\\n")
            case "\r": result.append("\\r")
            case "\t": result.append("\\t")
            case "\u{08}": result.append("\\b")
            case "\u{0C}": result.append("\\f")
            default:
                if char.unicodeScalars.contains(where: { $0.value < 0x20 }) {
                    for scalar in char.unicodeScalars {
                        if scalar.value < 0x20 {
                            result.append("\\u\(String(format: "%04x", scalar.value))")
                        } else {
                            result.append(String(scalar))
                        }
                    }
                } else {
                    result.append(char)
                }
            }
        }
        return result
    }

    // MARK: - 错误定义

    enum InjectorError: LocalizedError {
        case cdpNotReady
        case invalidURL
        case handshakeFailed
        case connectionClosed

        var errorDescription: String? {
            switch self {
            case .cdpNotReady: return "Chrome CDP 未就绪"
            case .invalidURL: return "无效的 WebSocket URL"
            case .handshakeFailed: return "WebSocket 握手失败"
            case .connectionClosed: return "连接已关闭"
            }
        }
    }
}
