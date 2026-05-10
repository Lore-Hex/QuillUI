// swift-tools-version: 6.0

import PackageDescription

var products: [Product] = [
    .library(name: "QuillUI", targets: ["QuillUI"]),
    .library(name: "QuillData", targets: ["QuillData"]),
    .library(name: "QuillKit", targets: ["QuillKit"]),
    .library(name: "QuillFoundation", targets: ["QuillFoundation"]),
    .library(name: "QuillRS", targets: ["QuillRS"]),
    .library(name: "QuillUIKit", targets: ["QuillUIKit"]),
    .library(name: "QuillWebKit", targets: ["QuillWebKit"]),
    .library(name: "QuillShims", targets: ["QuillShims"]),
    .executable(name: "quill-enchanted", targets: ["QuillEnchanted"]),
    .executable(name: "quill-enchanted-upstream-slice", targets: ["QuillEnchantedUpstreamSlice"])
]

#if os(Linux)
products.append(.executable(name: "quill-netnewswire", targets: ["QuillNetNewsWire"]))
#endif

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

let nnwSwiftSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v5),
    .unsafeFlags(["-strict-concurrency=minimal", "-Xfrontend", "-import-module", "-Xfrontend", "QuillShims", "-Xfrontend", "-disable-access-control"])
]

let standardSwiftSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v5),
    .unsafeFlags(["-strict-concurrency=minimal", "-Xfrontend", "-import-module", "-Xfrontend", "QuillShims"])
]

#if os(Linux)
let quillShimsDependencies: [Target.Dependency] = [
    "QuillKit", "QuillData", "os",
    "QuillFoundation", "QuillWebKit", "QuillUIKit", "QuillRS",
    "UIKit", "MessageUI", "SafariServices", "MobileCoreServices",
    "Zip", "Tidemark", "UniformTypeIdentifiers", "Network", "NetworkExtension"
]
#else
let quillShimsDependencies: [Target.Dependency] = [
    "QuillKit", "QuillData",
    "QuillFoundation", "QuillWebKit", "QuillUIKit", "QuillRS"
]
#endif

#if os(Linux)
let nnwLogicDependencies: [Target.Dependency] = [
    "RSCore", "Account", "Articles", "RSParser", "ArticlesDatabase",
    "RSWeb", "RSTree", "QuillShims", "os"
]
#else
let nnwLogicDependencies: [Target.Dependency] = [
    "RSCore", "Account", "Articles", "RSParser", "ArticlesDatabase",
    "RSWeb", "RSTree", "QuillShims"
]
#endif

// QuillWireGuard executable + core. On Linux they need the SwiftUI
// shim target since `import SwiftUI` doesn't resolve to Apple's
// SwiftUI (which doesn't ship on Linux).
#if os(Linux)
let quillWireGuardCoreDependencies: [Target.Dependency] = [
    "QuillUI", "QuillData", "WireGuardKit", "SwiftUI"
]
let quillWireGuardDependencies: [Target.Dependency] = ["QuillWireGuardCore", "SwiftUI"]
#else
let quillWireGuardCoreDependencies: [Target.Dependency] = [
    "QuillUI", "QuillData", "WireGuardKit"
]
let quillWireGuardDependencies: [Target.Dependency] = ["QuillWireGuardCore"]
#endif

