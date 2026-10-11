import AerieCore
import AerieNative
import Darwin
import Foundation

protocol StorageCommandTransport: AnyObject {
  func run(_ arguments: [String]) throws -> Data
  func cancel()
}
enum StorageCommandError: Error { case cancelled, failed, oversized }
/// Finite read-only OS queries. Output and lifetime are bounded; no shell or credentials are used.
final class StorageCommand: StorageCommandTransport {
  private let lock = NSLock()
  private var process: Process?
  private var cancelled = false
  private let executable: URL
  private let terminateAfter, killAfter: Double
  private let measurement: ((StorageCommandMeasurement) -> Void)?
  init(
    executable: URL = URL(fileURLWithPath: "/usr/sbin/diskutil"),
    terminateAfter: Double = 5, killAfter: Double = 6,
    measurement: ((StorageCommandMeasurement) -> Void)? = nil
  ) {
    self.executable = executable
    self.terminateAfter = terminateAfter; self.killAfter = max(terminateAfter, killAfter)
    self.measurement = measurement
  }
  func run(_ arguments: [String]) throws -> Data {
    let task = Process(), pipe = Pipe()
    task.executableURL = executable; task.arguments = arguments
    task.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LC_ALL": "C"]
    task.standardOutput = pipe; task.standardError = FileHandle.nullDevice
    task.standardInput = FileHandle.nullDevice
    lock.lock()
    if cancelled { lock.unlock(); throw StorageCommandError.cancelled }
    process = task
    do { try task.run() } catch { process = nil; lock.unlock(); throw error }
    lock.unlock()
    try? pipe.fileHandleForWriting.close()
    let identity = aerie_process_birth(task.processIdentifier)
    let probe = measurement.map {
      StorageCommandProbe(pid: task.processIdentifier, birth: identity, output: $0)
    }
    let deadline = DispatchWorkItem { if task.isRunning { task.terminate() } }
    DispatchQueue.global(qos: .utility).asyncAfter(
      deadline: .now() + terminateAfter, execute: deadline)
    let killDeadline = DispatchWorkItem {
      if task.isRunning, identity > 0, aerie_process_birth(task.processIdentifier) == identity {
        Darwin.kill(task.processIdentifier, SIGKILL)
      }
    }
    DispatchQueue.global(qos: .utility).asyncAfter(
      deadline: .now() + killAfter, execute: killDeadline)
    defer {
      deadline.cancel()
      if task.isRunning { task.terminate() }
      task.waitUntilExit()
      killDeadline.cancel()
      probe?.finish(status: task.terminationStatus)
      try? pipe.fileHandleForReading.close(); try? pipe.fileHandleForWriting.close()
      lock.lock(); process = nil; lock.unlock()
    }
    var data = Data()
    while let chunk = try pipe.fileHandleForReading.read(upToCount: 8192), !chunk.isEmpty {
      guard data.count <= 2_000_000 - chunk.count else { throw StorageCommandError.oversized }
      data.append(chunk)
    }
    task.waitUntilExit()
    lock.lock(); let wasCancelled = cancelled; lock.unlock()
    guard !wasCancelled else { throw StorageCommandError.cancelled }
    guard task.terminationStatus == 0 else { throw StorageCommandError.failed }
    return data
  }
  func cancel() {
    lock.lock(); cancelled = true; let task = process; lock.unlock()
    if let task, task.isRunning { task.terminate() }
  }
  deinit { cancel() }
}
struct StorageMetadataReading {
  var topology: DriveTopology?
  var drives: [String: DriveMetadata] = [:]
  var queriedAt: Date?
  var status = "Drive health begins when the Storage panel opens."
}
final class StorageMetadataReader {
  private let lock = NSLock()
  private let queue = DispatchQueue(label: "app.aerie.drive-metadata", qos: .utility)
  private let factory: () -> StorageCommandTransport
  private var command: StorageCommandTransport?
  private var generation = 0
  private var visible = false
  private var lastStarted = -Double.infinity
  private var result = StorageMetadataReading()
  init(
    factory: @escaping () -> StorageCommandTransport = {
      StorageCommand(measurement: StorageCommandProbe.cliOutput)
    }
  ) {
    self.factory = factory
  }
  func configure(visible: Bool, time: Double = ProcessInfo.processInfo.systemUptime) {
    lock.lock()
    self.visible = visible
    if !visible {
      generation += 1; let command = command; self.command = nil
      result = StorageMetadataReading(); lastStarted = -.infinity
      lock.unlock(); command?.cancel(); return
    }
    guard command == nil, time - lastStarted >= 60 else { lock.unlock(); return }
    let command = factory(); self.command = command; lastStarted = time
    result.status = "Reading OS drive metadata…"
    let token = generation; lock.unlock()
    queue.async { [weak self] in
      var reading = StorageMetadataReading()
      do {
        let physical = try DiskutilMetadata.physicalDisks(
          command.run(["list", "-plist", "physical"]))
        var warnings = 0
        do {
          reading.topology = try DiskutilMetadata.topology(
            physical: physical, apfs: command.run(["apfs", "list", "-plist"]))
        } catch {
          reading.topology = DriveTopology(physicalDisks: physical, physicalStoresByVolume: [:]);
          warnings += 1
        }
        for disk in physical {
          do {
            reading.drives[disk] = try DiskutilMetadata.drive(
              command.run(["info", "-plist", disk]), expected: disk)
          } catch { warnings += 1 }
        }
        reading.queriedAt = Date()
        reading.status =
          "OS-reported drive metadata · refresh 60s while visible · \(warnings) queries unavailable"
      } catch { reading.status = "OS drive metadata unavailable; reopen or wait 60s to retry." }
      guard let self else { return }
      self.lock.lock(); defer { self.lock.unlock() }
      guard self.visible, self.generation == token else { return }
      self.result = reading; self.command = nil
    }
  }
  func reading() -> StorageMetadataReading { lock.lock(); defer { lock.unlock() }; return result }
  deinit { command?.cancel() }
}
