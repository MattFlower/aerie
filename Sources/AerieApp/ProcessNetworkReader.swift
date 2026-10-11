import AerieCore
import AerieNative
import Darwin
import Foundation

/// Uses one bundled OS logger only while requested. It owns no helper while idle or suspended.
final class ProcessNetworkReader {
  private let queue: DispatchQueue
  private let executable: URL
  private let arguments: [String]?
  private var pid: Int32?
  private var processIdentity: UInt64?
  private var source: DispatchSourceRead?
  private var decoder = ProcessNetworkCSV()
  private var rates = ProcessNetworkRates()
  private var generation = 0
  private var interval = 1.0
  private var lastFrameTime: Double?
  private(set) var rows: [ProcessNetworkReading] = []
  private(set) var denied = 0
  private(set) var status = "Process traffic begins when this panel opens."
  var helperPID: Int32? { pid }
  init(
    queue: DispatchQueue, executable: URL = URL(fileURLWithPath: "/usr/bin/nettop"),
    arguments: [String]? = nil
  ) {
    self.queue = queue; self.executable = executable; self.arguments = arguments
  }
  func configure(visible: Bool, interval requested: Double) {
    let interval = ceil(max(1, requested))
    guard visible else { stop(); return }
    if pid != nil, self.interval == interval { return }
    stop(); self.interval = interval
    var master: Int32 = -1, child: Int32 = -1
    let result = executable.path.withCString { path in
      if let argument = arguments?.first {
        return argument.withCString {
          aerie_network_spawn(path, $0, Int32(interval), &master, &child)
        }
      }
      return aerie_network_spawn(path, nil, Int32(interval), &master, &child)
    }
    guard result == 0 else { status = "OS process traffic logger unavailable (\(result))."; return }
    pid = child; processIdentity = aerie_process(child).start_time
    let token = generation
    let exitSource = DispatchSource.makeProcessSource(
      identifier: child, eventMask: .exit, queue: queue)
    exitSource.setEventHandler { [weak self] in
      var exitStatus: Int32 = 0; Darwin.waitpid(child, &exitStatus, 0)
      exitSource.setEventHandler {}; exitSource.cancel()
      guard let self, self.generation == token else { return }
      self.stop(); self.status = "OS process traffic logger exited. Reopen the panel to retry."
    }
    exitSource.resume()
    status = "Awaiting process traffic baseline · \(Int(interval))s"
    let source = DispatchSource.makeReadSource(fileDescriptor: master, queue: queue)
    self.source = source
    source.setCancelHandler { Darwin.close(master) }
    source.setEventHandler { [weak self] in self?.receive(master, token: token) }
    source.resume()
  }
  private func receive(_ descriptor: Int32, token: Int) {
    guard generation == token else { return }
    var bytes = [UInt8](repeating: 0, count: 8192)
    // Bound work per callback; the dispatch source will signal remaining readable bytes again.
    for _ in 0..<16 {
      let count = Darwin.read(descriptor, &bytes, bytes.count)
      if count < 0, errno == EAGAIN { return }
      guard count > 0 else {
        stop(); status = "OS process traffic stream unavailable. Reopen the panel to retry."; return
      }
      do {
        let frames = try decoder.consume(
          Data(bytes.prefix(count)), time: ProcessInfo.processInfo.systemUptime)
        for frame in frames {
          let result = rates.update(frame) { pid in
            let info = aerie_process(pid)
            return info.valid != 0 && info.start_time > 0 ? info.start_time : nil
          }
          rows = result.rows; denied = result.denied; lastFrameTime = frame.time
          status =
            "OS TCP/UDP process summaries · \(Int(interval))s · \(denied) identities unavailable"
        }
      } catch {
        stop(); status = "OS process traffic format unavailable. Reopen the panel to retry."; return
      }
    }
  }
  func current(time: Double) -> (rows: [ProcessNetworkReading], status: String) {
    if let lastFrameTime, time - lastFrameTime > max(5, interval * 3) {
      return ([], "OS process traffic is stale; no previous rates are presented as live.")
    }
    return (rows, status)
  }
  func stop() {
    generation += 1
    source?.cancel(); source = nil
    if let pid {
      let identity = processIdentity
      Darwin.kill(pid, SIGTERM)
      queue.asyncAfter(deadline: .now() + 2) {
        if let identity, identity > 0, aerie_process(pid).start_time == identity {
          Darwin.kill(pid, SIGKILL)
        }
      }
    }
    pid = nil; processIdentity = nil; decoder = ProcessNetworkCSV(); rates = ProcessNetworkRates()
    rows.removeAll(); denied = 0; lastFrameTime = nil
    status = "Process traffic begins when this panel opens."
  }
  deinit { stop() }
}
