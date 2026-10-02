import Foundation

public actor AutomationBroker {
  public typealias ProfileHandler = @Sendable (String, J) async throws -> J
  private let profiles: ProfileHandler
  private let browser = BrowserAutomation()
  private var completed: [String: J] = [:]
  private var identities: [String: String] = [:]
  private var inflight: Set<String> = []
  private var order: [String] = []
  public init(profiles: @escaping ProfileHandler) { self.profiles = profiles }
  public static var capabilities: J {
    (try? J.decode(Data(AutomationResources.text("protocol", ext: "json").utf8))) ?? [:]
  }
  public func handle(_ request: J) async -> J {
    let id = request["id"].s
    let op = request["operation"].s
    let p = request["params"]
    let identity: J = ["operation": .str(op), "params": p]
    if !id.isEmpty, let cached = completed[id] {
      return identities[id] == identity.text()
        ? cached
        : automationFailure(
          AutomationError(
            "request_id_conflict", "Request ID was already used for different parameters"))
    }
    if !id.isEmpty && inflight.contains(id) {
      return [
        "ok": false,
        "error": [
          "code": "request_in_progress",
          "message": "Request is still running; do not repeat the action",
        ], "id": .str(id),
      ]
    }
    if !id.isEmpty { inflight.insert(id) }
    var reply: J
    do {
      guard Self.capabilities["operations"].a.contains(.str(op)) else {
        throw AutomationError("unknown_operation", op)
      }
      guard
        p == .null
          || {
            if case .object = p { return true }
            return false
          }()
      else { throw AutomationError("invalid_params", "params must be an object") }
      try validate(p)
      for field in Self.capabilities["required"][op].a
      where p[field.s] == .null
        || (field.s != "value"
          && Self.capabilities["parameterSchema"]["properties"][field.s]["type"].s == "string"
          && p[field.s].s.isEmpty)
      { throw AutomationError("missing_parameter", field.s) }
      let data: J
      if op == "system.capabilities" {
        data = Self.capabilities
      } else if op.hasPrefix("profile.") {
        var info = try await profiles(op, p)
        if op == "profile.stop" { await browser.invalidate(p["profile"].s) }
        if ["profile.endpoint", "profile.doctor", "profile.start"].contains(op), info["port"].i > 0
        {
          let tries = op == "profile.start" ? 40 : 1
          var health: J = [:]
          for attempt in 0..<tries {
            do {
              info = try await browser.endpoint(info)
              health = [:]
              break
            } catch {
              health = automationFailure(error)["error"]
              if attempt + 1 < tries { try await Task.sleep(nanoseconds: 250_000_000) }
            }
          }
          if health != [:] {
            info["cdpReady"] = false
            info["diagnostic"] = health
            info["readyForPageTools"] = false
            if op == "profile.endpoint" {
              throw AutomationError("cdp_unavailable", health["message"].s)
            }
          }
        }
        data = info
      } else {
        guard !p["profile"].s.isEmpty else {
          throw AutomationError("profile_required", "Specify an environment folder")
        }
        let info = try await profiles("profile.resolve", p)
        if !p["generation"].s.isEmpty && p["generation"] != info["generation"] {
          throw AutomationError("stale_session", "Browser instance has changed")
        }
        data = try await browser.execute(op, params: p, info: info)
      }
      let delivery =
        !p["output"].s.isEmpty && op != "page.capture" && op != "page.screenshot"
        ? try await browser.export(data, p: p) : data
      reply = [
        "ok": true, "result": op == "system.capabilities" ? delivery : bounded(delivery, p: p),
        "id": .str(id), "protocol": "isolator.local/1",
      ]
    } catch {
      reply = automationFailure(error)
      reply["id"] = .str(id)
    }
    if !id.isEmpty {
      inflight.remove(id)
      completed[id] = reply
      identities[id] = identity.text()
      order.append(id)
      while order.count > 128 {
        let key = order.removeFirst()
        completed.removeValue(forKey: key)
        identities.removeValue(forKey: key)
      }
    }
    return reply
  }
  private func validate(_ p: J) throws {
    let properties = Self.capabilities["parameterSchema"]["properties"]
    for (key, value) in p.o {
      let type = properties[key]["type"].s
      let matches: Bool
      switch (type, value) {
      case ("string", .string), ("boolean", .bool), ("object", .object): matches = true
      case ("integer", .number(let n)): matches = n.isFinite && n.rounded(.towardZero) == n
      case ("array", .array(let a)):
        matches = a.allSatisfy {
          if case .string = $0 { return true }
          return false
        }
      default: matches = false
      }
      guard matches else {
        throw AutomationError(
          "invalid_parameter", "\(key) must be a declared \(type.isEmpty ? "parameter":type)")
      }
    }
    for q in [p, p["until"]] where q != .null {
      if !q["state"].s.isEmpty
        && !["visible", "hidden", "absent", "enabled", "text", "value", "checked"].contains(
          q["state"].s)
      {
        throw AutomationError("invalid_state", q["state"].s)
      }
      if ["text", "value"].contains(q["state"].s) && q[q["state"].s] == .null {
        throw AutomationError("missing_parameter", q["state"].s)
      }
    }
    if p["until"] != .null { try validate(p["until"]) }
  }
  private func bounded(_ data: J, p: J) -> J {
    let budget = min(max(p["maxChars"].i == 0 ? 6000 : p["maxChars"].i, 512), 100000)
    if data.text().count <= budget { return data }
    var out = data
    for key in ["profiles", "tabs"] where out[key] != .null && out.text().count > budget {
      var rows = out[key].a
      let original = rows.count
      out["responseTruncated"] = true
      out["hint"] = "Continue with nextOffset, or increase maxChars"
      out["nextOffset"] = .int(p["offset"].i + rows.count)
      out["truncatedRows"] = 0
      while !rows.isEmpty && out.text().count > budget {
        rows.removeLast()
        out[key] = .array(rows)
        out["nextOffset"] = .int(p["offset"].i + rows.count)
        out["truncatedRows"] = .int(original - rows.count)
      }
    }
    // Never print broken JSON; preserve identifiers and report elided fields explicitly.
    var omissions: [J] = []
    for key in [
      "events", "changes", "outerHTML", "styles", "value", "attributes", "profiles", "tabs",
      "nodes",
    ] where out[key] != .null && out.text().count > budget {
      omissions.append(.str(key))
      out[key] = nil
    }
    if out["diff"] != .null && out.text().count > budget {
      out["diff"]["changes"] = []
      out["diff"]["truncated"] = true
      omissions.append("diff.changes")
    }
    if out["observation"] != .null && out.text().count > budget {
      out["observation"]["events"] = []
      out["observation"]["diff"]["changes"] = []
      out["observation"]["diff"]["truncated"] = true
      omissions.append("observation.details")
    }
    if !omissions.isEmpty {
      out["responseTruncated"] = true
      out["omittedFields"] = .array(omissions)
      out["hint"] = "Use fields, a larger maxChars budget, or file export for full details"
    }
    if out.text().count > budget {
      var minimal: J = [
        "responseTruncated": true, "omittedFieldCount": .int(data.o.count),
        "hint": "Increase maxChars or export to an output file",
      ]
      for key in [
        "snapshot", "tab", "watch", "generation", "path", "nextOffset", "state", "reason",
        "conditionMet", "businessCompletionVerified",
      ] where data[key] != .null && data[key].text().count < 150 { minimal[key] = data[key] }
      if data["observation"] != .null {
        minimal["observation"] = .object(
          data["observation"].o.filter {
            ["watch", "state", "reason", "conditionMet", "businessCompletionVerified"].contains(
              $0.key)
          })
      }
      return minimal
    }
    return out
  }
  public func shutdown() async { await browser.shutdown() }
}
