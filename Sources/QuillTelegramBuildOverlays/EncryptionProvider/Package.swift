// swift-tools-version:5.9

import PackageDescription

let package = Package(
    name: "EncryptionProvider",
    products: [
        .library(name: "EncryptionProvider", targets: ["EncryptionProvider"])
    ],
    targets: [
        .target(name: "EncryptionProvider", path: "QuillEncryptionProviderSources")
    ]
)
