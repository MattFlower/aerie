import AppKit
import Foundation

// Read-only packaging validation; this does not launch Aerie or alter icon caches.
let app = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "dist/Aerie.app")
let infoData = try Data(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
let info = try PropertyListSerialization.propertyList(from: infoData, format: nil) as? [String: Any]
guard info?["CFBundleIconFile"] as? String == "AppIcon.icns",
  let image = NSImage(contentsOf: app.appendingPathComponent("Contents/Resources/AppIcon.icns"))
else { fatalError("The app icon is missing from the bundle.") }
let expected = [16, 32, 32, 64, 128, 256, 256, 512, 512, 1024]
let representations = image.representations
let actual = representations.map(\.pixelsWide).sorted()
guard actual == expected, representations.allSatisfy({ $0.pixelsWide == $0.pixelsHigh })
else { fatalError("The app icon lacks required macOS image representations.") }
print("Verified the packaged app icon and all ten native macOS resolutions.")
