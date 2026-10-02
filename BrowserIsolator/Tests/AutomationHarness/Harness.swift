import Foundation
import IsolatorCore

@main struct Harness {
  static func main() async throws {
    let port = Int(ProcessInfo.processInfo.environment["TEST_CDP_PORT"] ?? "0") ?? 0
    let broker = AutomationBroker { op, p in
      if op == "profile.list" {
        let count = Int(ProcessInfo.processInfo.environment["TEST_PROFILE_COUNT"] ?? "1") ?? 1
        let offset = p["offset"].i
        let limit = p["limit"].i == 0 ? 40 : p["limit"].i
        let rows = (0..<count).map { index -> J in
          [
            "profile": .str(index == 0 ? "test" : "dummy\(index)"),
            "name": .str(String(repeating: "Fixture environment ", count: 8)), "running": true,
            "port": .int(port), "generation": "test-generation",
          ]
        }
        let selected = Array(rows.dropFirst(offset).prefix(limit))
        return [
          "profiles": .array(selected), "total": .int(count), "offset": .int(offset),
          "nextOffset": offset + selected.count < count ? .int(offset + selected.count) : nil,
        ]
      }
      guard p["profile"].s == "test" else { throw AutomationError("profile_not_found", "test") }
      return ["profile": "test", "port": .int(port), "generation": "test-generation"]
    }
    let server = AutomationServer { r in await broker.handle(r) }
    try server.start()
    while let line = readLine() {
      do {
        let r = try J.decode(Data(line.utf8))
        let reply = await broker.handle(r)
        print(reply.text())
        fflush(stdout)
      } catch {
        print(automationFailure(error).text())
        fflush(stdout)
      }
    }
    server.stop()
    await broker.shutdown()
  }
}
