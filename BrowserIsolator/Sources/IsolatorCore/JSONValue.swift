import Foundation

public enum JSONValue: Sendable, Codable, Equatable, ExpressibleByDictionaryLiteral,
  ExpressibleByArrayLiteral, ExpressibleByStringLiteral, ExpressibleByIntegerLiteral,
  ExpressibleByBooleanLiteral, ExpressibleByNilLiteral
{
  case object([String: JSONValue])
  case array([JSONValue])
  case string(String)
  case number(Double)
  case bool(Bool)
  case null
  public init(dictionaryLiteral elements: (String, JSONValue)...) {
    self = .object(Dictionary(elements, uniquingKeysWith: { _, last in last }))
  }
  public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
  public init(stringLiteral value: String) { self = .string(value) }
  public init(integerLiteral value: Int) { self = .number(Double(value)) }
  public init(booleanLiteral value: Bool) { self = .bool(value) }
  public init(nilLiteral: ()) { self = .null }
  public var s: String {
    if case .string(let value) = self { return value }
    return ""
  }
  public var i: Int {
    if case .number(let value) = self, value.isFinite, value < Double(Int.max),
      value > Double(Int.min)
    {
      return Int(value)
    }
    return 0
  }
  public var b: Bool {
    if case .bool(let value) = self { return value }
    return false
  }
  public var a: [JSONValue] {
    if case .array(let value) = self { return value }
    return []
  }
  public var o: [String: JSONValue] {
    if case .object(let value) = self { return value }
    return [:]
  }
  public subscript(_ key: String) -> JSONValue {
    get { o[key] ?? .null }
    set {
      var obj = o
      obj[key] = newValue
      self = .object(obj)
    }
  }
  public static func str(_ value: String) -> Self { .string(value) }
  public static func int(_ value: Int) -> Self { .number(Double(value)) }
  public static func decode(_ data: Data) throws -> Self {
    try JSONDecoder().decode(Self.self, from: data)
  }
  public func data() throws -> Data {
    let e = JSONEncoder()
    e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return try e.encode(self)
  }
  public func text() -> String { String(data: (try? data()) ?? Data(), encoding: .utf8) ?? "null" }
  public init(from decoder: Decoder) throws {
    let c = try decoder.singleValueContainer()
    if c.decodeNil() {
      self = .null
    } else if let v = try? c.decode(Bool.self) {
      self = .bool(v)
    } else if let v = try? c.decode(String.self) {
      self = .string(v)
    } else if let v = try? c.decode(Double.self) {
      self = .number(v)
    } else if let v = try? c.decode([String: Self].self) {
      self = .object(v)
    } else {
      self = .array(try c.decode([Self].self))
    }
  }
  public func encode(to encoder: Encoder) throws {
    var c = encoder.singleValueContainer()
    switch self {
    case .null: try c.encodeNil()
    case .bool(let v): try c.encode(v)
    case .string(let v): try c.encode(v)
    case .number(let v): try c.encode(v)
    case .array(let v): try c.encode(v)
    case .object(let v): try c.encode(v)
    }
  }
}
public typealias J = JSONValue
public struct AutomationError: Error, LocalizedError, Sendable {
  public let code: String
  public let message: String
  public init(_ code: String, _ message: String) {
    self.code = code
    self.message = message
  }
  public var errorDescription: String? { "\(code): \(message)" }
  public var json: J { ["code": .str(code), "message": .str(message)] }
}
public func automationFailure(_ error: Error) -> J {
  let e =
    error as? AutomationError ?? AutomationError("operation_failed", error.localizedDescription)
  return ["ok": false, "error": e.json]
}
public enum AutomationResources {
  public static func text(_ name: String, ext: String) -> String {
    let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
      .deletingLastPathComponent()
    let candidates = [
      Bundle.main.resourceURL?.appendingPathComponent("BrowserIsolator_IsolatorCore.bundle"),
      executable.appendingPathComponent("BrowserIsolator_IsolatorCore.bundle"),
      executable.appendingPathComponent("../Resources/BrowserIsolator_IsolatorCore.bundle")
        .standardizedFileURL,
    ]
    let packaged = candidates.compactMap { $0.flatMap(Bundle.init(url:)) }.first
    guard let u = (packaged ?? Bundle.module).url(forResource: name, withExtension: ext),
      let s = try? String(contentsOf: u, encoding: .utf8)
    else { return "" }
    return s
  }
}