// WireGuardKit deps + Linux-specific excludes.
#if os(Linux)
let wireGuardKitDependencies: [Target.Dependency] = ["WireGuardKitC", "Network", "NetworkExtension"]
let wireGuardKitExcludes: [String] = [
    "WireGuardAdapter.swift",
    // Upstream emits `#error("Unimplemented")` for these on non-iOS/
    // non-macOS — skipping them keeps the rest of WireGuardKit
    // compiling on Linux.
    "DNSResolver.swift",
    "PacketTunnelSettingsGenerator.swift",
    "IPAddress+AddrInfo.swift"
]
#else
let wireGuardKitDependencies: [Target.Dependency] = ["WireGuardKitC"]
let wireGuardKitExcludes: [String] = ["WireGuardAdapter.swift"]
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
    .target(
        name: "QuillUI",
        dependencies: quillUIDependencies
    ),
    .systemLibrary(
        name: "CGdkPixbuf",
        path: "Sources/CGdkPixbuf",
        pkgConfig: "gdk-pixbuf-2.0",
        providers: [
            .apt(["libgdk-pixbuf-2.0-dev"])
        ]
    ),
    // GTK4 system library — Phase B backing for NSWindow / NSApplication.
    // Wired only on Linux (the AppKit target depends on it conditionally
    // below). On macOS GTK4 isn't present and we don't need it (Apple's
    // real AppKit ships).
    .systemLibrary(
        name: "CGtk4",
        path: "Sources/CGtk4",
        pkgConfig: "gtk4",
        providers: [
            .apt(["libgtk-4-dev"])
        ]
    ),
    .target(
        name: "QuillData",
        dependencies: [
            "CSQLite",
            .product(name: "SQLiteData", package: "sqlite-data"),
            .product(name: "GRDB", package: "GRDB.swift")
        ]
    ),
    .target(
        name: "QuillKit",
        dependencies: []
    ),
    .target(
        name: "QuillFoundation",
        dependencies: [],
        path: "Sources/QuillFoundation"
    ),
    .target(
        name: "QuillWebKit",
        dependencies: ["QuillFoundation"],
        path: "Sources/QuillWebKit"
    ),
    .target(
        name: "QuillUIKit",
        dependencies: ["QuillFoundation"],
        path: "Sources/QuillUIKit"
    ),
    .target(
        name: "QuillRS",
        dependencies: ["QuillFoundation", "QuillData"],
        path: "Sources/QuillRS"
    ),
    .target(
        name: "QuillShims",
        dependencies: quillShimsDependencies
    ),
    .target(
        name: "RSCore",
        dependencies: ["RSCoreObjC", "QuillShims"],
        path: ".upstream/netnewswire/Modules/RSCore/Sources/RSCore",
        exclude: ["AppKit", "UIKit", "SendToBlogEditorApp.swift"],
        swiftSettings: nnwSwiftSettings
    ),
    .target(
        name: "RSCoreObjC",
        path: ".upstream/netnewswire/Modules/RSCore/Sources/RSCoreObjC"
    ),
    .target(
        name: "RSParser",
        dependencies: ["RSCore", "QuillShims", "Tidemark"],
        path: ".upstream/netnewswire/Modules/RSParser/Sources/RSParser",
        swiftSettings: standardSwiftSettings
    ),
    .target(
        name: "Articles",
        dependencies: ["RSCore", "QuillShims"],
        path: ".upstream/netnewswire/Modules/Articles/Sources/Articles",
        swiftSettings: nnwSwiftSettings
    ),
    .target(
        name: "Account",
        dependencies: ["RSCore", "Articles", "RSParser", "ArticlesDatabase", "RSWeb", "Secrets", "ErrorLog", "SyncDatabase", "CloudKitSync", "FeedFinder", "NewsBlur", "QuillShims"],
        path: ".upstream/netnewswire/Modules/Account/Sources/Account",
        swiftSettings: nnwSwiftSettings
    ),
    .target(
        name: "ArticlesDatabase",
        dependencies: ["RSCore", "RSParser", "Articles", "RSDatabase", "RSDatabaseObjC", "QuillShims"],
        path: ".upstream/netnewswire/Modules/ArticlesDatabase/Sources/ArticlesDatabase",
        swiftSettings: nnwSwiftSettings
    ),
    .target(
        name: "RSWeb",
        dependencies: ["RSParser", "RSCore", "QuillShims"],
        path: ".upstream/netnewswire/Modules/RSWeb/Sources/RSWeb",
        swiftSettings: nnwSwiftSettings
    ),
    .target(
        name: "ErrorLog",
        dependencies: ["RSCore", "RSDatabase", "RSDatabaseObjC", "QuillShims"],
        path: ".upstream/netnewswire/Modules/ErrorLog/Sources/ErrorLog",
        swiftSettings: nnwSwiftSettings
    ),
    .target(
        name: "SyncDatabase",
        dependencies: ["RSCore", "Articles", "RSDatabase", "RSDatabaseObjC", "QuillShims"],
        path: ".upstream/netnewswire/Modules/SyncDatabase/Sources/SyncDatabase",
        swiftSettings: nnwSwiftSettings
    ),
    .target(
        name: "CloudKitSync",
        dependencies: ["RSCore", "QuillShims"],
        path: ".upstream/netnewswire/Modules/CloudKitSync/Sources/CloudKitSync",
        swiftSettings: nnwSwiftSettings
    ),
    .target(
        name: "FeedFinder",
        dependencies: ["RSWeb", "RSParser", "RSCore", "QuillShims"],
        path: ".upstream/netnewswire/Modules/FeedFinder/Sources/FeedFinder",
        swiftSettings: nnwSwiftSettings
    ),
    .target(
        name: "NewsBlur",
        dependencies: ["RSWeb", "RSParser", "RSCore", "QuillShims"],
        path: ".upstream/netnewswire/Modules/NewsBlur/Sources/NewsBlur",
        swiftSettings: nnwSwiftSettings
    ),
    .target(
        name: "RSTree",
        dependencies: ["QuillShims"],
        path: "Sources/RSTree",
        swiftSettings: nnwSwiftSettings
    ),
    .target(
        name: "RSDatabase",
        dependencies: ["RSDatabaseObjC"],
        path: ".upstream/netnewswire/Modules/RSDatabase/Sources/RSDatabase",
        swiftSettings: [.swiftLanguageMode(.v5), .unsafeFlags(["-strict-concurrency=minimal"])]
    ),
    .target(
        name: "RSDatabaseObjC",
        path: ".upstream/netnewswire/Modules/RSDatabase/Sources/RSDatabaseObjC",
        publicHeadersPath: "include"
    ),
    // CYCLE-BREAK: these are deps of QuillShims (Linux block) so they
    // can't depend on QuillShims back. Their *.swift sources have been
    // updated to re-export QuillRS / QuillFoundation directly.
    .target(name: "Secrets", dependencies: ["QuillFoundation"], path: "Sources/SecretsShim"),
    .target(name: "Tidemark", dependencies: ["QuillRS"], path: "Sources/TidemarkShim"),
    .target(name: "Zip", dependencies: ["QuillRS"], path: "Sources/ZipShim"),
    .target(
        name: "WireGuardKitC",
        path: ".upstream/wireguard-apple/Sources/WireGuardKitC",
        publicHeadersPath: ".",
        // x25519.c includes <CommonCrypto/CommonRandom.h>. Sources/
        // CommonCryptoLinux/include provides a Linux-only header-only
        // shim that maps CCRandomGenerateBytes → getrandom(2). On macOS
        // Apple's real CommonCrypto wins via the SDK; this header
        // search path only fires on Linux. Zero modifications to
        // upstream wireguard-apple source.
        cSettings: [
            .headerSearchPath("../../../../Sources/CommonCryptoLinux/include",
                              .when(platforms: [.linux]))
        ]
    ),
    .target(
        name: "WireGuardKit",
        dependencies: wireGuardKitDependencies,
        path: ".upstream/wireguard-apple/Sources/WireGuardKit",
        // WireGuardAdapter.swift needs the Go bridge (not built here).
        // DNSResolver.swift / PacketTunnelSettingsGenerator.swift /
        // IPAddress+AddrInfo.swift are platform-gated to iOS/macOS by
        // upstream and emit `#error("Unimplemented")` on Linux. Exclude
        // them so the rest of WireGuardKit (keypair generation, config
        // parsing, IPv4/v6 helpers, the public API surface) compiles
        // unmodified on Linux.
        exclude: wireGuardKitExcludes,
        swiftSettings: [.swiftLanguageMode(.v5)]
    ),
    .target(
        name: "NetNewsWireLogic",
        dependencies: nnwLogicDependencies,
        path: ".upstream/netnewswire",
        exclude: ["Shared/ExtensionPoints/SendToMarsEditCommand.swift", "Shared/ExtensionPoints/SendToMicroBlogCommand.swift", "Shared/DefaultAccountNames.xcstrings", "Shared/Article Rendering/newsfoot.js", "Shared/Resources/Biblioteca.nnwtheme", "Shared/Resources/GlobalKeyboardShortcuts.plist", "Shared/Article Rendering/stylesheet.css", "Shared/Article Rendering/core.css", "Shared/Importers/DefaultFeeds.opml", "Shared/Resources/NewsFax.nnwtheme", "Shared/Resources/Sepia.nnwtheme", "Shared/Resources/Appanoose.nnwtheme", "Shared/Resources/SidebarKeyboardShortcuts.plist", "Shared/Resources/Tiqoe Dark.nnwtheme", "Shared/Article Rendering/main.js", "Shared/Resources/Promenade.nnwtheme", "Shared/Resources/Verdana Revival.nnwtheme", "Shared/ShareExtension/SafariExt.js", "Shared/Resources/DetailKeyboardShortcuts.plist", "Shared/Resources/Hyperlegible.nnwtheme", "Shared/Resources/ContentRules.json", "Shared/Article Rendering/template.html", "Shared/Resources/TimelineKeyboardShortcuts.plist", "Shared/Widget/WidgetDataEncoder.swift", "Shared/Widget/WidgetDeepLinks.swift", "iOS/NetNewsWire-iOS-Bridging-Header.h", "iOS/UIKit Extensions/SFSafariViewController+Extras.h", "iOS/UIKit Extensions/SFSafariViewController+Extras.m", "iOS/Resources/Assets.xcassets", "iOS/Resources/Thanks.rtf", "iOS/Resources/blank.html", "iOS/Resources/page.html", "iOS/Resources/NetNewsWire.entitlements", "iOS/Resources/Dedication.rtf", "iOS/IntentsExtension/NetNewsWire_iOS_IntentsExtension.entitlements", "iOS/Resources/Info.plist", "iOS/Resources/NetNewsWire-dev.entitlements", "iOS/Settings/SettingsTableViewCell.xib", "iOS/ShareExtension/NetNewsWire_iOS_ShareExtension.entitlements", "iOS/Add/AddFeedSelectFolderTableViewCell.xib", "iOS/Settings/Settings.storyboard", "iOS/ShareExtension/ShareFolderPickerAccountCell.xib", "iOS/Resources/main_ios.js", "iOS/Add/Add.storyboard", "iOS/Resources/About.rtf", "iOS/ShareExtension/Info.plist", "iOS/ShareExtension/ShareFolderPickerFolderCell.xib", "iOS/Inspector/Inspector.storyboard", "iOS/IntentsExtension/Info.plist", "iOS/Account/Account.storyboard", "iOS/Resources/Credits.rtf", "iOS/Settings/SettingsComboTableViewCell.xib", "iOS/IntentsExtension", "iOS/Widget", "iOS/ShareExtension", "iOS/Base.lproj", "iOS/Resources/PrivacyInfo.xcprivacy"],
        sources: ["Shared", "iOS"],
        swiftSettings: nnwSwiftSettings
    ),
    .executableTarget(
        name: "QuillNetNewsWire",
        dependencies: ["QuillUI", "NetNewsWireLogic", "QuillShims"],
        path: "Sources/QuillNetNewsWire",
        swiftSettings: nnwSwiftSettings
    ),
    // CYCLE-BREAK: same reasoning — re-export QuillFoundation/QuillUIKit.
    .target(name: "MessageUI", dependencies: ["QuillFoundation", "QuillUIKit"], path: "Sources/MessageUIShim"),
    .target(name: "SafariServices", dependencies: ["QuillFoundation", "QuillUIKit"], path: "Sources/SafariServicesShim"),
    .target(name: "MobileCoreServices", dependencies: ["QuillFoundation"], path: "Sources/MobileCoreServicesShim"),
    .target(name: "UIKit", dependencies: ["QuillFoundation", "QuillUIKit"], path: "Sources/UIKitShim"),
    .target(name: "SwiftData", dependencies: ["QuillData"], path: "Sources/SwiftData"),
    .target(
        name: "QuillEnchantedCore",
        dependencies: ["QuillUI", "QuillData", "CSQLite"]
    ),
    .executableTarget(
        name: "QuillEnchanted",
        dependencies: ["QuillEnchantedCore"]
    ),
    .executableTarget(
        name: "QuillEnchantedUpstreamSlice",
        dependencies: ["QuillEnchantedCore", "QuillUI"],
        // The slice's main.swift has a deeply-nested SwiftUI body that
        // trips Swift 6's per-expression type-check timeout (default
        // ~30s on macOS). Bump the threshold rather than restructure
        // the expression.
        swiftSettings: [
            .unsafeFlags(["-Xfrontend", "-solver-expression-time-threshold=600"])
        ]
    ),
    .target(
        name: "QuillWireGuardCore",
        dependencies: quillWireGuardCoreDependencies,
        path: "Sources/QuillWireGuardCore"
    ),
    .executableTarget(
        name: "QuillWireGuard",
        dependencies: quillWireGuardDependencies,
        path: "Sources/QuillWireGuard"
    ),
    // Asset Catalog Symbol Generation tool + build plugin. Generates
    // Color/UIColor/NSColor extensions for every .colorset in a target's
    // .xcassets (Xcode 15+ behavior, missing from SwiftPM).
    .executableTarget(
        name: "QuillAssetSymbolsTool",
        path: "Sources/QuillAssetSymbolsTool"
    ),
    .plugin(
        name: "QuillAssetSymbolsPlugin",
        capability: .buildTool(),
        dependencies: ["QuillAssetSymbolsTool"],
        path: "Plugins/QuillAssetSymbolsPlugin"
    ),
    // @main extraction tool + plugin: strips the `@main` attribute from
    // upstream entry-point files so their side declarations compile as
    // ordinary library code (used by EnchantedSupportShim).
    .executableTarget(
        name: "QuillMainExtractTool",
        path: "Sources/QuillMainExtractTool"
    ),
    .plugin(
        name: "QuillMainExtractPlugin",
        capability: .buildTool(),
        dependencies: ["QuillMainExtractTool"],
        path: "Plugins/QuillMainExtractPlugin"
    )
]

