// swift-tools-version: 6.2

// Niconico access layer: no UIKit/SwiftUI, so it builds and tests on Linux.
//     cd NicoKit && swift test
//     cd NicoKit && swift run nico sm9
import PackageDescription

let package = Package(
    name: "NicoKit",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
    ],
    products: [
        .library(name: "NicoKit", targets: ["NicoKit"]),
    ],
    targets: [
        .target(name: "NicoKit"),
        // Command-line check against the real API; not part of the app.
        .executableTarget(name: "nico", dependencies: ["NicoKit"]),
        .testTarget(
            name: "NicoKitTests",
            dependencies: ["NicoKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
