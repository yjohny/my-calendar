// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "TextCal",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "TextCalKit",
            targets: ["TextCalKit"]
        )
    ],
    targets: [
        // Core library (models, parsing, persistence, views) — testable
        .target(
            name: "TextCalKit",
            path: "Sources/TextCal",
            exclude: ["App/TextCalApp.swift"]
        ),
        .testTarget(
            name: "TextCalTests",
            dependencies: ["TextCalKit"],
            path: "Tests/TextCalTests"
        )
    ]
)
