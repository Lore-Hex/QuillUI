// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "OpusBinding",
    platforms: [.macOS(.v10_15)],
    products: [
        .library(name: "OpusBinding", targets: ["OpusBinding"])
    ],
    targets: [
        .target(
            name: "OpusBinding",
            path: "QuillOpusBindingSources"
        )
    ]
)