// CodeEdit upstream — macOS-only (it's a pure AppKit/SwiftUI Mac app
// using NSTextView, NSDocument, NSApplicationDelegateAdaptor, Sparkle,
// and a stack of CodeEditApp's own packages). The Linux path can't
// compile this without source modifications because so much of the
// surface is non-conditional AppKit.
#if !os(Linux)
targets += [
    .executableTarget(
        name: "CodeEditUpstream",
        // Keep CodeEditApp.swift (the @main entry point) — the
        // executable target uses upstream's own entry directly.
        dependencies: [
            .product(name: "CodeEditSymbols", package: "CodeEditSymbols"),
            .product(name: "CodeEditSourceEditor", package: "CodeEditSourceEditor"),
            .product(name: "CodeEditKit", package: "CodeEditKit"),
            .product(name: "AboutWindow", package: "AboutWindow"),
            .product(name: "WelcomeWindow", package: "WelcomeWindow"),
            .product(name: "LanguageClient", package: "LanguageClient"),
            .product(name: "LanguageServerProtocol", package: "LanguageServerProtocol"),
            .product(name: "ZIPFoundation", package: "ZIPFoundation"),
            .product(name: "Sparkle", package: "Sparkle"),
            .product(name: "LogStream", package: "LogStream"),
            .product(name: "Collections", package: "swift-collections"),
            .product(name: "CollectionConcurrencyKit", package: "collectionconcurrencykit"),
            .product(name: "SwiftUIIntrospect", package: "SwiftUI-Introspect"),
            .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
            .product(name: "SwiftTerm", package: "SwiftTerm"),
            .product(name: "GRDB", package: "GRDB.swift")
        ],
        path: ".upstream/codeedit/CodeEdit",
        exclude: [
            "Preview Content",
            "CodeEdit.entitlements",
            "Info.plist"
        ],
        // Re-include Assets.xcassets as a processed resource so the
        // QuillAssetSymbolsPlugin can scan it and emit Color/NSColor
        // extensions for upstream's `Color.amber` / `NSColor.folderBlue` /
        // etc. references (Xcode 15+ Asset Catalog Symbol Generation).
        resources: [.process("Assets.xcassets")],
        swiftSettings: [.swiftLanguageMode(.v5), .unsafeFlags(["-strict-concurrency=minimal"])],
        plugins: [.plugin(name: "QuillAssetSymbolsPlugin")]
    )
]
#endif

