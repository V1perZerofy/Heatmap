// swift-tools-version: 6.0

import PackageDescription

// xtool's Linux linker stamps the binary with the deployment target as its SDK version,
// so iOS 26+ runs the app in compatibility mode (no Liquid Glass). Record the real SDK version.
let sdkVersion: [LinkerSetting] = [
    .unsafeFlags(["-Xlinker", "-platform_version", "-Xlinker", "ios", "-Xlinker", "17.0", "-Xlinker", "26.0"]),
]

let package = Package(
    name: "Heatmap",
    platforms: [.iOS(.v17)],
    products: [
        // Main app
        .library(name: "Heatmap", targets: ["Heatmap"]),
        // Home screen widgets
        .library(name: "HeatmapWidget", targets: ["HeatmapWidget"]),
    ],
    targets: [
        .target(name: "Shared"),
        .target(name: "Heatmap", dependencies: ["Shared"], linkerSettings: sdkVersion),
        .target(name: "HeatmapWidget", dependencies: ["Shared"], linkerSettings: sdkVersion),
    ],
    swiftLanguageModes: [.v5]
)
