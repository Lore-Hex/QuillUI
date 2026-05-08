// swift-tools-version: 6.0

import PackageDescription

var products: [Product] = [
    .library(name: "QuillUI", targets: ["QuillUI"]),
    .library(name: "QuillData", targets: ["QuillData"]),
    .library(name: "QuillKit", targets: ["QuillKit"]),
    .executable(name: "quill-enchanted", targets: ["QuillEnchanted"]),
    .executable(name: "quill-enchanted-upstream-slice", targets: ["QuillEnchantedUpstreamSlice"])
]

var targets: [Target] = [
    .systemLibrary(
        name: "CSQLite",
        pkgConfig: "sqlite3",
        providers: [
            .apt(["libsqlite3-dev"]),
            .brew(["sqlite"])
        ]
    ),
    .target(
        name: "QuillUI",
        dependencies: [
            "QuillKit",
            .product(name: "SwiftOpenUI", package: "SwiftOpenUI")
        ]
    ),
    .target(
        name: "QuillData",
        dependencies: [
            "CSQLite"
        ]
    ),
    .target(
        name: "QuillKit",
        dependencies: []
    ),
    .target(
        name: "QuillEnchantedCore",
        dependencies: [
            "QuillUI",
            "QuillData",
            "CSQLite"
        ]
    ),
    .testTarget(
        name: "QuillEnchantedTests",
        dependencies: [
            "QuillEnchantedCore"
        ]
    ),
    .testTarget(
        name: "QuillDataTests",
        dependencies: [
            "QuillData"
        ]
    ),
    .testTarget(
        name: "QuillKitTests",
        dependencies: [
            "QuillKit"
        ]
    ),
    .testTarget(
        name: "QuillParityTests",
        dependencies: [
            "QuillUI",
            "QuillKit",
            "QuillData"
        ]
    )
]

#if os(Linux)
let linuxCompatibilityModuleTargets: [Target] = [
    .target(name: "SwiftUI", dependencies: ["QuillUI"]),
    .target(name: "SwiftData", dependencies: ["QuillData"]),
    .target(name: "UniformTypeIdentifiers", dependencies: ["QuillUI"]),
    .target(
        name: "Combine",
        dependencies: [
            .product(name: "OpenCombine", package: "OpenCombine"),
            .product(name: "OpenCombineFoundation", package: "OpenCombine"),
            .product(name: "OpenCombineDispatch", package: "OpenCombine")
        ]
    ),
    .target(name: "ActivityIndicatorView", dependencies: ["SwiftUI"]),
    .target(name: "MarkdownUI", dependencies: ["SwiftUI"]),
    .target(name: "Splash", dependencies: ["SwiftUI"]),
    .target(name: "OllamaKit", dependencies: ["Combine"]),
    .target(name: "AsyncAlgorithms", dependencies: []),
    .target(name: "Carbon", dependencies: []),
    .systemLibrary(name: "IOKit"),
    .target(name: "WrappingHStack", dependencies: ["SwiftUI"]),
    .target(name: "Vortex", dependencies: ["SwiftUI"]),
    .target(name: "KeyboardShortcuts", dependencies: ["SwiftUI", "QuillKit"]),
    .target(name: "Magnet", dependencies: ["AppKit", "QuillKit"]),
    .target(name: "AVFoundation", dependencies: ["QuillKit"]),
    .target(name: "Speech", dependencies: ["AVFoundation"]),
    .target(name: "AppKit", dependencies: ["QuillUI", "QuillKit"]),
    .target(name: "UIKit", dependencies: ["QuillKit"]),
    .target(name: "PhotosUI", dependencies: ["SwiftUI"]),
    .target(name: "Security", dependencies: ["QuillKit"]),
    .target(name: "ServiceManagement", dependencies: ["QuillKit"]),
    .target(name: "Sparkle", dependencies: ["Combine", "QuillKit"]),
    .target(name: "ApplicationServices", dependencies: ["QuillKit"]),
    .target(name: "CoreGraphics", dependencies: ["QuillKit"]),
    .target(name: "Alamofire", dependencies: ["Security", "QuillKit"]),
    .target(name: "os", dependencies: ["QuillKit"]),
    .testTarget(
        name: "QuillCompatibilityModuleTests",
        dependencies: [
            "SwiftUI",
            "SwiftData",
            "Combine",
            "ActivityIndicatorView",
            "MarkdownUI",
            "Splash",
            "OllamaKit",
            "AsyncAlgorithms",
            "Carbon",
            "IOKit",
            "WrappingHStack",
            "Vortex",
            "KeyboardShortcuts",
            "Magnet",
            "AVFoundation",
            "Speech",
            "AppKit",
            "UIKit",
            "PhotosUI",
            "Security",
            "ServiceManagement",
            "Sparkle",
            "ApplicationServices",
            "CoreGraphics",
            "Alamofire",
            "os"
        ]
    )
]

let linuxCompatibilityModuleNames = [
    "SwiftUI",
    "SwiftData",
    "UniformTypeIdentifiers",
    "Combine",
    "ActivityIndicatorView",
    "MarkdownUI",
    "Splash",
    "OllamaKit",
    "AsyncAlgorithms",
    "Carbon",
    "IOKit",
    "WrappingHStack",
    "Vortex",
    "KeyboardShortcuts",
    "Magnet",
    "AVFoundation",
    "Speech",
    "AppKit",
    "UIKit",
    "PhotosUI",
    "Security",
    "ServiceManagement",
    "Sparkle",
    "ApplicationServices",
    "CoreGraphics",
    "Alamofire",
    "os"
]

products += linuxCompatibilityModuleNames.map { .library(name: $0, targets: [$0]) }

targets += linuxCompatibilityModuleTargets
targets += [
    .executableTarget(
        name: "QuillEnchanted",
        dependencies: [
            "QuillEnchantedCore",
            .product(name: "BackendGTK4", package: "SwiftOpenUI")
        ]
    ),
    .executableTarget(
        name: "QuillEnchantedUpstreamSlice",
        dependencies: [
            "QuillEnchantedCore",
            "QuillUI",
            "UniformTypeIdentifiers",
            .product(name: "BackendGTK4", package: "SwiftOpenUI")
        ]
    )
]
#else
targets += [
    .executableTarget(
        name: "QuillEnchanted",
        dependencies: [
            "QuillEnchantedCore"
        ]
    ),
    .executableTarget(
        name: "QuillEnchantedUpstreamSlice",
        dependencies: [
            "QuillEnchantedCore",
            "QuillUI"
        ]
    )
]
#endif

var packageDependencies: [Package.Dependency] = [
    .package(url: "https://github.com/codelynx/SwiftOpenUI", revision: "6150b964a7cb1cf3a961770f6947ed55c1a31433")
]

#if os(Linux)
packageDependencies.append(
    .package(url: "https://github.com/OpenCombine/OpenCombine.git", from: "0.14.0")
)
#endif

let package = Package(
    name: "QuillUI",
    platforms: [
        .macOS(.v14)
    ],
    products: products,
    dependencies: packageDependencies,
    targets: targets
)
