import Foundation

public actor BrowserAutomation {
  private struct Frame: Sendable {
    let id: String
    let session: String
    let context: Int
    let index: Int
  }
  private struct Snapshot: Sendable {
    let generation: String
    let profile: String
    let tab: String
    let frames: [Frame]
    let time: Date
    var data: J
  }
  private struct Watch: Sendable {
    let generation: String
    let profile: String
    let tab: String
    var params: J
    let start: Date
    let deadline: Date
    var before: J
    var latest: J
    var events: [J]
    var state: String
    var reason: String
    var matched: Bool
    var cursor: Int
    var dropped: Int
    var finalResult: J = .null
    var historyBytes: Int = 0
  }
  private var profileGenerations: [String: String] = [:]
  private var sessions: [String: String] = [:]
  private var connecting: [String: Task<CDPConnection, Error>] = [:]
  private var attaching: [String: Task<String, Error>] = [:]
  private var connections: [String: CDPConnection] = [:]
  private var snapshots: [String: Snapshot] = [:]
  private var watches: [String: Watch] = [:]
  private var pendingWatches = 0
  private var watchTasks: [String: Task<Void, Never>] = [:]
  private var busy: Set<String> = []
  private let script = AutomationResources.text("page-agent", ext: "js")
  public init() {}
  private func now() -> String { ISO8601DateFormatter().string(from: Date()) }
  private func prune() {
    snapshots = snapshots.filter { Date().timeIntervalSince($0.value.time) < 600 }
    while snapshots.count > 16 {
      if let first = snapshots.min(by: { $0.value.time < $1.value.time }) {
        snapshots.removeValue(forKey: first.key)
      }
    }
    for (id, var w) in watches where w.state != "running" {
      compactWatch(id, &w)
      watches[id] = w
      if Date().timeIntervalSince(w.start) > 600 { watches.removeValue(forKey: id) }
    }
    var history = watches.filter { $0.value.state != "running" }.sorted {
      $0.value.start < $1.value.start
    }
    var bytes = history.reduce(0) { $0 + $1.value.historyBytes }
    while history.count > 16 || bytes > 2 * 1024 * 1024 {
      let oldest = history.removeFirst()
      bytes -= oldest.value.historyBytes
      watches.removeValue(forKey: oldest.key)
    }
  }
  private func http(_ path: String, port: Int) async throws -> J {
    guard (1...65535).contains(port), let url = URL(string: "http://127.0.0.1:\(port)/\(path)")
    else { throw AutomationError("cdp_unavailable", "No verified local debugging endpoint") }
    var r = URLRequest(url: url)
    r.timeoutInterval = 3
    let (data, response) = try await URLSession.shared.data(for: r)
    guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 32 * 1024 * 1024 else {
      throw AutomationError("cdp_unavailable", "CDP endpoint did not return a valid response")
    }
    return try J.decode(data)
  }
  private func connection(_ info: J) async throws -> CDPConnection {
    let key = info["generation"].s
    let profile = info["profile"].s
    if let previous = profileGenerations[profile], previous != key { await invalidate(profile) }
    profileGenerations[profile] = key
    guard connections.count < 32 || connections[key] != nil else {
      throw AutomationError("resource_limit", "At most 32 browser connections")
    }
    if let c = connections[key] {
      if !(await c.isClosed) { return c }
      await invalidate(profile, reason: "connection_lost")
      profileGenerations[profile] = key
    }
    if let task = connecting[key] { return try await task.value }
    let task = Task {
      let version = try await self.http("json/version", port: info["port"].i)
      guard let u = URL(string: version["webSocketDebuggerUrl"].s), u.scheme == "ws",
        ["127.0.0.1", "localhost", "::1"].contains(u.host ?? ""), u.port == info["port"].i
      else {
        throw AutomationError(
          "invalid_endpoint", "Browser WebSocket must belong to verified local port")
      }
      let c = CDPConnection(url: u)
      await c.connect()
      _ = try await c.send("Target.setDiscoverTargets", ["discover": true])
      return c
    }
    connecting[key] = task
    defer { connecting.removeValue(forKey: key) }
    let c = try await task.value
    connections[key] = c
    return c
  }
  private func attach(_ key: String, target: String, connection c: CDPConnection) async throws
    -> String
  {
    if let s = sessions[key] { return s }
    if let task = attaching[key] { return try await task.value }
    let task = Task {
      try await c.send("Target.attachToTarget", ["targetId": .str(target), "flatten": true])[
        "sessionId"
      ].s
    }
    attaching[key] = task
    defer { attaching.removeValue(forKey: key) }
    let s = try await task.value
    sessions[key] = s
    return s
  }

  private func tab(_ p: J, info: J) async throws -> J {
    let id = p["tab"].s
    guard !id.isEmpty else {
      throw AutomationError("tab_required", "Select an explicit tab from page list or page open")
    }
    let tabs = try await http("json/list", port: info["port"].i)
    guard let t = tabs.a.first(where: { $0["id"].s == id && $0["type"].s == "page" }) else {
      throw AutomationError("page_closed", "Selected tab no longer exists")
    }
    return t
  }
  private func frames(_ p: J, info: J) async throws -> (CDPConnection, [Frame], [J]) {
    _ = try await tab(p, info: info)
    let c = try await connection(info)
    let key = info["generation"].s + ":" + p["tab"].s
    let session = try await attach(key, target: p["tab"].s, connection: c)
    let tree = try await c.send("Page.getFrameTree", session: session)
    var ids: [String] = []
    func collect(_ t: J) {
      ids.append(t["frame"]["id"].s)
      for child in t["childFrames"].a { collect(child) }
    }
    collect(tree["frameTree"])
    // Page.getFrameTree omits out-of-process children. Verify their frame owner
    // against this tab before attaching; never collect another tab's frame.
    let targets = try await c.send("Target.getTargets")
    for target in targets["targetInfos"].a
    where target["type"].s == "iframe" && !ids.contains(target["targetId"].s) {
      if (try? await c.send("DOM.getFrameOwner", ["frameId": target["targetId"]], session: session))
        != nil
      {
        ids.append(target["targetId"].s)
      }
    }
    var out: [Frame] = []
    var gaps: [J] = []
    var owners: [String: String] = [:]
    var index = -1
    while index + 1 < ids.count {
      index += 1
      let id = ids[index]
      if id.isEmpty { continue }
      if index >= 64 {
        gaps.append(["reason": "frame_limit"])
        break
      }
      var frameSession = owners[id] ?? session
      do {
        var world: J
        do {
          world = try await c.send(
            "Page.createIsolatedWorld", ["frameId": .str(id), "worldName": "IsolatorAutomation"],
            session: frameSession)
        } catch {
          frameSession = try await attach(key + ":" + id, target: id, connection: c)
          world = try await c.send(
            "Page.createIsolatedWorld", ["frameId": .str(id), "worldName": "IsolatorAutomation"],
            session: frameSession)
        }
        let f = Frame(
          id: id, session: frameSession, context: world["executionContextId"].i, index: index)
        _ = try await c.evaluate(script, session: f.session, context: f.context)
        _ = try? await c.send("Page.enable", session: f.session)
        _ = try? await c.send("Runtime.enable", session: f.session)
        _ = try? await c.send(
          "Network.enable", ["maxTotalBufferSize": 1_048_576, "maxResourceBufferSize": 262144],
          session: f.session)
        out.append(f)
        if let subtree = try? await c.send("Page.getFrameTree", session: f.session) {
          func add(_ t: J) {
            let child = t["frame"]["id"].s
            if !child.isEmpty && !ids.contains(child) {
              ids.append(child)
              owners[child] = f.session
            }
            for c in t["childFrames"].a { add(c) }
          }
          add(subtree["frameTree"])
        }
        for target in targets["targetInfos"].a
        where target["type"].s == "iframe" && !ids.contains(target["targetId"].s) {
          if (try? await c.send(
            "DOM.getFrameOwner", ["frameId": target["targetId"]], session: f.session)) != nil
          {
            ids.append(target["targetId"].s)
            owners[target["targetId"].s] = f.session
          }
        }
      } catch { gaps.append(["frame": .str(id), "reason": .str(error.localizedDescription)]) }
    }
    guard !out.isEmpty else {
      throw AutomationError("frame_unavailable", "No readable document in selected tab")
    }
    return (c, out, gaps)
  }
  private func call(_ method: String, _ p: J, frame: Frame, connection: CDPConnection) async throws
    -> J
  {
    try await connection.evaluate(
      "globalThis.__isolator_page_agent_v1.\(method)(\(p.text()))", session: frame.session,
      context: frame.context)
  }
  private func capture(_ p: J, info: J) async throws -> J {
    prune()
    let id = "s-" + UUID().uuidString.lowercased()
    let (c, fs, initialGaps) = try await frames(p, info: info)
    var nodes: [J] = []
    var gaps = initialGaps
    var metadata: J = [:]
    var collected: [Frame] = []
    var frameInfo: [J] = []
    var remainingNodes = min(max(p["maxNodes"].i == 0 ? 20000 : p["maxNodes"].i, 1), 100000)
    var remainingBytes = min(
      max(p["maxCaptureBytes"].i == 0 ? 8 * 1024 * 1024 : p["maxCaptureBytes"].i, 1024),
      32 * 1024 * 1024)
    for f in fs {
      guard remainingNodes > 0 && remainingBytes > 1024 else {
        gaps.append(["frame": .str(f.id), "reason": "capture_limit"])
        continue
      }
      do {
        let r = try await call(
          "capture",
          [
            "token": .str(id), "maxNodes": .int(remainingNodes),
            "maxCaptureBytes": .int(remainingBytes),
          ], frame: f, connection: c)
        if f.index == 0 {
          metadata = r
          metadata["nodes"] = nil
        }
        collected.append(f)
        frameInfo.append([
          "id": .str(f.id), "index": .int(f.index), "url": r["url"], "title": r["title"],
        ])
        for raw in r["nodes"].a {
          var n = raw
          n["ref"] = .str("f\(f.index):" + raw["ref"].s)
          if raw["parent"] != .null { n["parent"] = .str("f\(f.index):" + raw["parent"].s) }
          n["frameId"] = .str(f.id)
          nodes.append(n)
        }
        remainingNodes -= r["nodes"].a.count
        remainingBytes -= (try? r.data().count) ?? remainingBytes
        if !r["captureComplete"].b {
          gaps.append(["frame": .str(f.id), "reason": "capture_limit"])
        }
      } catch { gaps.append(["frame": .str(f.id), "reason": .str(error.localizedDescription)]) }
    }
    metadata["snapshot"] = .str(id)
    metadata["nodes"] = .array(nodes)
    metadata["frames"] = .array(frameInfo)
    metadata["gaps"] = .array(gaps)
    metadata["captureComplete"] = .bool(gaps.isEmpty)
    metadata["totalNodes"] = .int(nodes.count)
    metadata["consistency"] = "best_effort"
    metadata["coverage"] = [
      "dom": "elements_and_text", "shadow": "open_roots; closed_roots_in_raw_capture_only",
      "canvas": "bitmap_requires_screenshot", "virtualized": "currently_loaded_DOM_only",
      "accessibility": "semantic_approximation_not_full_AX_tree",
    ]
    metadata["generation"] = info["generation"]
    metadata["profile"] = info["profile"]
    metadata["tab"] = p["tab"]
    snapshots[id] = Snapshot(
      generation: info["generation"].s, profile: info["profile"].s, tab: p["tab"].s,
      frames: collected, time: Date(), data: metadata)
    return metadata
  }
  private func snapshot(_ p: J, info: J) throws -> Snapshot {
    prune()
    guard let s = snapshots[p["snapshot"].s] else {
      throw AutomationError("snapshot_expired", "Capture a fresh snapshot")
    }
    guard s.generation == info["generation"].s, s.profile == info["profile"].s, s.tab == p["tab"].s
    else {
      throw AutomationError(
        "stale_reference", "Snapshot belongs to a different browser instance or tab")
    }
    return s
  }
  private func project(_ raw: J, _ p: J) -> J {
    var result = raw
    var nodes = raw["nodes"].a
    if !p["root"].s.isEmpty {
      var refs: Set<String> = [p["root"].s]
      for n in nodes where refs.contains(n["parent"].s) { refs.insert(n["ref"].s) }
      nodes = nodes.filter { refs.contains($0["ref"].s) }
    }
    if !p["query"].s.isEmpty {
      let q = p["query"].s.lowercased()
      nodes = nodes.filter { $0.text().lowercased().contains(q) }
    }
    if !p["includeHidden"].b { nodes = nodes.filter { $0["visible"].b } }
    let view = p["view"].s.isEmpty ? "summary" : p["view"].s
    if view == "text" {
      nodes = nodes.filter { $0["type"].s == "text" }
    } else if view == "summary" {
      nodes = nodes.filter {
        $0["type"].s == "text" || $0["role"].s != "generic" || !$0["attributes"]["id"].s.isEmpty
          || !$0["attributes"]["data-testid"].s.isEmpty
      }
    }
    let offset = min(max(0, p["offset"].i), nodes.count)
    let count = min(max(p["limit"].i == 0 ? 40 : p["limit"].i, 1), 500)
    let fields =
      p["fields"].s.isEmpty
      ? (view == "full"
        ? []
        : [
          "ref", "parent", "frameId", "tag", "role", "name", "text", "visible", "disabled", "value",
          "checked", "expanded",
        ]) : p["fields"].s.components(separatedBy: ",")
    var page: [J] = []
    let totalBudget = min(max(p["maxChars"].i == 0 ? 6000 : p["maxChars"].i, 512), 100000)
    var head = raw
    head["nodes"] = []
    let budget = max(0, totalBudget - head.text().count - 350)
    for node in nodes.dropFirst(offset).prefix(count) {
      let n = fields.isEmpty ? node : .object(node.o.filter { fields.contains($0.key) })
      if n.text().count + page.reduce(0, { $0 + $1.text().count }) > budget { break }
      page.append(n)
    }
    result["nodes"] = .array(page)
    result["total"] = .int(nodes.count)
    result["offset"] = .int(offset)
    result["nextOffset"] = offset + page.count < nodes.count ? .int(offset + page.count) : nil
    result["responseTruncated"] = .bool(offset + page.count < nodes.count)
    result["view"] = .str(view)
    if page.isEmpty && offset < nodes.count {
      result["nextOffset"] = .int(offset)
      result["hint"] =
        "Node exceeds output budget; select fields, increase maxChars or export the complete capture"
    }
    return result
  }
  private func location(_ p: J, info: J) async throws -> (CDPConnection, Frame, J) {
    if !p["ref"].s.isEmpty {
      let active = try await connection(info)
      let s = try snapshot(p, info: info)
      let parts = p["ref"].s.split(separator: ":", maxSplits: 1)
      guard parts.count == 2, let index = Int(parts[0].dropFirst()),
        let f = s.frames.first(where: { $0.index == index })
      else { throw AutomationError("element_not_found", "Invalid frame reference") }
      var adjusted = p
      adjusted["ref"] = .str(String(parts[1]))
      return (active, f, adjusted)
    }
    let (c, fs, _) = try await frames(p, info: info)
    if !p["frame"].s.isEmpty {
      guard let f = fs.first(where: { $0.id == p["frame"].s }) else {
        throw AutomationError("frame_unavailable", "Frame is not readable")
      }
      return (c, f, p)
    }
    guard let f = fs.first(where: { $0.index == 0 }) else {
      throw AutomationError("frame_unavailable", "Root frame is unavailable")
    }
    return (c, f, p)
  }
  private func diff(_ before: J, _ after: J) -> J {
    let fields = [
      "frameId", "tag", "role", "name", "text", "visible", "disabled", "checked", "expanded",
      "value",
    ]
    let a = before["nodes"].a.map { J.object($0.o.filter { fields.contains($0.key) }) }
    let b = after["nodes"].a.map { J.object($0.o.filter { fields.contains($0.key) }) }
    var changes: [J] = []
    var total = 0
    for i in 0..<max(a.count, b.count) {
      let x = i < a.count ? a[i] : .null
      let y = i < b.count ? b[i] : .null
      if x != y {
        total += 1
        if changes.count < 30 {
          changes.append([
            "kind": x == .null ? "added" : y == .null ? "removed" : "changed", "before": x,
            "after": y,
          ])
        }
      }
    }
    return [
      "beforeSnapshot": before["snapshot"], "afterSnapshot": after["snapshot"],
      "urlChanged": .bool(before["url"] != after["url"]), "url": after["url"],
      "changes": .array(changes), "totalChanges": .int(total),
      "truncated": .bool(total > changes.count), "comparison": "ordered_structure",
      "causality": "observed_after_action_not_proven",
    ]
  }
  private func check(_ p: J, info: J) async throws -> Bool {
    if !p["urlContains"].s.isEmpty {
      return (try await tab(p, info: info))["url"].s.contains(p["urlContains"].s)
    }
    let (c, f, q) = try await location(p, info: info)
    return try await call("condition", q, frame: f, connection: c)["matched"].b
  }
  private func action(_ op: String, _ p: J, info: J) async throws -> J {
    let (c, f, q) = try await location(p, info: info)
    if op == "page.evaluate" {
      guard !p["expression"].s.isEmpty else {
        throw AutomationError("expression_required", "Provide an explicit JavaScript expression")
      }
      return [
        "value": try await c.evaluate(
          p["expression"].s, session: f.session, context: f.context, timeout: 10),
        "mayModifyPage": true,
      ]
    }
    if op == "page.scroll" {
      let x = p["x"].i
      let y = p["y"] == .null ? 600 : p["y"].i
      return [
        "value": try await c.evaluate(
          "scrollBy({left:\(x),top:\(y),behavior:'instant'}); ({x:scrollX,y:scrollY})",
          session: f.session, context: f.context)
      ]
    }
    if op == "page.select" {
      var v = q
      v["action"] = "select"
      return try await call("action", v, frame: f, connection: c)
    }
    if op == "page.upload" {
      let resolved = try await call("resolve", q, frame: f, connection: c)
      guard resolved["tag"].s == "INPUT" else {
        throw AutomationError("invalid_element", "Upload requires a file input")
      }
      let object = try await c.send(
        "Runtime.evaluate",
        [
          "expression": .str(
            "(() => { const p=\(q.text()); const s=globalThis.__isolator_page_agent_v1; return s.element(p); })()"
          ), "contextId": .int(f.context),
        ], session: f.session)
      let paths =
        p["files"].a.isEmpty ? p["files"].s.components(separatedBy: ",").map(J.str) : p["files"].a
      guard !paths.isEmpty,
        paths.allSatisfy({ $0.s.hasPrefix("/") && FileManager.default.fileExists(atPath: $0.s) })
      else {
        throw AutomationError(
          "file_not_found", "Upload files must be existing absolute local paths")
      }
      _ = try await c.send(
        "DOM.setFileInputFiles",
        ["files": .array(paths), "objectId": object["result"]["objectId"]], session: f.session)
      return ["performed": true]
    }
    if op == "page.key" {
      if !q["ref"].s.isEmpty || !q["selector"].s.isEmpty || !q["role"].s.isEmpty
        || !q["name"].s.isEmpty
      {
        var target = q
        target["focus"] = true
        _ = try await call("prepare", target, frame: f, connection: c)
      }
      let key = p["key"].s
      let supported: [String: (String, Int)] = [
        "Enter": ("\r", 13), "Tab": ("", 9), "Escape": ("", 27), "Backspace": ("", 8),
        "ArrowDown": ("", 40), "ArrowUp": ("", 38), "ArrowLeft": ("", 37), "ArrowRight": ("", 39),
        "Space": (" ", 32),
      ]
      guard let (text, code) = supported[key] else {
        throw AutomationError(
          "invalid_key", "Supported keys: Enter, Tab, Escape, Backspace, Arrow*, Space")
      }
      _ = try await c.send(
        "Input.dispatchKeyEvent",
        [
          "type": "keyDown", "key": .str(key), "text": .str(text),
          "windowsVirtualKeyCode": .int(code),
        ], session: f.session)
      _ = try await c.send(
        "Input.dispatchKeyEvent",
        ["type": "keyUp", "key": .str(key), "windowsVirtualKeyCode": .int(code)], session: f.session
      )
      return ["performed": true]
    }
    var prep = q
    prep["focus"] = .bool(op == "page.fill")
    prep["editable"] = .bool(op == "page.fill")
    let point = try await call("prepare", prep, frame: f, connection: c)
    let object = try await c.send(
      "Runtime.evaluate",
      [
        "expression": .str("globalThis.__isolator_page_agent_v1.element(\(q.text()))"),
        "contextId": .int(f.context),
      ], session: f.session)
    let quads = try await c.send(
      "DOM.getContentQuads", ["objectId": object["result"]["objectId"]], session: f.session)
    guard let quad = quads["quads"].a.first, quad.a.count == 8 else {
      throw AutomationError("element_not_visible", "No element content quad")
    }
    let px = (quad.a[0].i + quad.a[2].i + quad.a[4].i + quad.a[6].i) / 4
    let py = (quad.a[1].i + quad.a[3].i + quad.a[5].i + quad.a[7].i) / 4
    if op == "page.fill" {
      var clear = q
      clear["action"] = "clear"
      _ = try await call("action", clear, frame: f, connection: c)
      _ = try await c.send("Input.insertText", ["text": p["value"]], session: f.session)
      _ = try await call("verifyFill", q, frame: f, connection: c)
    } else {
      if op == "page.check" {
        guard point["inputType"].s == "checkbox" || point["inputType"].s == "radio" else {
          throw AutomationError("invalid_element", "Check requires checkbox or radio")
        }
        if point["inputType"].s == "radio" && point["checked"].b && !p["checked"].b {
          throw AutomationError(
            "unsupported_state",
            "Select another radio in the group; a radio cannot be unchecked by clicking")
        }
        if point["checked"].b == p["checked"].b {
          return ["performed": false, "alreadySatisfied": true]
        }
      }
      let pos: J = ["x": .int(px), "y": .int(py)]
      _ = try await c.send(
        "Input.dispatchMouseEvent",
        .object(pos.o.merging(["type": "mouseMoved"], uniquingKeysWith: { $1 })), session: f.session
      )
      if op != "page.hover" {
        for type in ["mousePressed", "mouseReleased"] {
          var click = pos
          click["type"] = .str(type)
          click["button"] = "left"
          click["clickCount"] = 1
          _ = try await c.send("Input.dispatchMouseEvent", click, session: f.session)
        }
      }
    }
    return ["performed": true, "actionDispatched": true]
  }
  public func execute(_ op: String, params p: J, info: J) async throws -> J {
    prune()
    if op == "page.list" {
      let tabs = try await http("json/list", port: info["port"].i).a.filter {
        $0["type"].s == "page"
      }
      let offset = min(max(0, p["offset"].i), tabs.count)
      let limit = min(max(p["limit"].i == 0 ? 40 : p["limit"].i, 1), 500)
      let selected = Array(tabs.dropFirst(offset).prefix(limit))
      return [
        "tabs": .array(selected.map { ["id": $0["id"], "url": $0["url"], "title": $0["title"]] }),
        "generation": info["generation"], "total": .int(tabs.count), "offset": .int(offset),
        "nextOffset": offset + selected.count < tabs.count ? .int(offset + selected.count) : nil,
      ]
    }
    let c = try await connection(info)
    if op == "page.open" {
      guard let u = URL(string: p["url"].s),
        ["http", "https"].contains(u.scheme?.lowercased() ?? ""), u.host != nil
      else { throw AutomationError("invalid_url", "Only absolute http/https URLs are accepted") }
      let r = try await c.send("Target.createTarget", ["url": p["url"], "background": true])
      return ["tab": r["targetId"], "generation": info["generation"]]
    }
    if op == "watch.get" || op == "watch.cancel" {
      guard var w = watches[p["watch"].s], w.generation == info["generation"].s else {
        throw AutomationError("watch_expired", "Watch does not exist for this browser instance")
      }
      if op == "watch.cancel" && w.state == "running" {
        watchTasks.removeValue(forKey: p["watch"].s)?.cancel()
        w.state = "cancelled"
        w.reason = "cancelled"
        compactWatch(p["watch"].s, &w)
        watches[p["watch"].s] = w
        prune()
      }
      return watchResult(p["watch"].s, w)
    }
    _ = try await tab(p, info: info)
    if op == "page.snapshot" { return project(try await capture(p, info: info), p) }
    if op == "page.expand" || op == "page.search" || op == "page.text" {
      var q = p
      if op == "page.text" { q["view"] = "text" }
      let raw =
        p["snapshot"].s.isEmpty
        ? try await capture(p, info: info) : try snapshot(p, info: info).data
      return project(raw, q)
    }
    if op == "page.inspect" {
      if !p["ref"].s.isEmpty && !p["live"].b {
        let s = try snapshot(p, info: info)
        guard let n = s.data["nodes"].a.first(where: { $0["ref"] == p["ref"] }) else {
          throw AutomationError("element_not_found", "Unknown reference")
        }
        return n
      }
      let (c, f, q) = try await location(p, info: info)
      return try await call("inspect", q, frame: f, connection: c)
    }
    if op == "page.capture" {
      let raw = try await capture(p, info: info)
      let (c, fs, gaps) = try await frames(p, info: info)
      var documents: [J] = []
      var errors = gaps
      var remaining = min(
        max(p["maxCaptureBytes"].i == 0 ? 32 * 1024 * 1024 : p["maxCaptureBytes"].i, 1024),
        32 * 1024 * 1024)
      for f in fs {
        if remaining <= 1024 {
          errors.append(["frame": .str(f.id), "reason": "raw_capture_limit"])
          continue
        }
        do {
          let data = try await c.send(
            "DOMSnapshot.captureSnapshot",
            ["computedStyles": .array(p["styles"].a), "includeDOMRects": true], session: f.session)
          let document: J = [
            "frame": .str(f.id), "data": data,
            "accessibility": try await c.send(
              "Accessibility.getFullAXTree", ["frameId": .str(f.id)], session: f.session),
          ]
          let bytes = try document.data().count
          if bytes > remaining {
            errors.append(["frame": .str(f.id), "reason": "raw_capture_limit"])
          } else {
            documents.append(document)
            remaining -= bytes
          }
        } catch {
          errors.append(["frame": .str(f.id), "reason": .str(error.localizedDescription)])
        }
      }
      var complete = raw
      complete["rawDocuments"] = .array(documents)
      complete["rawGaps"] = .array(errors)
      complete["captureComplete"] = .bool(raw["captureComplete"].b && errors.isEmpty)
      return try writeArtifact(
        complete.data(), p: p, name: "capture.json",
        metadata: [
          "snapshot": raw["snapshot"], "captureComplete": complete["captureComplete"],
          "gaps": .array(errors),
        ])
    }
    if op == "page.screenshot" { return try await screenshot(p, info: info) }
    if op == "watch.start" || op == "page.wait" {
      let id = try await startWatch(p, info: info)
      if op == "watch.start" { return watchResult(id, watches[id]!) }
      while watches[id]?.state == "running" { try await Task.sleep(nanoseconds: 100_000_000) }
      return watchResult(id, watches[id]!)
    }
    let key = info["generation"].s + ":" + p["tab"].s
    guard !busy.contains(key) else {
      throw AutomationError("page_busy", "Another tool operation is changing this tab")
    }
    busy.insert(key)
    defer { busy.remove(key) }
    if op == "page.close" {
      sessions = sessions.filter { !($0.key == key || $0.key.hasPrefix(key + ":")) }
      return try await c.send("Target.closeTarget", ["targetId": p["tab"]])
    }
    if op == "page.navigate" {
      guard let u = URL(string: p["url"].s), ["http", "https"].contains(u.scheme ?? ""),
        u.host != nil
      else {
        throw AutomationError("invalid_url", "Only http/https URLs are accepted")
      }
      let id = p["observe"].b ? try await startWatch(p, info: info) : nil
      let (_, fs, _) = try await frames(p, info: info)
      var result = try await c.send("Page.navigate", ["url": p["url"]], session: fs[0].session)
      if let id {
        while watches[id]?.state == "running" { try await Task.sleep(nanoseconds: 100_000_000) }
        result["observation"] = watchResult(id, watches[id]!)
      }
      return result
    }
    if op == "diagnostics.get" {
      let (_, observedFrames, _) = try await frames(p, info: info)
      let events = await c.eventsSince(0)
      return [
        "events": .array(
          events.filter { event in
            let method = event["method"].s
            return observedFrames.contains(where: { $0.session == event["sessionId"].s })
              && (method.hasPrefix("Network.") || method == "Runtime.consoleAPICalled"
                || method == "Runtime.exceptionThrown")
          }.suffix(100).map(safeEvent)), "scope": "events_observed_after_target_subscription",
        "requestBodiesIncluded": false,
      ]
    }
    guard
      [
        "page.click", "page.fill", "page.hover", "page.key", "page.select", "page.check",
        "page.scroll", "page.upload", "page.evaluate",
      ].contains(op)
    else { throw AutomationError("unknown_operation", "Unknown operation: \(op)") }
    let watchID = p["observe"].b ? try await startWatch(p, info: info) : nil
    let dispatched: J
    do { dispatched = try await action(op, p, info: info) } catch {
      if let id = watchID {
        watchTasks[id]?.cancel()
        watches[id]?.state = "failed"
        watches[id]?.reason = "action_failed"
      }
      throw error
    }
    var result = dispatched
    if let id = watchID {
      while watches[id]?.state == "running" { try await Task.sleep(nanoseconds: 100_000_000) }
      result["observation"] = watchResult(id, watches[id]!)
    }
    return result
  }
  private func startWatch(_ p: J, info: J) async throws -> String {
    guard watches.values.filter({ $0.state == "running" }).count + pendingWatches < 8 else {
      throw AutomationError("resource_limit", "At most eight watches may run")
    }
    pendingWatches += 1
    defer { pendingWatches -= 1 }
    let id = "w-" + UUID().uuidString.lowercased()
    let before = try await capture(p, info: info)
    let (c, fs, _) = try await frames(p, info: info)
    let duration = min(
      max(p["timeout"].i == 0 ? (p["observe"].b ? 5 : 30) : p["timeout"].i, 1), 300)
    var observerGaps: [J] = []
    for f in fs {
      do {
        _ = try await call(
          "watchStart", ["watch": .str(id), "durationMs": .int(duration * 1000)], frame: f,
          connection: c)
      } catch {
        observerGaps.append([
          "kind": "observer_gap", "frame": .str(f.id), "reason": .str(error.localizedDescription),
        ])
      }
    }
    let cursor = await c.eventCursor()
    watches[id] = Watch(
      generation: info["generation"].s, profile: info["profile"].s, tab: p["tab"].s, params: p,
      start: Date(), deadline: Date().addingTimeInterval(Double(duration)), before: before,
      latest: before, events: observerGaps, state: "running", reason: "", matched: false,
      cursor: cursor,
      dropped: observerGaps.count)
    watchTasks[id] = Task { [weak self] in
      await self?.runWatch(id, info: info, frames: fs, connection: c)
    }
    return id
  }
  private func runWatch(_ id: String, info: J, frames fs: [Frame], connection c: CDPConnection)
    async
  {
    var lastChange = Date()
    var last: J = watches[id]?.before ?? [:]
    while !Task.isCancelled, var w = watches[id], w.state == "running" {
      do {
        try await Task.sleep(nanoseconds: 250_000_000)
        for f in fs {
          if let poll = try? await call("watchPoll", ["watch": .str(id)], frame: f, connection: c) {
            w.events.append(contentsOf: poll["events"].a)
            if poll["dropped"].b { w.events.append(["kind": "event_limit"]) }
          }
        }
        let observed = await c.eventsSince(w.cursor)
        if let first = observed.first, first["sequence"].i > w.cursor + 1 {
          w.dropped += first["sequence"].i - w.cursor - 1
        }
        if let latest = observed.last { w.cursor = latest["sequence"].i }
        w.events.append(
          contentsOf: observed.filter {
            fs.map(\.session).contains($0["sessionId"].s)
              || ($0["method"].s == "Target.targetCreated"
                && $0["params"]["targetInfo"]["openerId"].s == w.tab)
          }.map(safeEvent))
        if w.events.count > 200 {
          w.dropped += w.events.count - 200
          w.events = Array(w.events.suffix(200))
        }
        var eventBytes = w.events.reduce(0) { $0 + $1.text().utf8.count }
        while eventBytes > 2 * 1024 * 1024, !w.events.isEmpty {
          eventBytes -= w.events.removeFirst().text().utf8.count
          w.dropped += 1
        }
        let previous = w.latest["snapshot"].s
        w.latest = try await capture(w.params, info: info)
        if previous != w.before["snapshot"].s, let stale = snapshots.removeValue(forKey: previous) {
          for frame in stale.frames {
            _ = try? await call("forget", ["snapshot": .str(previous)], frame: frame, connection: c)
          }
        }
        if diff(last, w.latest)["totalChanges"].i > 0 || last["url"] != w.latest["url"] {
          lastChange = Date()
        }
        last = w.latest
        let condition = w.params["until"] == .null ? w.params : w.params["until"]
        var conditionParams: J =
          w.params["until"] == .null
          ? w.params
          : .object(
            w.params.o.filter { ["profile", "tab", "frame", "generation"].contains($0.key) })
        for (k, v) in condition.o { conditionParams[k] = v }
        let hasCondition =
          !condition["selector"].s.isEmpty || !condition["role"].s.isEmpty
          || !condition["ref"].s.isEmpty || !condition["name"].s.isEmpty
          || !condition["urlContains"].s.isEmpty
        if hasCondition && (!w.params["observe"].b || w.params["until"] != .null) {
          w.matched = try await check(conditionParams, info: info)
          if w.matched {
            w.state = "completed"
            w.reason = "condition_met"
          }
        } else if w.params["observe"].b && Date().timeIntervalSince(w.start) > 0.75
          && Date().timeIntervalSince(lastChange) > 0.5
        {
          w.state = "completed"
          w.reason = "quiet_window_business_completion_unverified"
        }
        if Date() >= w.deadline && w.state == "running" {
          w.state = "completed"
          w.reason = "timeout"
        }
        if watches[id]?.state == "running" {
          compactWatch(id, &w)
          watches[id] = w
          prune()
        }
      } catch {
        w.state = "failed"
        w.reason = error.localizedDescription
        if watches[id]?.state == "running" {
          compactWatch(id, &w)
          watches[id] = w
          prune()
        }
        break
      }
    }
    for f in fs { _ = try? await call("watchStop", ["watch": .str(id)], frame: f, connection: c) }
    watchTasks.removeValue(forKey: id)
  }
  private func compactWatch(_ id: String, _ w: inout Watch) {
    guard w.state != "running", w.finalResult == .null else { return }
    var result = watchResult(id, w)
    result["historyCompacted"] = true
    result["historyTruncated"] = false
    result["reason"] = .str(String(result["reason"].s.prefix(1000)))
    result["diff"]["url"] = .str(String(result["diff"]["url"].s.prefix(2048)))
    while result.text().utf8.count > 256 * 1024 {
      result["historyTruncated"] = true
      if !result["events"].a.isEmpty {
        result["events"] = .array(Array(result["events"].a.dropFirst()))
        result["droppedEvents"] = .int(result["droppedEvents"].i + 1)
      } else if !result["diff"]["changes"].a.isEmpty {
        result["diff"]["changes"] = .array(Array(result["diff"]["changes"].a.dropLast()))
        result["diff"]["truncated"] = true
      } else {
        break
      }
    }
    w.finalResult = result
    w.historyBytes = result.text().utf8.count
    w.before = [:]
    w.latest = [:]
    w.params = [:]
    w.events = []
  }
  private func watchResult(_ id: String, _ w: Watch) -> J {
    if w.finalResult != .null { return w.finalResult }
    return [
      "watch": .str(id), "state": .str(w.state), "reason": .str(w.reason),
      "conditionMet": .bool(w.matched), "diff": diff(w.before, w.latest),
      "events": .array(w.events), "afterSnapshotTemporary": .bool(w.state == "running"),
      "eventLimit": 200, "droppedEvents": .int(w.dropped),
      "coverage": [
        "dom": "polling plus mutations in roots present at subscription",
        "network": "after_subscription; bodies_and_headers_excluded", "consistency": "best_effort",
      ], "businessCompletionVerified": .bool(w.matched),
    ]
  }
  private func safeEvent(_ e: J) -> J {
    let p = e["params"]
    let m = e["method"].s
    var out: J = [
      "method": e["method"], "observedAt": e["observedAt"], "sequence": e["sequence"],
      "sessionId": e["sessionId"],
    ]
    if m == "Target.targetCreated" {
      out["target"] = p["targetInfo"]["targetId"]
      out["opener"] = p["targetInfo"]["openerId"]
      out["url"] = p["targetInfo"]["url"]
      out["title"] = p["targetInfo"]["title"]
    } else if m.hasPrefix("Network.") {
      out["requestId"] = p["requestId"]
      out["url"] = p["request"]["url"] != .null ? p["request"]["url"] : p["response"]["url"]
      out["status"] = p["response"]["status"]
      out["errorText"] = p["errorText"]
    } else if m == "Runtime.consoleAPICalled" {
      out["type"] = p["type"]
      out["args"] = .array(
        p["args"].a.map {
          ["type": $0["type"], "value": $0["value"], "description": $0["description"]]
        })
    } else if m == "Runtime.exceptionThrown" {
      out["text"] = p["exceptionDetails"]["text"]
      out["description"] = p["exceptionDetails"]["exception"]["description"]
    }
    return out
  }
  private func writeArtifact(_ data: Data, p: J, name: String, metadata: J) throws -> J {
    let output = p["output"].s
    guard output.hasPrefix("/"), !output.contains("\0") else {
      throw AutomationError("output_required", "Provide an absolute output file path")
    }
    let u = URL(fileURLWithPath: output)
    let fm = FileManager.default
    guard !fm.fileExists(atPath: u.path) || p["overwrite"].b else {
      throw AutomationError("output_exists", "Choose a new path or explicitly set overwrite")
    }
    try fm.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: u, options: .atomic)
    try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: u.path)
    var result = metadata
    result["path"] = .str(u.path)
    result["bytes"] = .int(data.count)
    result["delivery"] = "file_only"
    return result
  }
  private func screenshot(_ p: J, info: J) async throws -> J {
    let (c, fs, _) = try await frames(p, info: info)
    guard let f = fs.first(where: { $0.index == 0 }) else {
      throw AutomationError("frame_unavailable", "Root frame unavailable")
    }
    let metrics = try await c.send("Page.getLayoutMetrics", session: f.session)
    let full = p["fullPage"].b
    let size = full ? metrics["cssContentSize"] : metrics["cssVisualViewport"]
    var width = size["width"].i
    var height = size["height"].i
    if !full {
      width = size["clientWidth"].i
      height = size["clientHeight"].i
    }
    var x = full ? 0 : size["pageX"].i
    var y = full ? 0 : size["pageY"].i
    if ["ref", "selector", "role", "name"].contains(where: { !p[$0].s.isEmpty }) {
      let (_, target, q) = try await location(p, info: info)
      let object = try await c.send(
        "Runtime.evaluate",
        [
          "expression": .str("globalThis.__isolator_page_agent_v1.element(\(q.text()))"),
          "contextId": .int(target.context),
        ], session: target.session)
      let box = try await c.send(
        "DOM.getBoxModel", ["objectId": object["result"]["objectId"]], session: target.session)
      let quad = box["model"]["border"].a
      guard quad.count == 8 else {
        throw AutomationError("element_not_visible", "No element screenshot bounds")
      }
      var points = quad
      var current = fs.first(where: { $0.session == target.session }) ?? target
      var visited: Set<String> = []
      while current.session != f.session {
        guard visited.insert(current.id).inserted else {
          throw AutomationError("frame_unavailable", "Frame coordinate cycle")
        }
        var mapped = false
        for parent in fs where parent.session != current.session {
          guard
            let owner = try? await c.send(
              "DOM.getFrameOwner", ["frameId": .str(current.id)], session: parent.session),
            let model = try? await c.send(
              "DOM.getBoxModel", ["backendNodeId": owner["backendNodeId"]], session: parent.session)
          else { continue }
          let border = model["model"]["content"].a
          let meta = try await call("meta", [:], frame: current, connection: c)
          let vw = max(1, meta["viewport"]["width"].i)
          let vh = max(1, meta["viewport"]["height"].i)
          guard border.count == 8 else { continue }
          var transformed: [J] = []
          for i in stride(from: 0, to: 8, by: 2) {
            let u = Double(points[i].i) / Double(vw)
            let v = Double(points[i + 1].i) / Double(vh)
            transformed.append(
              .number(
                Double(border[0].i) + u * Double(border[2].i - border[0].i) + v
                  * Double(border[6].i - border[0].i)))
            transformed.append(
              .number(
                Double(border[1].i) + u * Double(border[3].i - border[1].i) + v
                  * Double(border[7].i - border[1].i)))
          }
          points = transformed
          current = fs.first(where: { $0.session == parent.session }) ?? parent
          mapped = true
          break
        }
        guard mapped else {
          throw AutomationError("frame_unavailable", "Could not map element to the root viewport")
        }
      }
      let xs = stride(from: 0, to: 8, by: 2).map { points[$0].i }
      let ys = stride(from: 1, to: 8, by: 2).map { points[$0].i }
      x = (xs.min() ?? 0) + metrics["cssVisualViewport"]["pageX"].i
      y = (ys.min() ?? 0) + metrics["cssVisualViewport"]["pageY"].i
      width = (xs.max() ?? 0) - (xs.min() ?? 0)
      height = (ys.max() ?? 0) - (ys.min() ?? 0)
    }
    guard width > 0 && height > 0 else {
      throw AutomationError("invalid_viewport", "No screenshot area")
    }
    if full && height > 2400 {
      let count = (height + 2399) / 2400
      guard count <= 32 else {
        throw AutomationError(
          "image_too_large", "Full-page export exceeds 32 tiles; crop or scroll explicitly")
      }
      let output = p["output"].s
      guard output.hasPrefix("/") else {
        throw AutomationError("output_required", "Provide an absolute manifest output path")
      }
      let base = URL(fileURLWithPath: output)
      let dir = base.deletingLastPathComponent().appendingPathComponent(
        base.deletingPathExtension().lastPathComponent + "-tiles")
      guard !FileManager.default.fileExists(atPath: dir.path) else {
        throw AutomationError(
          "output_exists", "Tile directory already exists; choose a new output path")
      }
      try FileManager.default.createDirectory(
        at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
      var tiles: [J] = []
      do {
        for i in 0..<count {
          let h = min(2400, height - i * 2400)
          let scale = min(
            1,
            Double(p["maxSide"].i == 0 ? 1600 : min(max(p["maxSide"].i, 320), 4096))
              / Double(max(width, h)))
          let clip: J = [
            "x": .int(x), "y": .int(y + i * 2400), "width": .int(width), "height": .int(h),
            "scale": .number(scale),
          ]
          let result = try await c.send(
            "Page.captureScreenshot",
            ["format": "png", "clip": clip, "captureBeyondViewport": true], session: f.session)
          guard let data = Data(base64Encoded: result["data"].s), data.count <= 2 * 1024 * 1024
          else { throw AutomationError("image_too_large", "A tile exceeds 2 MiB; reduce maxSide") }
          var q = p
          q["output"] = .str(dir.appendingPathComponent("tile-\(i+1).png").path)
          tiles.append(
            try writeArtifact(
              data, p: q, name: "",
              metadata: [
                "y": .int(y + i * 2400), "width": .int(Int(Double(width) * scale)),
                "height": .int(Int(Double(h) * scale)),
              ]))
        }
        let manifest: J = [
          "tiles": .array(tiles), "fullWidth": .int(width), "fullHeight": .int(height),
          "consistency": "best_effort", "loadedContentOnly": true,
          "visionRequiredForInterpretation": true,
          "notice": AutomationBroker.capabilities["notice"],
        ]
        return try writeArtifact(
          manifest.data(), p: p, name: "",
          metadata: [
            "tileCount": .int(count), "tiles": .array(tiles),
            "visionRequiredForInterpretation": true,
            "notice": AutomationBroker.capabilities["notice"],
          ])
      } catch {
        try? FileManager.default.removeItem(at: dir)
        throw error
      }
    }
    let scale = min(
      1,
      Double(p["maxSide"].i == 0 ? 1600 : min(max(p["maxSide"].i, 320), 4096))
        / Double(max(width, height)))
    let clip: J = [
      "x": .int(x), "y": .int(y), "width": .int(width), "height": .int(height),
      "scale": .number(scale),
    ]
    let r = try await c.send(
      "Page.captureScreenshot",
      ["format": "png", "clip": clip, "captureBeyondViewport": .bool(full)], session: f.session)
    guard let data = Data(base64Encoded: r["data"].s), data.count <= 2 * 1024 * 1024 else {
      throw AutomationError(
        "image_too_large", "Screenshot exceeds 2 MiB; use smaller maxSide or element crop")
    }
    return try writeArtifact(
      data, p: p, name: "screenshot.png",
      metadata: [
        "width": .int(Int(Double(width) * scale)), "height": .int(Int(Double(height) * scale)),
        "visionRequiredForInterpretation": true,
        "notice": "只有当前模型具备图像理解能力且工具支持传递图片时，才能分析截图；能力未知或读取图片曾卡住时，请使用文字快照和元素详情。",
        "loadedContentOnly": true,
      ])
  }
  public func endpoint(_ info: J) async throws -> J {
    let version = try await http("json/version", port: info["port"].i)
    guard let u = URL(string: version["webSocketDebuggerUrl"].s), u.scheme == "ws",
      ["127.0.0.1", "localhost", "::1"].contains(u.host ?? ""), u.port == info["port"].i
    else { throw AutomationError("invalid_endpoint", "Endpoint did not verify") }
    var result = info
    result["cdpReady"] = true
    result["browserVersion"] = version["Browser"]
    result["webSocketDebuggerUrl"] = version["webSocketDebuggerUrl"]
    return result
  }
  public func invalidate(_ profile: String, reason: String = "browser_instance_changed") async {
    guard let generation = profileGenerations.removeValue(forKey: profile) else { return }
    connecting.removeValue(forKey: generation)?.cancel()
    if let c = connections.removeValue(forKey: generation) { await c.close() }
    sessions = sessions.filter { !$0.key.hasPrefix(generation + ":") }
    snapshots = snapshots.filter { $0.value.generation != generation }
    for (id, var w) in watches where w.generation == generation && w.state == "running" {
      watchTasks[id]?.cancel()
      w.state = "failed"
      w.reason = reason
      compactWatch(id, &w)
      watches[id] = w
    }
    prune()
  }
  public func export(_ data: J, p: J) throws -> J {
    try writeArtifact(
      data.data(), p: p, name: "result.json", metadata: ["operationResultExported": true])
  }
  public func shutdown() async {
    for t in watchTasks.values { t.cancel() }
    watchTasks.removeAll()
    for c in connections.values { await c.close() }
    connections.removeAll()
    sessions.removeAll()
    snapshots.removeAll()
    watches.removeAll()
  }
}
