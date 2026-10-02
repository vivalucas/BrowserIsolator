import Darwin
import Foundation

public enum LocalTransport {
  public static var socketPath: String {
    if let path = ProcessInfo.processInfo.environment["ISOLATOR_SOCKET"], path.hasPrefix("/") {
      return path
    }
    return NSTemporaryDirectory() + "isolator-\(getuid())/browserisolator.sock"
  }
  static func address(_ path: String) throws -> sockaddr_un {
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(path.utf8) + [0]
    guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
      throw AutomationError("invalid_socket_path", "Socket path is too long")
    }
    withUnsafeMutableBytes(of: &address.sun_path) { dest in
      for (i, b) in bytes.enumerated() { dest[i] = b }
    }
    return address
  }
  static func peer(_ fd: Int32) -> Bool {
    var uid: uid_t = 0
    var gid: gid_t = 0
    return getpeereid(fd, &uid, &gid) == 0 && uid == getuid()
  }
  static func tune(_ fd: Int32, seconds: Int) {
    _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
    var value: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &value, socklen_t(MemoryLayout<Int32>.size))
    var timeout = timeval(tv_sec: seconds, tv_usec: 0)
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
  }
  static func readLine(_ fd: Int32, limit: Int) throws -> Data {
    var out = Data()
    var b = [UInt8](repeating: 0, count: 8192)
    while out.count <= limit {
      let n = Darwin.read(fd, &b, b.count)
      if n <= 0 {
        throw AutomationError(
          "transport_closed", "Local connection ended or timed out; do not replay actions")
      }
      if let index = b.prefix(n).firstIndex(of: 10) {
        guard out.count + index <= limit else {
          throw AutomationError("message_too_large", "Local message exceeds configured limit")
        }
        out.append(contentsOf: b[..<index])
        return out
      }
      out.append(contentsOf: b.prefix(n))
    }
    throw AutomationError("message_too_large", "Local message exceeds configured limit")
  }
  static func writeLine(_ fd: Int32, data: Data) throws {
    let bytes = data + Data([10])
    try bytes.withUnsafeBytes { raw in
      var sent = 0
      while sent < bytes.count {
        let n = Darwin.write(fd, raw.baseAddress!.advanced(by: sent), bytes.count - sent)
        if n <= 0 { throw AutomationError("transport_closed", "Could not write local response") }
        sent += n
      }
    }
  }
  public static func request(_ request: J, path: String = socketPath, timeout: Int = 330) throws
    -> J
  {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { throw AutomationError("transport_unavailable", "Could not create socket") }
    defer { Darwin.close(fd) }
    tune(fd, seconds: timeout)
    var addr = try address(path)
    let connected = withUnsafePointer(to: &addr) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
      }
    }
    guard connected == 0 else {
      throw AutomationError(
        "app_not_running", "Start BrowserIsolator, or pass --launch with its application path")
    }
    guard peer(fd) else {
      throw AutomationError("unauthorized_peer", "Server belongs to another user")
    }
    try writeLine(fd, data: request.data())
    return try J.decode(readLine(fd, limit: 32 * 1024 * 1024))
  }
}
public final class AutomationServer: @unchecked Sendable {
  private var fd: Int32 = -1
  private let path: String
  private let handler: @Sendable (J) async -> J
  private let lock = NSLock()
  private var clients = 0
  public init(path: String = LocalTransport.socketPath, handler: @escaping @Sendable (J) async -> J)
  {
    self.path = path
    self.handler = handler
  }
  public func start() throws {
    let dir = URL(fileURLWithPath: path).deletingLastPathComponent()
    try FileManager.default.createDirectory(
      at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    var st = stat()
    guard lstat(dir.path, &st) == 0, (st.st_mode & S_IFMT) == S_IFDIR, st.st_uid == getuid(),
      (st.st_mode & 0o077) == 0
    else {
      throw AutomationError(
        "unsafe_socket_directory", "Automation socket requires a private directory")
    }
    fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { throw AutomationError("transport_unavailable", "Socket creation failed") }
    LocalTransport.tune(fd, seconds: 10)
    // A successful connect means the listener is owned, even if it is unresponsive.
    let probe = socket(AF_UNIX, SOCK_STREAM, 0)
    if probe >= 0 {
      var address = try LocalTransport.address(path)
      let connected =
        withUnsafePointer(to: &address) {
          $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            Darwin.connect(probe, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
          }
        } == 0
      Darwin.close(probe)
      if connected {
        Darwin.close(fd)
        fd = -1
        throw AutomationError("already_running", "Another application owns the automation listener")
      }
    }
    if lstat(path, &st) == 0 {
      guard (st.st_mode & S_IFMT) == S_IFSOCK && st.st_uid == getuid() else {
        Darwin.close(fd)
        fd = -1
        throw AutomationError("unsafe_socket_path", "Refusing to replace a non-socket path")
      }
      unlink(path)
    }
    var addr = try LocalTransport.address(path)
    let result = withUnsafePointer(to: &addr) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
      }
    }
    guard result == 0 else {
      Darwin.close(fd)
      fd = -1
      throw AutomationError("bind_failed", "Automation listener could not bind")
    }
    chmod(path, 0o600)
    guard listen(fd, 16) == 0 else {
      stop()
      throw AutomationError("listen_failed", "Automation listener failed")
    }
    let listener = fd
    DispatchQueue.global(qos: .utility).async { [weak self] in
      while let self, self.owns(listener) {
        let client = accept(listener, nil, nil)
        if client < 0 {
          if errno == EAGAIN || errno == EINTR { continue }
          break
        }
        guard LocalTransport.peer(client), self.admit() else {
          Darwin.close(client)
          continue
        }
        LocalTransport.tune(client, seconds: 330)
        DispatchQueue.global(qos: .utility).async { [self] in
          do {
            let data = try LocalTransport.readLine(client, limit: 1024 * 1024)
            let request = try J.decode(data)
            Task {
              let reply = await self.handler(request)
              try? LocalTransport.writeLine(client, data: reply.data())
              Darwin.close(client)
              self.release()
            }
          } catch {
            try? LocalTransport.writeLine(client, data: automationFailure(error).data())
            Darwin.close(client)
            self.release()
          }
        }
      }
    }
  }
  private func owns(_ listener: Int32) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return fd == listener
  }
  private func admit() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard clients < 32 else { return false }
    clients += 1
    return true
  }
  private func release() {
    lock.lock()
    clients -= 1
    lock.unlock()
  }
  public func stop() {
    lock.lock()
    let socket = fd
    fd = -1
    lock.unlock()
    if socket >= 0 {
      shutdown(socket, SHUT_RDWR)
      Darwin.close(socket)
      unlink(path)
    }
  }
}
