// swift-tools-version:5.9

import PackageDescription

let package = Package(
    name: "CryptoUtils",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(name: "CryptoUtils", targets: ["CryptoUtils"]),
    ],
    targets: [
        .target(
            name: "CryptoUtils",
            path: "QuillCryptoUtilsSources",
            linkerSettings: [.linkedLibrary("crypto")]
        ),
    ]
)
