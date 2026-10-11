import AppKit

final class WeatherDetailWindow: NSWindowController, NSWindowDelegate {
  var onClose: (() -> Void)?
  private let text = NSTextView()
  init(title: String, message: String) {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 600, height: 540),
      styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    window.title = title; window.isReleasedWhenClosed = false
    super.init(window: window); window.delegate = self
    let scroll = NSScrollView(frame: window.contentView!.bounds)
    scroll.autoresizingMask = [.width, .height]; scroll.hasVerticalScroller = true
    text.frame = scroll.bounds; text.isEditable = false; text.isSelectable = true
    text.isRichText = false; text.font = .systemFont(ofSize: 13); text.string = message
    text.textContainerInset = NSSize(width: 16, height: 16)
    text.isVerticallyResizable = true; text.autoresizingMask = [.width]
    text.textContainer?.widthTracksTextView = true;
    text.textContainer?.containerSize = NSSize(
      width: scroll.bounds.width, height: .greatestFiniteMagnitude)
    text.setAccessibilityLabel(title + " details")
    scroll.documentView = text; window.contentView?.addSubview(scroll); window.center()
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  func windowWillClose(_ notification: Notification) { text.string = ""; onClose?() }
}
