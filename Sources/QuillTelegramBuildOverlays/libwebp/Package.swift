// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "libwebp",
    platforms: [.macOS(.v10_15)],
    products: [
        .library(name: "libwebp", targets: ["libwebp"])
    ],
    dependencies: [
    ],
    targets: [
        .target(
            name: "libwebp",
            dependencies: [],
            path: "QuillWebPBindingSources"
        )
    ]
)
