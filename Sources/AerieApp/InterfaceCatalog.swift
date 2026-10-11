import Foundation
import SystemConfiguration

struct InterfaceDescription {
  let name, kind: String
}
enum InterfaceCatalog {
  /// Settings-only metadata. No polling, network request, or saved interface addresses.
  static func descriptions() -> [String: InterfaceDescription] {
    guard let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] else { return [:] }
    var result: [String: InterfaceDescription] = [:]
    for interface in interfaces.prefix(256) {
      guard let identifier = SCNetworkInterfaceGetBSDName(interface) as String? else { continue }
      let name = SCNetworkInterfaceGetLocalizedDisplayName(interface) as String? ?? identifier
      let kind = SCNetworkInterfaceGetInterfaceType(interface) as String? ?? "Interface"
      result[identifier] = InterfaceDescription(
        name: String(name.prefix(128)), kind: String(kind.prefix(64)))
    }
    return result
  }
  static func title(identifier: String, active: Bool, description: InterfaceDescription?) -> String
  {
    let name = description?.name ?? "Network interface"
    let kind = description?.kind ?? "Interface"
    return "\(name) · \(identifier) · \(kind) · \(active ? "Active" : "Inactive")"
  }
}
