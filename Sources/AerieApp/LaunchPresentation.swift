import AppKit
import Carbon

/// Explicit manual launches open Settings; background tests and OS login/service launches stay quiet.
enum LaunchPresentation {
  static func silent(arguments: [String], event: NSAppleEventDescriptor?) -> Bool {
    if arguments.contains("--background") || arguments.contains("--self-check") { return true }
    guard let event, event.eventID == AEEventID(kAEOpenApplication) else { return false }
    let markers = [AEKeyword(keyAELaunchedAsLogInItem), AEKeyword(keyAELaunchedAsServiceItem)]
    if markers.contains(where: { event.paramDescriptor(forKeyword: $0) != nil }) { return true }
    let value = event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue
    return markers.contains { value == $0 }
  }
}
