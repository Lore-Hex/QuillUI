// swift-tools-version:5.9

import PackageDescription

// Swift replacement for the upstream Objective-C OpenSSLEncryptionProvider
// island: Linux Swift cannot import Objective-C modules, so Telegram-Mac's
// `import OpenSSLEncryption` compiles against this overlay, which fronts the
// EncryptionProvider overlay's Swift implementation.
let package = Package(
    name: "OpenSSLEncryption",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(name: "OpenSSLEncryption", targets: ["OpenSSLEncryption"])
    ],
    dependencies: [
        .package(name: "EncryptionProvider", path: "../EncryptionProvider")
    ],
    targets: [
        .target(
            name: "OpenSSLEncryption",
            dependencies: [
                .product(name: "EncryptionProvider", package: "EncryptionProvider")
            ],
            path: "QuillOpenSSLEncryptionSources"
        )
    ]
)
