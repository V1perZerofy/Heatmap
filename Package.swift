// swift-tools-version: 6.0

import PackageDescription

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
        .target(name: "Heatmap", dependencies: ["Shared"]),
        .target(name: "HeatmapWidget", dependencies: ["Shared"]),
    ],
    swiftLanguageModes: [.v5]
)
