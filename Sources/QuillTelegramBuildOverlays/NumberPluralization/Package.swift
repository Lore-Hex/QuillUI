// swift-tools-version:5.5

import PackageDescription

let package = Package(
    name: "NumberPluralization",
    products: [
        .library(name: "NumberPluralization", targets: ["NumberPluralization"]),
    ],
    targets: [
        .target(
            name: "NumberPluralization",
            dependencies: [],
            path: "Sources/QuillNumberPluralization"
        ),
    ]
)
