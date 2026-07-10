// swift-tools-version: 5.7

import PackageDescription

let package = Package(
  name: "swift-async-algorithms",
  platforms: [
    .macOS("10.15"),
    .iOS("13.0"),
    .tvOS("13.0"),
    .watchOS("6.0"),
  ],
  products: [
    .library(name: "AsyncAlgorithms", targets: ["AsyncAlgorithms"]),
    .library(name: "AsyncSequenceValidation", targets: ["AsyncSequenceValidation"]),
    .library(name: "_CAsyncSequenceValidationSupport", type: .static, targets: ["AsyncSequenceValidation"]),
    .library(name: "AsyncAlgorithms_XCTest", targets: ["AsyncAlgorithms_XCTest"]),
  ],
  dependencies: [
    .package(path: "../swift-collections"),
  ],
  targets: [
    .target(
      name: "AsyncAlgorithms",
      dependencies: [.product(name: "Collections", package: "swift-collections")]
    ),
    .target(
      name: "AsyncSequenceValidation",
      dependencies: ["_CAsyncSequenceValidationSupport", "AsyncAlgorithms"]
    ),
    .systemLibrary(name: "_CAsyncSequenceValidationSupport"),
    .target(
      name: "AsyncAlgorithms_XCTest",
      dependencies: ["AsyncAlgorithms", "AsyncSequenceValidation"]
    ),
  ]
)
