// swift-tools-version: 6.0.0

import PackageDescription

let package = Package(
    name: "WelcomeWindow",
    platforms: [.macOS(.v13)],
    products: [
        .library(
            name: "WelcomeWindow",
            targets: ["WelcomeWindow"]
        )
    ],
    targets: [
        .target(name: "WelcomeWindow")
    ]
)
