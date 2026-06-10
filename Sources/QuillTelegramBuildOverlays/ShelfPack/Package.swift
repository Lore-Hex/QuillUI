// swift-tools-version:5.9

import PackageDescription

let package = Package(
    name: "ShelfPack",
    products: [
        .library(name: "ShelfPack", targets: ["ShelfPack"])
    ],
    targets: [
        .target(name: "ShelfPack", path: "QuillShelfPackSources")
    ]
)
