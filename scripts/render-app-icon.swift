import AppKit
import Foundation

// Original Aerie artwork. Render from paths at each size, without external artwork or fonts.
let output = URL(
  fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Resources/AppIcon.iconset")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
  CGColor(srgbRed: red / 255, green: green / 255, blue: blue / 255, alpha: alpha)
}

func silhouette() -> CGPath {
  let path = CGMutablePath()
  // A rising wing, an alpine summit and an A share one silhouette.
  path.move(to: CGPoint(x: 185, y: 466))
  path.addCurve(
    to: CGPoint(x: 512, y: 260), control1: CGPoint(x: 330, y: 474),
    control2: CGPoint(x: 408, y: 393))
  path.addCurve(
    to: CGPoint(x: 839, y: 466), control1: CGPoint(x: 616, y: 393),
    control2: CGPoint(x: 694, y: 474))
  path.addCurve(
    to: CGPoint(x: 568, y: 597), control1: CGPoint(x: 769, y: 564),
    control2: CGPoint(x: 670, y: 612))
  path.addLine(to: CGPoint(x: 512, y: 718))
  path.addLine(to: CGPoint(x: 456, y: 597))
  path.addCurve(
    to: CGPoint(x: 185, y: 466), control1: CGPoint(x: 354, y: 612),
    control2: CGPoint(x: 255, y: 564))
  path.closeSubpath()
  return path
}

func render(_ pixels: Int) throws -> Data {
  guard
    let context = CGContext(
      data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
  else { throw CocoaError(.coderInvalidValue) }
  context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
  context.translateBy(x: 0, y: 1024)
  context.scaleBy(x: 1, y: -1)
  let tile = CGPath(
    roundedRect: CGRect(x: 64, y: 64, width: 896, height: 896),
    cornerWidth: 190, cornerHeight: 190, transform: nil)
  context.saveGState()
  context.setShadow(
    offset: CGSize(width: 0, height: 14), blur: 22,
    color: color(8, 18, 36, 0.3))
  context.addPath(tile)
  context.setFillColor(color(21, 45, 73))
  context.fillPath()
  context.restoreGState()
  context.saveGState()
  context.addPath(tile)
  context.clip()
  let sky = CGGradient(
    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
    colors: [color(62, 106, 151), color(29, 61, 101), color(16, 37, 64)] as CFArray,
    locations: [0, 0.5, 1])!
  context.drawLinearGradient(
    sky, start: CGPoint(x: 260, y: 64),
    end: CGPoint(x: 720, y: 960), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
  if pixels > 32 {
    context.addPath(
      CGPath(
        roundedRect: CGRect(x: 68, y: 68, width: 888, height: 888),
        cornerWidth: 186, cornerHeight: 186, transform: nil))
    context.setStrokeColor(color(183, 219, 239, 0.23))
    context.setLineWidth(4)
    context.strokePath()
  }
  context.saveGState()
  if pixels > 32 {
    context.setShadow(
      offset: CGSize(width: 0, height: 10), blur: 16,
      color: color(7, 22, 40, 0.35))
  }
  context.addPath(silhouette())
  context.setFillColor(color(239, 248, 247))
  context.fillPath()
  context.restoreGState()
  if pixels > 32 {
    context.saveGState()
    context.addPath(silhouette())
    context.clip()
    let fold = CGMutablePath()
    fold.move(to: CGPoint(x: 512, y: 260))
    fold.addLine(to: CGPoint(x: 512, y: 718))
    fold.addLine(to: CGPoint(x: 456, y: 597))
    fold.addCurve(
      to: CGPoint(x: 185, y: 466), control1: CGPoint(x: 354, y: 612),
      control2: CGPoint(x: 255, y: 564))
    fold.addCurve(
      to: CGPoint(x: 512, y: 260), control1: CGPoint(x: 330, y: 474),
      control2: CGPoint(x: 408, y: 393))
    fold.closeSubpath()
    context.addPath(fold)
    context.setFillColor(color(158, 218, 218))
    context.fillPath()
    context.restoreGState()
  }
  context.restoreGState()
  guard let image = context.makeImage(),
    let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
  else { throw CocoaError(.coderInvalidValue) }
  return data
}

for points in [16, 32, 128, 256, 512] {
  for scale in [1, 2] {
    let suffix = scale == 2 ? "@2x" : ""
    let file = output.appendingPathComponent("icon_\(points)x\(points)\(suffix).png")
    try render(points * scale).write(to: file, options: .atomic)
  }
}
print("Rendered ten original Aerie icon representations.")
