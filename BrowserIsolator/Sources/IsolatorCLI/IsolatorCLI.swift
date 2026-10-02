import Foundation
import IsolatorCore

@main struct IsolatorCLI {
  private static let images = ImageDelivery()
  private static let outputLock = NSLock()
  static func output(_ value: J) {
    outputLock.lock()
    defer { outputLock.unlock() }
    FileHandle.standardOutput.write(Data((value.text() + "\n").utf8))
  }
  static func request(_ op: String, _ params: J, _ id: String = UUID().uuidString) -> J {
    if op == "system.capabilities" { return ["ok": true, "result": AutomationBroker.capabilities] }
    do {
      return try LocalTransport.request(["id": .str(id), "operation": .str(op), "params": params])
    } catch { return automationFailure(error) }
  }
  static func main() async {
    do {
      var args = Array(CommandLine.arguments.dropFirst())
      if args.isEmpty || args.contains("--help") {
        print(
          "isolator <profile|page|watch> <operation> --profile p1 [--tab ID] [--params JSON]\nisolator request < JSON\nisolator mcp serve [--vision]\nisolator system capabilities\nApp must be running. --launch /path/BrowserIsolator.app starts it in background.\nScreenshots return file paths. Only vision-capable models/tool chains can interpret images."
        )
        return
      }
      if let i = args.firstIndex(of: "--launch") {
        guard i + 1 < args.count else {
          throw AutomationError("missing_parameter", "--launch application path")
        }
        let path = args[i + 1]
        args.removeSubrange(i...i + 1)
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-g", path]
        try task.run()
        task.waitUntilExit()
        for _ in 0..<100 {
          if FileManager.default.fileExists(atPath: LocalTransport.socketPath) { break }
          try await Task.sleep(nanoseconds: 100_000_000)
        }
      }
      if args == ["mcp", "serve"] || args == ["mcp", "serve", "--vision"] {
        await serveMCP(vision: args.contains("--vision"))
        return
      }
      if args == ["request"] {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        guard data.count <= 1024 * 1024 else {
          throw AutomationError("message_too_large", "Request exceeds 1 MiB")
        }
        let r = try J.decode(data)
        let result = request(
          r["operation"].s, r["params"], r["id"].s.isEmpty ? UUID().uuidString : r["id"].s)
        output(result)
        if !result["ok"].b { exit(1) }
        return
      }
      guard args.count >= 2 else {
        throw AutomationError("invalid_command", "Expected group and operation")
      }
      let op = (args[0] == "profiles" ? "profile" : args[0]) + "." + args[1]
      var p: J = [:]
      var i = 2
      while i < args.count {
        let arg = args[i]
        guard arg.hasPrefix("--") else { throw AutomationError("invalid_argument", arg) }
        let bits = arg.dropFirst(2).split(separator: "-")
        let name = bits.enumerated().map {
          $0.offset == 0
            ? String($0.element) : $0.element.prefix(1).uppercased() + $0.element.dropFirst()
        }.joined()
        if name == "params" {
          guard i + 1 < args.count else { throw AutomationError("missing_parameter", arg) }
          p = try J.decode(Data(args[i + 1].utf8))
          i += 2
          continue
        }
        if i + 1 < args.count && !args[i + 1].hasPrefix("--") {
          let v = args[i + 1]
          let type = AutomationBroker.capabilities["parameterSchema"]["properties"][name]["type"].s
          if type == "integer", let n = Int(v) {
            p[name] = .int(n)
          } else if type == "boolean", v == "true" || v == "false" {
            p[name] = .bool(v == "true")
          } else if type == "array" || type == "object" {
            p[name] = try J.decode(Data(v.utf8))
          } else {
            p[name] = .str(v)
          }
          i += 2
        } else {
          p[name] = true
          i += 1
        }
      }
      if !p["output"].s.isEmpty {
        p["output"] = .str(URL(fileURLWithPath: p["output"].s).standardizedFileURL.path)
      }
      let r = request(op, p, p["requestId"].s.isEmpty ? UUID().uuidString : p["requestId"].s)
      output(r)
      if !r["ok"].b { exit(1) }
    } catch {
      output(automationFailure(error))
      exit(1)
    }
  }
  static func serveMCP(vision: Bool) async {
    await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
      DispatchQueue.global(qos: .userInitiated).async {
        let jobs = DispatchGroup()
        let slots = DispatchSemaphore(value: 32)
        while let line = readLine(strippingNewline: true) {
          slots.wait()
          jobs.enter()
          DispatchQueue.global(qos: .utility).async {
            handleMCP(line, vision: vision)
            slots.signal()
            jobs.leave()
          }
        }
        jobs.notify(queue: .global()) { done.resume() }
      }
    }
  }
  static func handleMCP(_ line: String, vision: Bool) {
    do {
      guard line.utf8.count <= 1024 * 1024 else {
        throw AutomationError("message_too_large", "MCP message exceeds 1 MiB")
      }
      let r = try J.decode(Data(line.utf8))
      if r["id"] == .null { return }
      var reply: J = ["jsonrpc": "2.0", "id": r["id"]]
      switch r["method"].s {
      case "initialize":
        let supported = ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"]
        let v = r["params"]["protocolVersion"].s
        reply["result"] = [
          "protocolVersion": .str(supported.contains(v) ? v : supported[0]),
          "capabilities": ["tools": [:]],
          "serverInfo": ["name": "BrowserIsolator", "version": "1.0"],
          "instructions": AutomationBroker.capabilities["notice"],
        ]
      case "ping": reply["result"] = [:]
      case "tools/list":
        var catalog = try J.decode(Data(AutomationResources.text("mcp-tools", ext: "json").utf8))
        if vision {
          catalog["tools"] = .array(
            catalog["tools"].a + [
              try J.decode(Data(AutomationResources.text("mcp-image-tool", ext: "json").utf8))
            ])
        }
        reply["result"] = catalog
      case "tools/call":
        let name = r["params"]["name"].s
        let arguments = r["params"]["arguments"]
        if name == "isolator_image" {
          do {
            guard vision else {
              throw AutomationError(
                "vision_disabled",
                "Start MCP with --vision only for a model/tool chain that accepts images")
            }
            reply["result"] = try images.read(arguments)
          } catch {
            let failure = automationFailure(error)
            reply["result"] = [
              "isError": true, "content": [["type": "text", "text": .str(failure.text())]],
            ]
          }
          output(reply)
          return
        }
        let catalog = try J.decode(Data(AutomationResources.text("mcp-tools", ext: "json").utf8))
        guard let tool = catalog["tools"].a.first(where: { $0["name"].s == name }),
          tool["inputSchema"]["properties"]["operation"]["enum"].a.contains(arguments["operation"])
        else {
          reply["error"] = ["code": -32602, "message": "Unknown tool or operation"]
          output(reply)
          return
        }
        let data = request(
          arguments["operation"].s, arguments["params"],
          arguments["params"]["requestId"].s.isEmpty
            ? UUID().uuidString : arguments["params"]["requestId"].s)
        if arguments["operation"].s == "page.screenshot", data["ok"].b { images.remember(data) }
        reply["result"] = [
          "content": [["type": "text", "text": .str(data.text())]], "structuredContent": data,
          "isError": .bool(!data["ok"].b),
        ]
      default: reply["error"] = ["code": -32601, "message": "Method not found"]
      }
      output(reply)
    } catch {
      output([
        "jsonrpc": "2.0", "id": nil,
        "error": ["code": -32700, "message": .str(error.localizedDescription)],
      ])
    }
  }
}
