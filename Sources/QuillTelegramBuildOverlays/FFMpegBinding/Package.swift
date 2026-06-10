// swift-tools-version:5.9

import PackageDescription

let package = Package(
    name: "FFMpegBinding",
    products: [
        .library(name: "FFMpegBinding", targets: ["FFMpegBinding"])
    ],
    dependencies: [
    ],
    targets: [
        .target(
            name: "FFMpegBinding",
            dependencies: [],
            path: "QuillFFMpegBindingSources"
        )
    ]
)
