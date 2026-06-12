// swift-tools-version:5.9

import PackageDescription

let package = Package(
    name: "MtProtoKit",
    products: [
        .library(name: "MtProtoKit", targets: ["MtProtoKit"])
    ],
    dependencies: [
        .package(name: "EncryptionProvider", path: "../EncryptionProvider")
    ],
    targets: [
        .target(
            name: "MtProtoKit",
            dependencies: [.product(name: "EncryptionProvider", package: "EncryptionProvider")],
            path: "QuillMtProtoKitSources"
        )
    ]
)
