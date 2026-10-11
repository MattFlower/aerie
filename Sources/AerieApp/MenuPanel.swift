import AppKit

private final class MenuDashboardWindow: NSPanel {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
  override func cancelOperation(_ sender: Any?) { close() }
}

/// An opaque, ordinary AppKit utility panel. The dashboard and every source keep their cadence.
final class MenuPanel: NSObject, NSWindowDelegate {
  var contentViewController: NSViewController?
  var contentSize = NSSize(width: 416, height: 620)
  var onClose: (() -> Void)?
  private var panel: MenuDashboardWindow?
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
      styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel], backing: .buffered,
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
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
  }
  static func anchor(attached: NSRect?, visibleFrame: NSRect) -> NSRect {
    // Hidden or overflowed status items have no window. Settings must still open the dashboard.
    attached ?? NSRect(x: visibleFrame.midX, y: visibleFrame.maxY, width: 0, height: 0)
  }
  func performClose(_ sender: Any?) { panel?.close() }
  func windowWillClose(_ notification: Notification) {
    guard let window = notification.object as? NSWindow, window === panel else { return }
    panel = nil; window.delegate = nil; window.contentViewController = nil
    onClose?()
  }
  func windowDidResignKey(_ notification: Notification) {
    guard let window = notification.object as? NSWindow, window === panel else { return }
    // Menu tracking may temporarily route events elsewhere within the same application.
    DispatchQueue.main.async { [weak self, weak window] in
      guard let self, let window, self.panel === window, !window.isKeyWindow,
        !NSApp.isActive
      else { return }
      self.performClose(nil)
    }
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
