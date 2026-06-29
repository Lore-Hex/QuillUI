// swift-tools-version: 5.8

import PackageDescription

let package = Package(
    name: "TextStory",
	platforms: [
		.macOS(.v10_15),
		.macCatalyst(.v13),
		.iOS(.v13),
		.tvOS(.v13),
	],
    products: [
        .library(name: "TextStory", targets: ["TextStory"])
    ],
    dependencies: [
        .package(path: "../Rearrange")
    ],
    targets: [
        .target(name: "Internal", exclude: ["TSYTextStorage.h", "TSYTextStorage.m"]),
        .target(name: "TextStory", dependencies: ["Internal", "Rearrange"])
    ]
)

let swiftSettings: [SwiftSetting] = [
    .enableExperimentalFeature("StrictConcurrency")
]

for target in package.targets {
    var settings = target.swiftSettings ?? []
    settings.append(contentsOf: swiftSettings)
    target.swiftSettings = settings
}
