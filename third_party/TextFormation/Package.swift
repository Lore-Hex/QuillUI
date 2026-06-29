// swift-tools-version: 5.8

import PackageDescription

let package = Package(
    name: "TextFormation",
    platforms: [
		.macOS(.v10_15),
		.macCatalyst(.v13),
		.iOS(.v13),
		.tvOS(.v13),
	],
    products: [
        .library(name: "TextFormation", targets: ["TextFormation"]),
    ],
    dependencies: [
		.package(path: "../TextStory")
    ],
    targets: [
        .target(name: "TextFormation", dependencies: ["TextStory"])
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
