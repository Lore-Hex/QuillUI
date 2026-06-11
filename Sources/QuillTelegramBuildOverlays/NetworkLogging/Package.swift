// swift-tools-version:5.9

import PackageDescription

let package = Package(
    name: "NetworkLogging",
    products: [
        .library(name: "NetworkLogging", targets: ["NetworkLogging"])
    ],
    targets: [
        .target(name: "NetworkLogging", path: "QuillNetworkLoggingSources")
    ]
)
