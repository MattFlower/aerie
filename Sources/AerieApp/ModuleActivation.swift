import AerieCore
import AppKit

enum ModuleActivation: Equatable {
  case close
  case show(Module)
  static func resolve(requested: Module, shown: Module?) -> ModuleActivation {
    shown == requested ? .close : .show(requested)
  }
}

/// Each native button retains its own destination through tracking and item rebuilds.
/// A forwarded sender need not be the exact object returned by NSStatusItem.button.
final class StatusItemTarget: NSObject {
  let module: Module
  private let onPress: (Module, NSButton) -> Void
  init(module: Module, onPress: @escaping (Module, NSButton) -> Void) {
    self.module = module; self.onPress = onPress
  }
  func attach(to button: NSButton) {
    button.target = self; button.action = #selector(press(_:))
    button.sendAction(on: [.leftMouseUp, .rightMouseUp])
  }
  @objc private func press(_ sender: NSButton) { onPress(module, sender) }
}
