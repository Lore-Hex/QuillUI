// swift-tools-version:5.5

import PackageDescription

let package = Package(
    name: "GZIP",
    products: [
        .library(name: "GZIP", targets: ["GZIP"]),
    ],
    targets: [
        .target(
            name: "CGZIP",
            path: "Sources/GZIP",
            publicHeadersPath: "."
        ),
        .target(
            name: "GZIP",
            dependencies: ["CGZIP"],
            path: "Sources/QuillGZIP"
        ),
    ]
)
