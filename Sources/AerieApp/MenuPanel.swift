import AppKit

private final class MenuDashboardWindow: NSPanel {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }
  override func cancelOperation(_ sender: Any?) { close() }
}

/// An opaque, ordinary AppKit utility panel. The dashboard and every source keep their cadence.
final class MenuPanel: NSObject, NSWindowDelegate {
  var contentViewController: NSViewController?
  var contentSize = NSSize(width: 416, height: 620)
  var onClose: (() -> Void)?
  var onCreate: ((NSWindow) -> Void)?
  var onShow: ((NSWindow) -> Void)?
  private var panel: MenuDashboardWindow?
  private var deactivationObserver: NSObjectProtocol?
  var isShown: Bool { panel?.isVisible == true }

  func show(anchoredTo button: NSStatusBarButton) {
    let anchorWindow = button.window
    let screen = anchorWindow?.screen ?? NSApp.mainWindow?.screen ?? NSScreen.main
    guard let screen else { return }
    let attachedAnchor = anchorWindow.map {
      $0.convertToScreen(button.convert(button.bounds, to: nil))
    }
    let anchor = Self.anchor(attached: attachedAnchor, visibleFrame: screen.visibleFrame)
    let window = MenuDashboardWindow(
      contentRect: NSRect(origin: .zero, size: contentSize),
      styleMask: [.titled, .closable, .utilityWindow], backing: .buffered,
      defer: false)
    window.isReleasedWhenClosed = false
    window.title = "Aerie"
    window.isOpaque = true; window.backgroundColor = .windowBackgroundColor
    window.hasShadow = true; window.isFloatingPanel = true
    window.hidesOnDeactivate = false; window.level = .floating
    window.collectionBehavior = [.transient, .moveToActiveSpace]
    window.contentViewController = contentViewController
    window.delegate = self
    window.setFrameOrigin(
      Self.origin(anchor: anchor, visibleFrame: screen.visibleFrame, size: window.frame.size))
    panel = window
    onCreate?(window)
    deactivationObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didResignActiveNotification, object: NSApp, queue: .main
    ) { [weak self] _ in self?.performClose(nil) }
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
    onShow?(window)
  }
  deinit {
    if let deactivationObserver { NotificationCenter.default.removeObserver(deactivationObserver) }
  }
  static func anchor(attached: NSRect?, visibleFrame: NSRect) -> NSRect {
    // Hidden or overflowed status items have no window. Settings must still open the dashboard.
    attached ?? NSRect(x: visibleFrame.midX, y: visibleFrame.maxY, width: 0, height: 0)
  }
  func performClose(_ sender: Any?) { panel?.close() }
  func windowWillClose(_ notification: Notification) {
    guard let window = notification.object as? NSWindow, window === panel else { return }
    panel = nil; window.delegate = nil; Self.releaseContent(of: window)
    if let deactivationObserver { NotificationCenter.default.removeObserver(deactivationObserver) }
    deactivationObserver = nil
    onClose?()
  }
  static func releaseContent(of window: NSWindow) {
    // Clearing the controller alone can leave its view attached to an ordered-out native window.
    window.contentViewController = nil
    window.contentView = nil
  }
  static func origin(anchor: NSRect, visibleFrame: NSRect, size: NSSize) -> NSPoint {
    let margin: CGFloat = 8
    let minimumX = visibleFrame.minX + margin
    let maximumX = max(minimumX, visibleFrame.maxX - size.width - margin)
    let minimumY = visibleFrame.minY + margin
    let maximumY = max(minimumY, visibleFrame.maxY - size.height - margin)
    return NSPoint(
      x: min(maximumX, max(minimumX, anchor.midX - size.width / 2)),
      y: min(maximumY, max(minimumY, anchor.minY - size.height - margin)))
  }
}