#if os(Linux)
// Linux-only shadow targets. Use canonical Apple framework names so
// upstream `import SwiftUI` / `import Network` / etc. resolves to
// these targets (SPM's swiftmodule filename follows the target name).
// Source dirs are *Shim-suffixed to avoid a directory naming clash
// with anything upstream might want to vendor.
targets.append(contentsOf: [
    .target(name: "os", dependencies: [], path: "Sources/osShim"),
    .target(name: "SwiftUI", dependencies: ["QuillUI"], path: "Sources/SwiftUIShim"),
    .target(name: "UniformTypeIdentifiers", dependencies: ["QuillUI"], path: "Sources/UniformTypeIdentifiersShim"),
    .target(name: "Network", dependencies: [], path: "Sources/NetworkShim"),
    .target(name: "NetworkExtension", dependencies: ["Network"], path: "Sources/NetworkExtensionShim"),
    // QuillAppKit — compile-only AppKit shadow. Target named `AppKit`
    // so upstream `import AppKit` resolves to this swiftmodule on
    // Linux. Phase A: type stubs only. Phase B will back the heavy
    // hitters (NSWindow, NSView, NSPasteboard, etc.) with GTK4.
    .target(name: "AppKit", dependencies: ["QuillFoundation", "QuillUIKit"], path: "Sources/QuillAppKit", exclude: ["QuillAppKit+GTK.swift"]),
    // GTK4-backed runtime for QuillAppKit. Separate target so the
    // bare AppKit module stays a clean shadow (no transitive CGtk4
    // dep visible to clients like swift-sharing's `canImport(AppKit)`
    // branch). Apps that want the runtime backing import QuillAppKitGTK.
    .target(name: "QuillAppKitGTK", dependencies: ["AppKit", "CGtk4"], path: "Sources/QuillAppKitGTK"),
    // Runtime demo: exercises NSPasteboard.general's Phase B backing
    // (Wayland / X11 / file-backed tier) end-to-end. Writes a string,
    // reads it back, asserts the round-trip succeeded. Linux-only —
    // on macOS the real NSPasteboard works without any QuillAppKit
    // shim, so the demo target is unnecessary there.
    .executableTarget(
        name: "QuillAppKitPasteboardDemo",
        dependencies: ["AppKit", "QuillAppKitGTK"],
        path: "Sources/QuillAppKitPasteboardDemo"
    ),
    // Smoke test for QuillAppKit. Exercises realistic AppKit usage
    // (NSWindowController, NSViewController, NSOutlineViewDelegate,
    // NSStatusItem, NSPasteboard, NSApplicationDelegate) so that
    // missing types surface as compile errors here before they land
    // in a real upstream app.
    .target(name: "QuillAppKitSmoke", dependencies: ["AppKit"], path: "Sources/QuillAppKitSmoke"),
    // Linux-only target that compiles a hand-picked set of real
    // CodeEdit upstream files (the ones that import AppKit only,
    // with no dependency on Sparkle/CodeEditSourceEditor/SwiftUI/etc.)
    // to prove QuillAppKit's surface is sufficient for production
    // Mac code with zero source modifications.
    .target(
        name: "CodeEditAppKitSlice",
        dependencies: ["AppKit"],
        path: ".upstream/codeedit/CodeEdit",
        sources: [
            // AppKit-specific extensions
            "Utils/Extensions/NSWindow/NSWindow+Child.swift",
            "Features/SplitView/Model/CodeEditDividerStyle.swift",
            // Pure-Foundation utilities (compile against any platform)
            "Utils/Extensions/Collection/Collection+subscript_safe.swift",
            "Utils/Extensions/Array/Array+Index.swift",
            "Utils/Extensions/URL/URL+absolutePath.swift",
            "Utils/Extensions/URL/URL+Filename.swift",
            "Utils/Extensions/URL/URL+Identifiable.swift",
            // Stand-alone CodeEdit type
            "SceneID.swift"
        ],
        swiftSettings: [.swiftLanguageMode(.v5)]
    )
])
#endif

