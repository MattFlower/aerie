import AerieCore
import Carbon
import Foundation

protocol HotKeyDriver: AnyObject {
  var onPress: ((UInt32) -> Void)? { get set }
  var onLayoutChange: (() -> Void)? { get set }
  func register(_ shortcut: KeyboardShortcut, identifier: UInt32) -> Int32
  func stop()
}
/// Registers only chosen combinations; it never observes the general keyboard event stream.
private final class NativeHotKeyDriver: HotKeyDriver {
  private var handler: EventHandlerRef?
  private var hotKeys: [EventHotKeyRef] = []
  private var installed: OSStatus = noErr
  var onPress: ((UInt32) -> Void)?
  var onLayoutChange: (() -> Void)?
  private var layoutObserver: NSObjectProtocol?
  init() {
    var type = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    let callback: EventHandlerUPP = { _, event, context in
      guard let event, let context else { return OSStatus(eventNotHandledErr) }
      var identity = EventHotKeyID()
      let status = GetEventParameter(
        event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
        MemoryLayout<EventHotKeyID>.size, nil, &identity)
      guard status == noErr, identity.signature == 0x41455249 else {
        return OSStatus(eventNotHandledErr)
      }
      Unmanaged<NativeHotKeyDriver>.fromOpaque(context).takeUnretainedValue().onPress?(identity.id)
      return noErr
    }
    installed = InstallEventHandler(
      GetApplicationEventTarget(), callback, 1, &type, Unmanaged.passUnretained(self).toOpaque(),
      &handler)
    layoutObserver = DistributedNotificationCenter.default().addObserver(
      forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
      object: nil, queue: .main
    ) { [weak self] _ in self?.onLayoutChange?() }

  }
  private func keyCode(_ key: String) -> UInt32? {
    if key == "SPACE" { return UInt32(kVK_Space) }
    let functionKeys = [
      kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11,
      kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
    ]
    if key.hasPrefix("F"), let number = Int(key.dropFirst()), (1...20).contains(number) {
      return UInt32(functionKeys[number - 1])
    }
    guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
      let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
    else { return nil }
    let data = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue()
    guard CFDataGetLength(data) >= MemoryLayout<UCKeyboardLayout>.size,
      let bytes = CFDataGetBytePtr(data)
    else { return nil }
    let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
    for code in UInt16(0)..<128 {
      var state: UInt32 = 0, length = 0
      var characters = [UniChar](repeating: 0, count: 4)
      let status = UCKeyTranslate(
        layout, code, UInt16(kUCKeyActionDown), 0, UInt32(LMGetKbdType()),
        OptionBits(kUCKeyTranslateNoDeadKeysMask), &state, 4, &length, &characters)
      if status == noErr, length > 0, length <= 4,
        String(utf16CodeUnits: characters, count: length).uppercased() == key
      {
        return UInt32(code)
      }
    }
    return nil
  }
  func register(_ shortcut: KeyboardShortcut, identifier: UInt32) -> Int32 {
    guard installed == noErr else { return installed }
    guard shortcut.valid, let code = keyCode(shortcut.key) else { return Int32(paramErr) }
    var modifiers: UInt32 = 0
    if shortcut.command { modifiers |= UInt32(cmdKey) };
    if shortcut.control { modifiers |= UInt32(controlKey) }
    if shortcut.option { modifiers |= UInt32(optionKey) };
    if shortcut.shift { modifiers |= UInt32(shiftKey) }
    var reference: EventHotKeyRef?
    let status = RegisterEventHotKey(
      code, modifiers, EventHotKeyID(signature: 0x41455249, id: identifier),
      GetApplicationEventTarget(), 0, &reference)
    if status == noErr, let reference { hotKeys.append(reference) }
    return status
  }
  func stop() {
    hotKeys.forEach { UnregisterEventHotKey($0) }; hotKeys.removeAll()
    if let layoutObserver {
      DistributedNotificationCenter.default().removeObserver(layoutObserver);
      self.layoutObserver = nil
    }
    if let handler { RemoveEventHandler(handler); self.handler = nil }; onPress = nil
    onLayoutChange = nil
  }
  deinit { stop() }
}
/// Main-thread ownership. IDs are never reused within the app lifetime, so late events are ignored.
final class KeyboardShortcuts {
  private let factory: () -> HotKeyDriver
  private var driver: HotKeyDriver?
  private var bindings: [UInt32: KeyboardShortcut] = [:]
  private var nextIdentifier: UInt32 = 0
  private var generation: UInt64 = 0
  var registeredCount: Int { bindings.count }
  private var configured: [KeyboardShortcut] = []
  var onPress: ((KeyboardShortcut) -> Void)?
  var onReconfigured: (([String]) -> Void)?
  init(factory: @escaping () -> HotKeyDriver = { NativeHotKeyDriver() }) { self.factory = factory }
  func configure(_ shortcuts: [KeyboardShortcut]) -> [String] {
    generation &+= 1
    let expectedGeneration = generation
    driver?.stop(); driver = nil; bindings.removeAll()
    configured = shortcuts
    guard KeyboardShortcut.valid(shortcuts) else { return ["Invalid shortcut configuration"] }
    guard !shortcuts.isEmpty else { return [] }
    let driver = factory(); self.driver = driver
    driver.onPress = { [weak self] identifier in
      guard let self, self.generation == expectedGeneration,
        let binding = self.bindings[identifier]
      else { return };
      self.onPress?(binding)
    }
    driver.onLayoutChange = { [weak self] in
      guard let self, self.generation == expectedGeneration else { return }
      let result = self.configure(self.configured); self.onReconfigured?(result)
    }
    var failed: [String] = []
    for shortcut in shortcuts {
      guard nextIdentifier < UInt32.max else {
        failed.append(shortcut.targetTitle + ": identifier limit"); continue
      }
      nextIdentifier += 1
      let status = driver.register(shortcut, identifier: nextIdentifier)
      if status == 0 {
        bindings[nextIdentifier] = shortcut
      } else {
        failed.append(shortcut.targetTitle + ": unavailable OS status \(status)")
      }
    }
    return failed
  }
  func stop() {
    generation &+= 1
    driver?.stop(); driver = nil; bindings.removeAll(); configured.removeAll()
  }
  deinit { stop() }
}
