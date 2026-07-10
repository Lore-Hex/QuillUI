// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "OllamaKit",
    platforms: [
        .iOS(.v13),
        .macOS(.v11),
        .macCatalyst(.v13)
    ],
    products: [
        .library(
            name: "OllamaKit",
            targets: ["OllamaKit"]),
    ],
    dependencies: [
        .package(path: "../Alamofire")
    ],
    targets: [
        .target(
            name: "OllamaKit",
            dependencies: ["Alamofire"]),
    ]
)
