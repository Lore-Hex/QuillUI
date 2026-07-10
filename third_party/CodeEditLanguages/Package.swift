// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "CodeEditLanguages",
    platforms: [.macOS(.v13)],
    products: [
        .library(
            name: "CodeEditLanguages",
            targets: ["CodeEditLanguages"]
        )],
    dependencies: [
        .package(path: "../SwiftTreeSitter")],
    targets: [
        .target(
            name: "CodeEditLanguages",
            dependencies: ["SwiftTreeSitter"],
            resources: [
                .copy("Resources")
            ],
            linkerSettings: [.linkedLibrary("c++")]
        )]
)
