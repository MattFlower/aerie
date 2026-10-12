import AppKit
import Carbon

/// Let the existing first sample populate Settings inventories without extra collection.
/// A bounded fallback still opens the window if that sample is unavailable or delayed.
struct InitialSettingsPresentation {
  private(set) var sampleAvailable = false
  private(set) var awaitingSample = false
  mutating func request() -> Bool {
    if sampleAvailable { return true }
    awaitingSample = true
    return false
  }
  mutating func receivedSample() -> Bool {
    sampleAvailable = true
    return consumeRequest()
  }
  mutating func fallback() -> Bool { consumeRequest() }
  mutating func didPresent() { awaitingSample = false }
  private mutating func consumeRequest() -> Bool {
    let present = awaitingSample
    awaitingSample = false
    return present
  }
}

/// Explicit manual launches open Settings; background tests and OS login/service launches stay quiet.
enum LaunchPresentation {
  static func presentsOnReopen(arguments: [String], visibleWindows: Bool, menuShown: Bool) -> Bool {
    !visibleWindows && !menuShown
      && !arguments.contains("--background") && !arguments.contains("--self-check")
  }
  static func silent(arguments: [String], event: NSAppleEventDescriptor?) -> Bool {
    if arguments.contains("--self-check") { return true }
    if arguments.contains("--background") { return !arguments.contains("--open-settings") }
    guard let event, event.eventID == AEEventID(kAEOpenApplication) else { return false }
    let markers = [AEKeyword(keyAELaunchedAsLogInItem), AEKeyword(keyAELaunchedAsServiceItem)]
    if markers.contains(where: { event.paramDescriptor(forKeyword: $0) != nil }) { return true }
    let value = event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue
    return markers.contains { value == $0 }
  }
}
