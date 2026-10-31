// swift-tools-version: 6.2

// Built with xtool (https://xtool.sh) via SwiftPM on Linux/WSL:
//     bash scripts/build_ipa.sh
import PackageDescription

let package = Package(
    name: "NicoPlayer",
    platforms: [
        .iOS(.v26),
    ],
    products: [
        // xtool expects exactly one library product, representing the app.
        .library(
            name: "NicoPlayer",
            targets: ["NicoPlayer"]
        ),
    ],
    dependencies: [
        // Kept as its own package so it builds and tests on Linux (`swift test`).
        .package(path: "NicoKit"),
    ],
    targets: [
        .target(
            name: "NicoPlayer",
            dependencies: ["NicoKit"],
            path: "NicoPlayer",
            exclude: ["Resources"],
            linkerSettings: [
                // xtool links with the deployment target as the SDK version, so
                // iOS would run the app with the pre-26 look (no Liquid Glass).
                // Record the SDK actually installed (Xcode 27.1). Update with the SDK.
                .unsafeFlags([
                    "-Xlinker", "-platform_version", "-Xlinker", "ios",
                    "-Xlinker", "26.0", "-Xlinker", "27.1",
                ]),
            ]
        ),
    ]
)
