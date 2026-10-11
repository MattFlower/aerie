// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "Aerie", platforms: [.macOS(.v14)],
  products: [
    .executable(name: "Aerie", targets: ["AerieApp"]),
    .executable(name: "AerieMeasure", targets: ["AerieMeasure"]),
  ],
  targets: [
    .target(name: "AerieCore"),
    .target(name: "AerieNative", linkerSettings: [.linkedFramework("IOKit")]),
    .executableTarget(
      name: "AerieApp", dependencies: ["AerieCore", "AerieNative"],
      linkerSettings: [
        .linkedFramework("AppKit"), .linkedFramework("CoreWLAN"),
        .linkedFramework("EventKit"), .linkedFramework("ServiceManagement"),
        .linkedFramework("DiskArbitration"),
      ]),
    .executableTarget(name: "AerieMeasure", dependencies: ["AerieCore", "AerieNative"]),
    .testTarget(name: "AerieCoreTests", dependencies: ["AerieCore"]),
    .testTarget(name: "AerieAppTests", dependencies: ["AerieApp", "AerieCore", "AerieNative"]),
  ])
