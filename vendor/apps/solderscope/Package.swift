// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SolderScope",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "SolderScope",
            targets: ["SolderScope"]
        )
    ],
    targets: [
        .executableTarget(
            name: "SolderScope",
            path: "SolderScope"
        )
    ]
)
