// swift-tools-version: 5.8

import PackageDescription
import CompilerPluginSupport

// Availability Macros

let availabilityMacros: [SwiftSetting] = [
  .enableExperimentalFeature(
    "AvailabilityMacro=AsyncAlgorithms 1.0:macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0"
  ),
  .enableExperimentalFeature(
    "AvailabilityMacro=AsyncAlgorithms 1.1:macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0"
  ),
  .enableExperimentalFeature(
    "AvailabilityMacro=AsyncAlgorithms 1.2:macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0"
  ),
  .enableExperimentalFeature(
    "AvailabilityMacro=AsyncAlgorithms 1.3:macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0"
  ),
]

let package = Package(
  name: "swift-async-algorithms",
  products: [
    .library(name: "AsyncAlgorithms", targets: ["AsyncAlgorithms"])
  ],
  targets: [
    .target(
      name: "AsyncAlgorithms",
      dependencies: [
        .product(name: "OrderedCollections", package: "swift-collections"),
        .product(name: "DequeModule", package: "swift-collections"),
      ],
      swiftSettings: availabilityMacros + [
        .enableExperimentalFeature("StrictConcurrency=complete")
      ]
    ),
    .target(
      name: "AsyncSequenceValidation",
      dependencies: ["_CAsyncSequenceValidationSupport", "AsyncAlgorithms"],
      swiftSettings: availabilityMacros + [
        .enableExperimentalFeature("StrictConcurrency=complete")
      ]
    ),
    .systemLibrary(name: "_CAsyncSequenceValidationSupport"),
    .target(
      name: "AsyncAlgorithms_XCTest",
      dependencies: ["AsyncAlgorithms", "AsyncSequenceValidation"],
      swiftSettings: availabilityMacros + [
        .enableExperimentalFeature("StrictConcurrency=complete")
      ]
    ),
  ]
)

package.dependencies += [
  .package(path: "../swift-collections")
]
