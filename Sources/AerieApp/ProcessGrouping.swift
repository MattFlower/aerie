import AerieCore
import AerieNative
import Foundation

/// Reads paths only for explicitly combined, visible process details; retains no path cache.
final class ProcessGroupReader {
  private let path: (ProcessIdentity) -> String?
  init(
    path: @escaping (ProcessIdentity) -> String? = { identity in
      guard let pid = Int32(exactly: identity.pid), pid > 0, identity.startTime > 0 else {
        return nil
      }
      var bytes = [CChar](repeating: 0, count: 4096)
      guard aerie_process_path(pid, identity.startTime, &bytes, Int32(bytes.count)) > 0 else {
        return nil
      }
      return String(validatingCString: bytes)
    }
  ) { self.path = path }
  func read(_ identities: [ProcessIdentity], enabled: Bool, visible: Bool) -> [ProcessIdentity:
    ProcessGroupIdentity]
  {
    guard enabled, visible, identities.count <= 8192 else { return [:] }
    var result: [ProcessIdentity: ProcessGroupIdentity] = [:]
    for identity in Set(identities) where identity.pid > 0 && identity.startTime > 0 {
      result[identity] = path(identity).flatMap { ProcessGroupIdentity(executablePath: $0) }
    }
    return result
  }
}

enum ProcessPresentation {
  static func completeSum(_ values: [Double?]) -> Double? {
    guard !values.isEmpty else { return nil }
    var total = 0.0
    for value in values {
      guard let value, value.isFinite, value >= 0 else { return nil }
      total += value
      guard total.isFinite else { return nil }
    }
    return total
  }
  static func combine(_ rows: [ProcessData], enabled: Bool) -> [ProcessData] {
    guard enabled else { return rows }
    var groups: [ProcessGroupIdentity: [ProcessData]] = [:], result: [ProcessData] = []
    for row in rows {
      if let group = row.group {
        groups[group, default: []].append(row)
      } else {
        result.append(row)
      }
    }
    for (group, members) in groups {
      guard members.count > 1 else { result += members; continue }
      result.append(
        ProcessData(
          pid: members.map(\.pid).min() ?? 0,
          name: group.name + " · \(members.count) processes",
          cpu: completeSum(members.map(\.cpu)),
          memory: completeSum(members.map { $0.memory }) ?? .nan,
          read: completeSum(members.map(\.read)), write: completeSum(members.map(\.write)),
          wakeups: completeSum(members.map(\.wakeups)), group: group, members: members.count))
    }
    return result
  }
  static func sorted(
    _ rows: [ProcessData], by sort: ProcessSort, automatic: (ProcessData, ProcessData) -> Bool
  ) -> [ProcessData] {
    func value(_ row: ProcessData) -> Double? {
      let value: Double?
      switch sort {
      case .cpu: value = row.cpu
      case .memory: value = row.memory
      case .read: value = row.read
      case .write: value = row.write
      case .wakeups: value = row.wakeups
      default: value = nil
      }
      return value.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
    }
    return rows.sorted {
      let left = value($0), right = value($1)
      if sort == .automatic {
        if automatic($0, $1) { return true }
        if automatic($1, $0) { return false }
      } else if left != right {
        if let left, let right { return left > right }
        return left != nil
      }
      return $0.name == $1.name ? $0.pid < $1.pid : $0.name < $1.name
    }
  }
  struct NetworkRow {
    let pid: Int32
    let name: String
    let download, upload: Double?
    var members = 1
  }
  static func network(
    _ rows: [ProcessNetworkReading], groups: [ProcessIdentity: ProcessGroupIdentity], enabled: Bool,
    sort: ProcessSort
  ) -> [NetworkRow] {
    var combined: [ProcessGroupIdentity: [NetworkRow]] = [:], result: [NetworkRow] = []
    for row in rows {
      let value = NetworkRow(
        pid: row.pid, name: row.name, download: row.download, upload: row.upload)
      if enabled, let group = groups[ProcessIdentity(pid: Int(row.pid), startTime: row.startTime)] {
        combined[group, default: []].append(value)
      } else {
        result.append(value)
      }
    }
    for (group, members) in combined {
      guard members.count > 1 else { result += members; continue }
      result.append(
        NetworkRow(
          pid: members.map(\.pid).min() ?? 0,
          name: group.name + " · \(members.count) processes",
          download: completeSum(members.map(\.download)),
          upload: completeSum(members.map(\.upload)), members: members.count))
    }
    func value(_ row: NetworkRow) -> Double? {
      let value =
        sort == .download
        ? row.download : sort == .upload ? row.upload : completeSum([row.download, row.upload])
      return value.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
    }
    return result.sorted {
      let left = value($0), right = value($1)
      if left != right { if let left, let right { return left > right }; return left != nil }
      return $0.name == $1.name ? $0.pid < $1.pid : $0.name < $1.name
    }
  }
}
