// swift-tools-version:5.9

import PackageDescription

// Swift replacement for the upstream Objective-C DateUtils island: Linux Swift
// cannot import Objective-C modules, so app sources that `import DateUtils`
// compile against this overlay instead.
let package = Package(
    name: "DateUtils",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(name: "DateUtils", targets: ["DateUtils"])
    ],
    targets: [
        .target(name: "DateUtils", path: "QuillDateUtilsSources")
    ]
)
