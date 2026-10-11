import AerieCore
import AppKit

/// Native two-line status images; dimensions and source text stay bounded.
enum MenuRenderer {
  static func color(_ hex: String?) -> NSColor? {
    guard let rgb = MenuColor.rgb(hex) else { return nil }
    return NSColor(
      srgbRed: Double((rgb >> 16) & 255) / 255, green: Double((rgb >> 8) & 255) / 255,
      blue: Double(rgb & 255) / 255, alpha: 1)
  }
  static func stacked(_ first: String, _ second: String, color: NSColor?) -> NSImage {
    let font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium)
    let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center;
    paragraph.lineBreakMode = .byTruncatingTail
    let attributes: [NSAttributedString.Key: Any] = [
      .font: font, .foregroundColor: color ?? NSColor.labelColor, .paragraphStyle: paragraph,
    ]
    let lines = [String(first.prefix(1536)), String(second.prefix(1536))]
    let width = min(
      360,
      max(
        18,
        ceil(lines.map { ($0 as NSString).size(withAttributes: attributes).width }.max() ?? 18) + 4)
    )
    let image = NSImage(size: NSSize(width: width, height: 20), flipped: true) { rect in
      NSBezierPath(rect: rect).addClip()
      for (index, line) in lines.enumerated() {
        (line as NSString).draw(
          in: NSRect(x: 2, y: CGFloat(index) * 10 - 0.5, width: width - 4, height: 11),
          withAttributes: attributes)
      }
      return true
    }
    image.isTemplate = color == nil; return image
  }
}