// CodeEdit's SPM deps. macOS-only — Sparkle is Apple-platform auto-update,
// CodeEditSourceEditor uses NSTextView, AboutWindow uses NSApplication,
// etc. On Linux the upstream CodeEdit source itself can't compile (it's a
// pure AppKit/SwiftUI Mac app) so we only resolve these on macOS.
var allPackageDependencies: [Package.Dependency] = [
    .package(url: "https://github.com/codelynx/SwiftOpenUI", revision: "6150b964a7cb1cf3a961770f6947ed55c1a31433"),
    .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "600.0.0"),
    .package(url: "https://github.com/pointfreeco/sqlite-data", from: "1.0.0"),
    .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0")
]
#if !os(Linux)
allPackageDependencies += [
    // CodeEditSymbols 0.2.3's upstream Package.swift never declares
    // `Symbols.xcassets` as a resource — Bundle.module is undefined
    // under SwiftPM. Locally-vendored copy at .upstream/codeeditsymbols
    // adds the missing `resources: [.process("Symbols.xcassets")]` line.
    .package(name: "CodeEditSymbols", path: ".upstream/codeeditsymbols"),
    .package(url: "https://github.com/CodeEditApp/CodeEditSourceEditor", exact: "0.15.1"),
    .package(url: "https://github.com/CodeEditApp/CodeEditKit", exact: "0.1.2"),
    .package(url: "https://github.com/CodeEditApp/AboutWindow", from: "1.0.0"),
    .package(url: "https://github.com/CodeEditApp/WelcomeWindow", from: "1.0.0"),
    .package(url: "https://github.com/ChimeHQ/LanguageClient", from: "0.8.0"),
    .package(url: "https://github.com/ChimeHQ/LanguageServerProtocol", from: "0.13.0"),
    .package(url: "https://github.com/weichsel/ZIPFoundation", from: "0.9.19"),
    .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.0.0"),
    .package(url: "https://github.com/Wouter01/LogStream", from: "1.3.0"),
    .package(url: "https://github.com/apple/swift-collections.git", from: "1.0.0"),
    .package(url: "https://github.com/johnsundell/collectionconcurrencykit", from: "0.2.0"),
    .package(url: "https://github.com/siteline/SwiftUI-Introspect.git", from: "1.0.0"),
    .package(url: "https://github.com/apple/swift-async-algorithms", from: "1.0.0"),
    // CodeEdit uses thecoolwinter's SwiftTerm fork (branch `codeedit`)
    // because it preserves the older `selectedPositions()` API the
    // upstream main has since renamed.
    .package(url: "https://github.com/thecoolwinter/SwiftTerm", branch: "codeedit")
]
#endif

let package = Package(
    name: "QuillUI",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: products,
    dependencies: allPackageDependencies,
    targets: targets + [
        .testTarget(name: "QuillShimsTests", dependencies: ["QuillShims"])
    ]
)
