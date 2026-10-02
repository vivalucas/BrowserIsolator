import Foundation

public actor CDPConnection {
  private let socket: URLSessionWebSocketTask
  private var receiver: Task<Void, Never>?
  private var nextID = 0
  private var pending: [Int: CheckedContinuation<J, Error>] = [:]
  private var timers: [Int: Task<Void, Never>] = [:]
  private var events: [J] = []
  private var sequence = 0
  private var eventSizes: [Int] = []
  private var eventBytes = 0
  private var closed = false
  public init(url: URL) {
    socket = URLSession.shared.webSocketTask(with: url)
    socket.maximumMessageSize = 32 * 1024 * 1024
  }
  public func connect() {
    socket.resume()
    receiver = Task { [weak self] in await self?.receiveLoop() }
  }
  public func send(
    _ method: String, _ params: J = [:], session: String? = nil, timeout: Double = 10
  ) async throws -> J {
    guard !closed else { throw AutomationError("connection_closed", "CDP connection closed") }
    nextID += 1
    let id = nextID
    var command: J = ["id": .int(id), "method": .str(method), "params": params]
    if let session { command["sessionId"] = .str(session) }
    let text = command.text()
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        pending[id] = continuation
        timers[id] = Task { [weak self] in
          do {
            try await Task.sleep(nanoseconds: UInt64(max(0.1, timeout) * 1_000_000_000))
            await self?.finish(
              id,
              .failure(
                AutomationError(
                  "timeout", "CDP response timed out; do not automatically replay actions")))
          } catch {}
        }
        Task { [weak self, socket] in
          do { try await socket.send(.string(text)) } catch {
            await self?.finish(id, .failure(error))
          }
        }
      }
    } onCancel: {
      Task { await self.finish(id, .failure(AutomationError("cancelled", "Request cancelled"))) }
    }
  }
  private func finish(_ id: Int, _ result: Result<J, Error>) {
    timers.removeValue(forKey: id)?.cancel()
    pending.removeValue(forKey: id)?.resume(with: result)
  }
  private func receiveLoop() async {
    do {
      while !Task.isCancelled {
        let message = try await socket.receive()
        let data: Data
        switch message {
        case .data(let d): data = d
        case .string(let s): data = Data(s.utf8)
        @unknown default: continue
        }
        let json = try J.decode(data)
        if json["id"].i > 0 {
          let id = json["id"].i
          if json["error"] != .null {
            finish(id, .failure(AutomationError("cdp_error", json["error"]["message"].s)))
          } else {
            finish(id, .success(json["result"]))
          }
        } else if !json["method"].s.isEmpty {
          var e = json
          sequence += 1
          e["sequence"] = .int(sequence)
          e["observedAt"] = .str(ISO8601DateFormatter().string(from: Date()))
          events.append(e)
          eventSizes.append(data.count)
          eventBytes += data.count
          while events.count > 1000 || eventBytes > 4 * 1024 * 1024 {
            events.removeFirst()
            eventBytes -= eventSizes.removeFirst()
          }
        }
      }
    } catch { awaitClose(error) }
  }
  private func awaitClose(_ error: Error) {
    closed = true
    for id in Array(pending.keys) { finish(id, .failure(error)) }
    socket.cancel(with: .goingAway, reason: nil)
  }
  public var isClosed: Bool { closed }
  public func eventCursor() -> Int { sequence }
  public func eventsSince(_ cursor: Int) -> [J] { events.filter { $0["sequence"].i > cursor } }
  public func close() {
    receiver?.cancel()
    receiver = nil
    awaitClose(AutomationError("connection_closed", "Browser connection ended"))
  }
  public func evaluate(
    _ expression: String, session: String, context: Int? = nil, timeout: Double = 10
  ) async throws -> J {
    var p: J = ["expression": .str(expression), "returnByValue": true, "awaitPromise": true]
    if let context { p["contextId"] = .int(context) }
    let r = try await send("Runtime.evaluate", p, session: session, timeout: timeout)
    if r["exceptionDetails"] != .null {
      let message = r["exceptionDetails"]["exception"]["description"].s
      let clean = message.replacingOccurrences(of: "Error: ", with: "")
      let code = clean.components(separatedBy: ":").first ?? "javascript_error"
      throw AutomationError(code, message.isEmpty ? r["exceptionDetails"]["text"].s : message)
    }
    return r["result"]["value"]
  }
}
