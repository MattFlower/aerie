import Foundation

/// Volatile executable identity, never a persisted preference or history value.
public struct ProcessGroupIdentity: Hashable {
  public let key, name: String
  public init?(executablePath: String) {
    guard executablePath.hasPrefix("/"), executablePath.utf8.count < 4096,
      !executablePath.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    else { return nil }
    let parts = executablePath.dropFirst().split(separator: "/", omittingEmptySubsequences: false)
    guard parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else { return nil }
    if let index = parts.indices.first(where: {
      parts[$0].hasSuffix(".app") && $0 + 1 < parts.count && parts[$0 + 1] == "Contents"
    }) {
      key = "bundle:/" + parts[...index].joined(separator: "/")
      name = String(parts[index].dropLast(4).prefix(128))
    } else {
      key = "executable:" + executablePath
      name = String((parts.last ?? "").prefix(128))
    }
    guard !name.isEmpty else { return nil }
  }
}

public enum ProcessSort: String, CaseIterable, Codable {
  case automatic, cpu, memory, read, write, wakeups, download, upload
  public var title: String {
    switch self {
    case .automatic: return "Automatic"
    case .cpu: return "CPU"
    case .memory: return "Memory"
    case .read: return "Disk read"
    case .write: return "Disk write"
    case .wakeups: return "Interrupt wakeups"
    case .download: return "Download"
    case .upload: return "Upload"
    }
  }
  public static let modules: [Module] = [.cpu, .memory, .storage, .network, .power]
  public static func options(for module: Module) -> [ProcessSort] {
    switch module {
    case .cpu, .memory: return [.automatic, .cpu, .memory]
    case .storage: return [.automatic, .read, .write, .cpu, .memory]
    case .power: return [.automatic, .wakeups, .cpu, .memory]
    case .network: return [.automatic, .download, .upload]
    default: return []
    }
  }
  public static func valid(_ choices: [Module: ProcessSort]?) -> Bool {
    choices?.allSatisfy { options(for: $0.key).contains($0.value) } ?? true
  }
}
