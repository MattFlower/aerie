import AppKit
import XCTest
@testable import AerieApp

final class MenuRendererTests: XCTestCase {
  func testNativeTwoLineImageDrawsBoundedDimensionsAndUsesAutomaticOrCustomColor() async throws {
    try await MainActor.run {
      _ = NSApplication.shared
      let normal = MenuRenderer.stacked("CPU 20%", "U 10% S 10%", color: nil)
      XCTAssertTrue(normal.isTemplate); XCTAssertEqual(normal.size.height, 20)
      let tinted = MenuRenderer.stacked(
        String(repeating: "Synthetic ", count: 1000), "Memory 40%",
        color: MenuRenderer.color("#123ABC"))
      XCTAssertFalse(tinted.isTemplate); XCTAssertLessThanOrEqual(tinted.size.width, 360)
      let bitmap = try XCTUnwrap(
        NSBitmapImageRep(
          bitmapDataPlanes: nil, pixelsWide: Int(tinted.size.width), pixelsHigh: 20,
          bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
          colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
      NSGraphicsContext.saveGraphicsState(); defer { NSGraphicsContext.restoreGraphicsState() }
      NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
      tinted.draw(in: NSRect(origin: .zero, size: tinted.size))
      let visible = (0..<bitmap.pixelsWide).contains { x in
        (0..<20).contains { bitmap.colorAt(x: x, y: $0)?.alphaComponent ?? 0 > 0 }
      }
      XCTAssertTrue(visible)
      XCTAssertNil(MenuRenderer.color("invalid"))
    }
  }
}
