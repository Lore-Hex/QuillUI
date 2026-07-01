// swift-tools-version:5.1
// The swift-tools-version declares the minimum version of Swift required to build this package.
import PackageDescription

let package = Package(
    name: "Magnet",
    platforms: [
      .macOS(.v10_13)
    ],
    products: [
        .library(
            name: "Magnet",
            targets: ["Magnet"]),
    ],
    dependencies: [
        .package(path: "../Sauce"),
    ],
    targets: [
        .target(
            name: "Magnet",
            dependencies: ["Sauce"],
            path: "Lib/Magnet"),
    ],
    swiftLanguageVersions: [.v5]
)
