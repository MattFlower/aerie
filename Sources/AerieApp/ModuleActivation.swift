import AerieCore

enum ModuleActivation: Equatable {
  case close
  case show(Module)
  static func resolve(requested: Module, shown: Module?) -> ModuleActivation {
    shown == requested ? .close : .show(requested)
  }
}
