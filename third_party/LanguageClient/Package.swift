// swift-tools-version: 5.9

import PackageDescription

let package = Package(
	name: "LanguageClient",
	platforms: [
		.macOS(.v11),
		.macCatalyst(.v14),
		.iOS(.v14),
		.tvOS(.v14),
		.watchOS(.v7)
	],
	products: [
		.library(
			name: "LanguageClient",
			targets: ["LanguageClient"]),
	],
	dependencies: [
		.package(path: "../LanguageServerProtocol"),
		.package(path: "../FSEventsWrapper"),
		.package(path: "../swift-glob"),
		.package(path: "../JSONRPC"),
		.package(path: "../ProcessEnv"),
		.package(path: "../Semaphore"),
		.package(path: "../Queue"),
	],
	targets: [
		.target(
			name: "LanguageClient",
			dependencies: [
				.product(name: "FSEventsWrapper", package: "FSEventsWrapper", condition: .when(platforms: [.macOS])),
				.product(name: "Glob", package: "swift-glob"),
				"JSONRPC",
				"LanguageServerProtocol",
				.product(name: "ProcessEnv", package: "ProcessEnv", condition: .when(platforms: [.macOS])),
				"Queue",
				"Semaphore",
			]
		)
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
