// swift-tools-version: 6.0

import CompilerPluginSupport
import PackageDescription

var products: [Product] = [
    .library(name: "QuillUI", targets: ["QuillUI"]),
    .library(name: "QuillData", targets: ["QuillData"]),
    .library(name: "QuillKit", targets: ["QuillKit"]),
    .executable(name: "quill-wireguard", targets: ["QuillWireGuard"]),
    .executable(name: "quill-enchanted", targets: ["QuillEnchanted"]),
    .executable(name: "quill-enchanted-upstream-slice", targets: ["QuillEnchantedUpstreamSlice"])
]

#if os(Linux)
let quillUIDependencies: [Target.Dependency] = [
    "QuillKit",
    .product(name: "SwiftOpenUI", package: "SwiftOpenUI"),
    "CGdkPixbuf",
    .product(name: "CGTK", package: "SwiftOpenUI"),
    .product(name: "BackendGTK4", package: "SwiftOpenUI")
]
#else
let quillUIDependencies: [Target.Dependency] = [
    "QuillKit",
    .product(name: "SwiftOpenUI", package: "SwiftOpenUI")
]
#endif

var targets: [Target] = [
    .systemLibrary(
        name: "CSQLite",
        pkgConfig: "sqlite3",
        providers: [
            .apt(["libsqlite3-dev"]),
            .brew(["sqlite"])
        ]
    ),
    .systemLibrary(
        name: "CGdkPixbuf",
        path: "Sources/CGdkPixbuf",
        pkgConfig: "gdk-pixbuf-2.0",
        providers: [
            .apt(["libgdk-pixbuf-2.0-dev"])
        ]
    ),
    .target(
        name: "QuillUI",
        dependencies: quillUIDependencies
    ),
    .target(
        name: "QuillData",
        dependencies: [
            "CSQLite",
            "QuillDataMacros",
            .product(name: "SQLiteData", package: "sqlite-data"),
            .product(name: "GRDB", package: "GRDB.swift")
        ]
    ),
    .macro(
        name: "QuillDataMacros",
        dependencies: [
            .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
            .product(name: "SwiftCompilerPlugin", package: "swift-syntax")
        ]
    ),
    .target(
        name: "QuillKit",
        dependencies: []
    ),
    .target(
        name: "QuillWireGuardCore",
        dependencies: [
            "QuillUI",
            "QuillData"
        ] + ( {
            #if os(Linux)
            return []
            #else
            return ["WireGuardKit"]
            #endif
        }() ),
        path: "Sources/QuillWireGuardCore"
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
    ),
    .testTarget(
        name: "QuillPredicateTranslationTests",
        dependencies: [
            "QuillData",
            .product(name: "SQLiteData", package: "sqlite-data")
        ]
    )
]

#if os(Linux)
products.append(.executable(name: "quill-gtk-interaction-smoke", targets: ["QuillGtkInteractionSmoke"]))

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
        ],
        path: "Sources/Combine",
        sources: ["Combine.swift"]
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
    .target(name: "QuillUIKit", dependencies: ["QuillKit"]),
    .target(name: "UIKit", dependencies: ["QuillUIKit"]),
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
            "QuillUIKit",
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
    "QuillUIKit",
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
        name: "QuillWireGuard",
        dependencies: [
            "QuillWireGuardCore",
            .product(name: "BackendGTK4", package: "SwiftOpenUI")
        ]
    ),
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
    ),
    .executableTarget(
        name: "QuillGtkInteractionSmoke",
        dependencies: [
            "QuillUI",
            .product(name: "BackendGTK4", package: "SwiftOpenUI")
        ]
    )
]
#else
targets += [
    .target(
        name: "WireGuardKit",
        path: ".upstream/wireguard-apple/Sources/WireGuardKit"
    ),
    .executableTarget(
        name: "QuillWireGuard",
        dependencies: [
            "QuillWireGuardCore"
        ]
    ),
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
    .package(url: "https://github.com/codelynx/SwiftOpenUI", revision: "6150b964a7cb1cf3a961770f6947ed55c1a31433"),
    .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "600.0.0"),
    .package(url: "https://github.com/pointfreeco/sqlite-data", from: "1.0.0"),
    .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0")
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
