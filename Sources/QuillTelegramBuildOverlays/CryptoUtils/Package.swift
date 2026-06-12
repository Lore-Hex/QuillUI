// swift-tools-version:5.9

import PackageDescription

let package = Package(
    name: "CryptoUtils",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(name: "CryptoUtils", targets: ["CryptoUtils", "CryptoUtilsObjCHeaders"]),
    ],
    targets: [
        .target(
            name: "CryptoUtils",
            path: "QuillCryptoUtilsSources",
            linkerSettings: [.linkedLibrary("crypto")]
        ),
        // Re-exports the upstream <CryptoUtils/Crypto.h> Objective-C header for
        // dependents like BuildConfig; the header itself is materialized into
        // ObjCHeaders/include by the generated package check so the upstream
        // checkout stays untouched and unvendored.
        .target(
            name: "CryptoUtilsObjCHeaders",
            path: "ObjCHeaders",
            publicHeadersPath: "include"
        ),
    ]
)
