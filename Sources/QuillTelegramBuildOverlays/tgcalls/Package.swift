// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "TgVoipWebrtc",
    products: [
        .library(name: "TgVoipWebrtc", targets: ["TgVoipWebrtc"]),
    ],
    dependencies: [
    ],
    targets: [
        .target(
            name: "TgVoipWebrtc",
            dependencies: [],
            path: "Sources/TgVoipWebrtc"
        ),
    ]
)
