// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "ObjcUtils",
    products: [
        .library(name: "ObjcUtils", targets: ["ObjcUtils"]),
        .library(name: "ObjcUtilsObjC", targets: ["ObjcUtilsObjC"]),
    ],
    dependencies: [
    ],
    targets: [
        .target(
            name: "ObjcUtils",
            dependencies: [],
            path: "Sources/ObjcUtilsSwift"
        ),
        .target(
            name: "ObjcUtilsObjC",
            dependencies: [],
            path: ".",
            exclude: ["Package.swift", "Sources/ObjcUtilsSwift"],
            publicHeadersPath: "Sources/ObjcUtils"
        ),
    ]
)
