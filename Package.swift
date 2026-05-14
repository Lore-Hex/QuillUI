// swift-tools-version: 6.0

import PackageDescription
import CompilerPluginSupport
import Foundation

// Upstream-checkout gating.
//
// Path-based `.upstream/...` targets (NetNewsWire, WireGuard-Apple,
// CodeEdit, CodeEditSymbols) are gated on the matching directory
// existing under `.upstream/`. A fresh `git clone` of QuillUI
// resolves cleanly with no `.upstream/` populated and can still
// build `QuillUI` / `QuillEnchanted` / `QuillWireGuard` /
// `QuillWireGuardQt`. Run
// `scripts/fetch-upstream.sh` to fetch the upstreams and enable
// the gated targets.
//
// Path resolution: SwiftPM evaluates this manifest inside a
// sandbox copy, so `#filePath` points at the sandbox staging
// directory — not the package directory. CWD is reliable.
let packageRoot: String = FileManager.default.currentDirectoryPath
func upstreamPresent(_ relativePath: String) -> Bool {
    FileManager.default.fileExists(atPath: "\(packageRoot)/\(relativePath)")
}

enum QuillUILinuxBuildBackend: String {
    case gtk
    case qt

    init?(environmentValue rawValue: String) {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "", "gtk", "gtk4":
            self = .gtk
        case "qt", "qt6":
            self = .qt
        default:
            return nil
        }
    }
}

let quillUILinuxBuildBackendEnvironmentKey = "QUILLUI_LINUX_BACKEND"

#if os(Linux)
func pkgConfigPackagePresent(_ name: String) -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["pkg-config", "--exists", name]
    process.standardOutput = Pipe()
    process.standardError = Pipe()

    do {
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    } catch {
        return false
    }
}

func pkgConfigArguments(_ name: String, _ arguments: [String]) -> [String] {
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["pkg-config"] + arguments + [name]
    process.standardOutput = output
    process.standardError = Pipe()

    do {
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            return []
        }
        return String(decoding: data, as: UTF8.self)
            .split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
            .map(String.init)
    } catch {
        return []
    }
}

let quillUILinuxBuildBackend: QuillUILinuxBuildBackend = {
    let environment = ProcessInfo.processInfo.environment
    guard let rawValue = environment[quillUILinuxBuildBackendEnvironmentKey] else {
        return .gtk
    }

    guard let backend = QuillUILinuxBuildBackend(environmentValue: rawValue) else {
        fatalError("Unsupported \(quillUILinuxBuildBackendEnvironmentKey) value \"\(rawValue.trimmingCharacters(in: .whitespacesAndNewlines))\"; expected gtk or qt.")
    }

    return backend
}()

let qt6WidgetsPresent: Bool = pkgConfigPackagePresent("Qt6Widgets")
let qt6WidgetsIncludeFlags: [String] = pkgConfigArguments("Qt6Widgets", ["--cflags-only-I"])
let qt6WidgetsLinkerFlags: [String] = pkgConfigArguments("Qt6Widgets", ["--libs-only-L", "--libs-only-l"])
let qt6WidgetsCxxFlags: [String] = qt6WidgetsIncludeFlags + ["-std=c++17", "-fPIC", "-Wno-deprecated-literal-operator"]

if quillUILinuxBuildBackend == .qt && !qt6WidgetsPresent {
    fatalError("\(quillUILinuxBuildBackendEnvironmentKey)=qt requires the Qt6Widgets pkg-config package (install qt6-base-dev).")
}
#else
let quillUILinuxBuildBackend: QuillUILinuxBuildBackend = .gtk
let qt6WidgetsPresent: Bool = false
let qt6WidgetsIncludeFlags: [String] = []
let qt6WidgetsLinkerFlags: [String] = []
let qt6WidgetsCxxFlags: [String] = []
#endif
let nnwUpstreamPresent: Bool = upstreamPresent(".upstream/netnewswire/Modules/RSCore")
let wireguardUpstreamPresent: Bool = upstreamPresent(".upstream/wireguard-apple/Sources/WireGuardKit")
let codeEditSourceUpstreamPresent: Bool = upstreamPresent(".upstream/codeedit/CodeEdit")
let codeEditSymbolsUpstreamPresent: Bool = upstreamPresent(".upstream/codeeditsymbols")

var products: [Product] = [
    .library(name: "QuillUI", targets: ["QuillUI"]),
    .library(name: "QuillUIGtk", targets: ["QuillUIGtk"]),
    .library(name: "QuillUIQt", targets: ["QuillUIQt"]),
    .library(name: "QuillData", targets: ["QuillData"]),
    .library(name: "QuillKit", targets: ["QuillKit"]),
    .library(name: "QuillChatKit", targets: ["QuillChatKit"]),
    .library(name: "QuillFoundation", targets: ["QuillFoundation"]),
    .library(name: "QuillRS", targets: ["QuillRS"]),
    .library(name: "QuillUIKit", targets: ["QuillUIKit"]),
    .library(name: "QuillWebKit", targets: ["QuillWebKit"]),
    .library(name: "QuillShims", targets: ["QuillShims"]),
    .library(name: "KeychainSwift", targets: ["KeychainSwift"]),
    .executable(name: "quill-enchanted", targets: ["QuillEnchanted"]),
    .executable(name: "quill-enchanted-upstream-slice", targets: ["QuillEnchantedUpstreamSlice"]),
    .executable(name: "quill-icecubes", targets: ["QuillIceCubes"]),
    .executable(name: "quill-signal", targets: ["QuillSignal"]),
    .executable(name: "quill-telegram", targets: ["QuillTelegram"]),
    .executable(name: "quill-iina", targets: ["QuillIINA"]),
    .executable(name: "quill-codeedit", targets: ["QuillCodeEdit"]),
    .executable(name: "quill-wireguard", targets: ["QuillWireGuard"])
]

#if !os(Linux)
products.append(.executable(name: "quill-wireguard-qt", targets: ["QuillWireGuardQt"]))
#endif

// `quill-netnewswire` is now a cross-platform executable backed
// by the self-contained QuillNetNewsWireCore (Foundation
// XMLParser-based RSS reader). Was previously gated on the
// upstream NetNewsWireLogic Shared/ tree compiling, which it
// doesn't on either platform yet.
products.append(.executable(name: "quill-netnewswire", targets: ["QuillNetNewsWire"]))

// SwiftData stays cross-platform: generated packages can depend on
// this product explicitly, while Apple's SDK module remains available
// through normal framework import resolution.
products.append(.library(name: "SwiftData", targets: ["SwiftData"]))

// Canonical iOS framework shims are Linux-only. Exposing a local
// `UIKit` module on macOS poisons third-party `canImport(UIKit)`
// checks and makes packages compile iOS-only branches against the
// wrong module.
#if os(Linux)
products += [
    .library(name: "UIKit", targets: ["UIKit"]),
    .library(name: "MessageUI", targets: ["MessageUI"]),
    .library(name: "SafariServices", targets: ["SafariServices"]),
    .library(name: "MobileCoreServices", targets: ["MobileCoreServices"])
]
#endif

// Linux-only library products exposing the Apple-framework
// compatibility shim targets to consumers (e.g. the generated
// Quill Chat / Enchanted package built by
// `scripts/generated-enchanted-full-source-check.sh`). On Apple
// platforms `import SwiftUI`, `import AVFoundation` etc. resolve
// to the real Apple frameworks via the SDK; on Linux they
// resolve to these QuillUI-exported shims.
#if os(Linux)
if quillUILinuxBuildBackend == .gtk {
    products.append(.executable(name: "quill-gtk-interaction-smoke", targets: ["QuillGtkInteractionSmoke"]))
}

products += [
    .library(name: "SwiftUI", targets: ["SwiftUI"]),
    .library(name: "UniformTypeIdentifiers", targets: ["UniformTypeIdentifiers"]),
    .library(name: "Network", targets: ["Network"]),
    .library(name: "NetworkExtension", targets: ["NetworkExtension"]),
    .library(name: "AppKit", targets: ["AppKit"]),
    .library(name: "QuillAppKitGTK", targets: ["QuillAppKitGTK"]),
    .library(name: "os", targets: ["os"]),
    .library(name: "AsyncAlgorithms", targets: ["AsyncAlgorithms"]),
    .library(name: "Carbon", targets: ["Carbon"]),
    .library(name: "CoreGraphics", targets: ["CoreGraphics"]),
    .library(name: "Security", targets: ["Security"]),
    .library(name: "AVFoundation", targets: ["AVFoundation"]),
    .library(name: "Speech", targets: ["Speech"]),
    .library(name: "ApplicationServices", targets: ["ApplicationServices"]),
    .library(name: "ServiceManagement", targets: ["ServiceManagement"]),
    .library(name: "Alamofire", targets: ["Alamofire"]),
    .library(name: "MarkdownUI", targets: ["MarkdownUI"]),
    .library(name: "Splash", targets: ["Splash"]),
    .library(name: "ActivityIndicatorView", targets: ["ActivityIndicatorView"]),
    .library(name: "WrappingHStack", targets: ["WrappingHStack"]),
    .library(name: "Vortex", targets: ["Vortex"]),
    .library(name: "KeyboardShortcuts", targets: ["KeyboardShortcuts"]),
    .library(name: "PhotosUI", targets: ["PhotosUI"]),
    .library(name: "Magnet", targets: ["Magnet"]),
    .library(name: "Combine", targets: ["Combine"]),
    .library(name: "OllamaKit", targets: ["OllamaKit"]),
    .library(name: "Sparkle", targets: ["Sparkle"]),
    .library(name: "IOKit", targets: ["IOKit"])
]
#endif

#if os(Linux)
let quillUIDependencies: [Target.Dependency] = [
    "QuillKit",
    // QuillFoundation provides `RSImage` (which QuillUI's Linux
    // `NSImage` typealiases to) and other CoreGraphics-shaped
    // bridge types. macOS uses Apple's real frameworks instead.
    "QuillFoundation",
    "UniformTypeIdentifiers",
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

#if os(Linux)
let quillChatKitDependencies: [Target.Dependency] = ["SwiftUI"]
#else
let quillChatKitDependencies: [Target.Dependency] = []
#endif

let nnwSwiftSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v5),
    .unsafeFlags(["-strict-concurrency=minimal", "-Xfrontend", "-import-module", "-Xfrontend", "QuillShims", "-Xfrontend", "-disable-access-control"])
]

let standardSwiftSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v5),
    .unsafeFlags(["-strict-concurrency=minimal", "-Xfrontend", "-import-module", "-Xfrontend", "QuillShims"])
]

let appSwiftSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v5),
    .unsafeFlags(["-strict-concurrency=minimal"])
]

#if os(Linux)
let quillShimsDependencies: [Target.Dependency] = [
    "QuillKit", "QuillData", "os",
    "QuillFoundation", "QuillWebKit", "QuillUIKit", "QuillRS",
    "UIKit", "MessageUI", "SafariServices", "MobileCoreServices",
    "Zip", "Tidemark", "UniformTypeIdentifiers", "Network", "NetworkExtension",
    "KeychainSwift"
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
    "RSWeb", "RSTree", "QuillShims", "Zip", "os"
]
#else
let nnwLogicDependencies: [Target.Dependency] = [
    "RSCore", "Account", "Articles", "RSParser", "ArticlesDatabase",
    "RSWeb", "RSTree", "QuillShims", "Zip"
]
#endif

// QuillWireGuard is split into a pure model core, one shared SwiftUI-shaped UI
// target, and backend-specific entry points. Linux chooses one host graph with
// QUILLUI_LINUX_BACKEND=gtk|qt: the default GTK graph keeps the SwiftOpenUI
// scene path, while the Qt graph swaps quill-wireguard-qt to a native Qt
// Widgets host fed by the same core presentation snapshot.
let quillWireGuardCoreDependencies: [Target.Dependency] = []
var quillWireGuardUIDependencies: [Target.Dependency] = ["QuillWireGuardCore", "QuillUI"]
#if !os(Linux)
if wireguardUpstreamPresent {
    quillWireGuardUIDependencies.append("WireGuardKit")
}
#endif
#if os(Linux)
quillWireGuardUIDependencies.append("SwiftUI")
#endif
let quillWireGuardDependencies: [Target.Dependency] = ["QuillWireGuardUI", "QuillUI"]
var quillParityTestDependencies: [Target.Dependency] = [
    "QuillKit",
    "QuillData",
    "QuillUI",
    "QuillWireGuardUI"
]
#if os(Linux)
quillParityTestDependencies.append("SwiftUI")
#endif
#if os(Linux)
func quillLinuxBackendDependencies(
    nativeQt: [Target.Dependency],
    fallback: [Target.Dependency]
) -> [Target.Dependency] {
    if quillUILinuxBuildBackend == .qt {
        return nativeQt
    }
    return fallback
}
#else
func quillLinuxBackendDependencies(
    nativeQt: [Target.Dependency],
    fallback: [Target.Dependency]
) -> [Target.Dependency] {
    fallback
}
#endif

let quillWireGuardQtDependencies: [Target.Dependency] = quillLinuxBackendDependencies(
    nativeQt: ["QuillWireGuardQtNativeRuntime"],
    fallback: ["QuillWireGuardUI", "QuillUIQt"]
)
#if os(Linux)
let quillWireGuardQtSwiftSettings: [SwiftSetting] =
    appSwiftSettings + (quillUILinuxBuildBackend == .qt ? [.define("QUILLUI_WIREGUARD_QT_NATIVE_BACKEND")] : [])
#else
let quillWireGuardQtSwiftSettings: [SwiftSetting] = appSwiftSettings
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
    .target(
        name: "QuillUIGtk",
        dependencies: ["QuillUI"],
        path: "Sources/QuillUIGtk"
    ),
    .target(
        name: "QuillUIQt",
        dependencies: ["QuillUI"],
        path: "Sources/QuillUIQt"
    ),
    .target(
        name: "QuillInteractionSmokeSupport",
        dependencies: ["QuillUI"],
        path: "Sources/QuillInteractionSmokeSupport"
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
    // QuillDataMacros declares the @QuillModel / @Attribute /
    // @Relationship / @QuillPredicate / @Observable macros used
    // by QuillData. The compiler loads it as an out-of-process
    // build plugin; without a `.macro(…)` declaration here,
    // `#externalMacro(module: "QuillDataMacros", …)` references
    // fail with "plugin for module 'QuillDataMacros' not found".
    .macro(
        name: "QuillDataMacros",
        dependencies: [
            .product(name: "SwiftSyntax", package: "swift-syntax"),
            .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
            .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
            .product(name: "SwiftCompilerPlugin", package: "swift-syntax")
        ],
        path: "Sources/QuillDataMacros"
    ),
    .target(
        name: "QuillData",
        dependencies: [
            "QuillDataMacros",
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
        dependencies: ["QuillFoundation", "QuillUIKit", "QuillKit", "QuillData"],
        path: "Sources/QuillRS"
    ),
    .target(
        name: "QuillShims",
        dependencies: quillShimsDependencies
    ),
    .target(
        name: "KeychainSwift",
        dependencies: [],
        path: "Sources/KeychainSwift"
    ),
    // RSTree lives in-tree (Sources/RSTree) so its target stays here
    // regardless of which upstream is fetched.
    .target(
        name: "RSTree",
        dependencies: ["QuillShims"],
        path: "Sources/RSTree",
        swiftSettings: nnwSwiftSettings
    ),
    // CYCLE-BREAK: these are deps of QuillShims (Linux block) so they
    // can't depend on QuillShims back. Their *.swift sources have been
    // updated to re-export QuillRS / QuillFoundation directly.
    .target(name: "Secrets", dependencies: ["QuillFoundation"], path: "Sources/SecretsShim"),
    .target(name: "Tidemark", dependencies: ["QuillRS"], path: "Sources/TidemarkShim"),
    .target(name: "Zip", dependencies: ["QuillRS"], path: "Sources/ZipShim"),
    .target(name: "SwiftData", dependencies: ["QuillData"], path: "Sources/SwiftData"),
    .target(
        name: "QuillEnchantedCore",
        dependencies: ["QuillUI", "QuillData", "CSQLite"]
    ),
    .executableTarget(
        name: "QuillEnchanted",
        dependencies: ["QuillEnchantedCore", "QuillUI"],
        swiftSettings: appSwiftSettings
    ),
    // NetNewsWire app — third port per docs/app-targets.md.
    // Self-contained RSS reader: `URLSession`-fetched feed
    // bytes parsed by Foundation's built-in `XMLParser` into a
    // minimal `RSSItem` model. The upstream
    // Ranchero-Software/NetNewsWire `Shared/` tree references
    // `Mac/`-only types (~1655 errors on macOS) and its ObjC
    // pieces don't compile against swift-corelibs-foundation
    // on Linux, so we ship a local reader until those are
    // split. Cross-platform target — works on both macOS and
    // Linux unmodified.
    .target(
        name: "QuillNetNewsWireCore",
        dependencies: ["QuillUI", "QuillFoundation"],
        swiftSettings: appSwiftSettings
    ),
    .executableTarget(
        name: "QuillNetNewsWire",
        dependencies: ["QuillNetNewsWireCore", "QuillUI"],
        swiftSettings: appSwiftSettings
    ),
    // IceCubes app — second port per docs/app-targets.md.
    // Reimplements the Mastodon API surface (Status, Account,
    // Timelines, MastodonClient) locally in
    // `Sources/QuillIceCubesCore/IceCubesAPI.swift` because the
    // upstream Dimillian/IceCubesApp Packages pin
    // `platforms: [.iOS(.v18), .visionOS(.v1)]` and don't
    // resolve on macOS or Linux.
    //
    // Swift 5 language mode + minimal strict-concurrency so
    // SwiftOpenUI's `.task` / `Task { … }` / `.onAppear` paths
    // don't trip Swift 6's `#SendableClosureCaptures` /
    // `#SendingRisksDataRace` checks on the non-Sendable
    // `QuillIceCubesContentView` struct.
    .target(
        name: "QuillIceCubesCore",
        dependencies: ["QuillUI", "QuillFoundation"],
        swiftSettings: appSwiftSettings
    ),
    .executableTarget(
        name: "QuillIceCubes",
        dependencies: ["QuillIceCubesCore", "QuillUI"],
        swiftSettings: appSwiftSettings
    ),
    // Signal iOS (5), Telegram Swift (6), IINA (7) — fixture-backed
    // app shells per docs/app-targets.md. These targets now render
    // conversation timelines, foldered chat lists, and media-player
    // chrome through QuillUI while future slices replace fixture
    // models with real protocol/playback backends.
    //
    // QuillChatKit is shared chat chrome (bubble, sidebar shell,
    // timeline) that Signal + Telegram both consume so the per-app
    // shells only carry their own model + folder/unread logic.
    .target(
        name: "QuillChatKit",
        dependencies: quillChatKitDependencies,
        swiftSettings: appSwiftSettings
    ),
    .target(
        name: "QuillSignalCore",
        dependencies: ["QuillUI", "QuillChatKit"],
        swiftSettings: appSwiftSettings
    ),
    .executableTarget(
        name: "QuillSignal",
        dependencies: ["QuillSignalCore", "QuillUI"],
        swiftSettings: appSwiftSettings
    ),
    .target(
        name: "QuillTelegramCore",
        dependencies: ["QuillUI", "QuillChatKit"],
        swiftSettings: appSwiftSettings
    ),
    .executableTarget(
        name: "QuillTelegram",
        dependencies: ["QuillTelegramCore", "QuillUI"],
        swiftSettings: appSwiftSettings
    ),
    .target(
        name: "QuillIINACore",
        dependencies: ["QuillUI"],
        swiftSettings: appSwiftSettings
    ),
    .executableTarget(
        name: "QuillIINA",
        dependencies: ["QuillIINACore", "QuillUI"],
        swiftSettings: appSwiftSettings
    ),
    // CodeEdit (4) — fixture-backed IDE shell. The vendored CodeEditUpstream
    // target stays opt-in via
    // `scripts/fetch-upstream.sh codeedit codeeditsymbols`; it
    // pulls in a SwiftLintPlugin prebuild command that SwiftPM
    // 6 rejects. QuillCodeEditCore keeps the file tree, tabs, and
    // editable text pane buildable through QuillUI's compatibility
    // layer without the opt-in path.
    .target(
        name: "QuillCodeEditCore",
        dependencies: ["QuillUI"],
        swiftSettings: appSwiftSettings
    ),
    .executableTarget(
        name: "QuillCodeEdit",
        dependencies: ["QuillCodeEditCore", "QuillUI"],
        swiftSettings: appSwiftSettings
    ),
    .executableTarget(
        name: "QuillEnchantedUpstreamSlice",
        dependencies: ["QuillEnchantedCore", "QuillUI"],
        // The slice's main.swift has a deeply-nested SwiftUI body that
        // trips Swift 6's per-expression type-check timeout (default
        // ~30s on macOS). Bump the threshold rather than restructure
        // the expression.
        swiftSettings: appSwiftSettings + [
            .unsafeFlags(["-Xfrontend", "-solver-expression-time-threshold=600"])
        ]
    ),
    .target(
        name: "QuillWireGuardCore",
        dependencies: quillWireGuardCoreDependencies,
        path: "Sources/QuillWireGuardCore"
    ),
    .target(
        name: "QuillWireGuardUI",
        dependencies: quillWireGuardUIDependencies,
        path: "Sources/QuillWireGuardUI",
        swiftSettings: appSwiftSettings
    ),
    .executableTarget(
        name: "QuillWireGuard",
        dependencies: quillWireGuardDependencies,
        path: "Sources/QuillWireGuard",
        swiftSettings: appSwiftSettings
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
    // `QuillAssetSymbolsPlugin` is the only build plugin kept in the
    // package manifest. Older `@main` extraction scaffolding was replaced
    // by the generated Enchanted source-lowering scripts.
]

#if !os(Linux)
targets.append(
    .executableTarget(
        name: "QuillWireGuardQt",
        dependencies: quillWireGuardQtDependencies,
        path: "Sources/QuillWireGuardQt",
        swiftSettings: quillWireGuardQtSwiftSettings
    )
)
#endif

// NetNewsWire upstream — modular RSS reader source (Ranchero-Software/
// NetNewsWire). The path-based targets only exist if `.upstream/
// netnewswire/...` is populated (run `scripts/fetch-upstream.sh`).
// On a fresh clone we skip the whole NetNewsWire graph and the
// `QuillNetNewsWire` executable along with it.
//
// Linux gate: NetNewsWire ships `.m`/`.h` Objective-C sources
// (RSCoreObjC, RSDatabaseObjC) that #import <Foundation/Foundation.h>
// — that header doesn't exist on swift-corelibs-foundation, so
// even the apt-clang-free toolchain can't build the ObjC pieces.
// Until we provide a GNUstep-style header shim or rewrite the
// ObjC bits in Swift, keep the NetNewsWire graph macOS-only.
#if !os(Linux)
if nnwUpstreamPresent {
    targets += [
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
        .target(
            name: "NetNewsWireLogic",
            dependencies: nnwLogicDependencies,
            path: ".upstream/netnewswire",
            exclude: ["Shared/ExtensionPoints/SendToMarsEditCommand.swift", "Shared/ExtensionPoints/SendToMicroBlogCommand.swift", "Shared/DefaultAccountNames.xcstrings", "Shared/Article Rendering/newsfoot.js", "Shared/Resources/Biblioteca.nnwtheme", "Shared/Resources/GlobalKeyboardShortcuts.plist", "Shared/Article Rendering/stylesheet.css", "Shared/Article Rendering/core.css", "Shared/Importers/DefaultFeeds.opml", "Shared/Resources/NewsFax.nnwtheme", "Shared/Resources/Sepia.nnwtheme", "Shared/Resources/Appanoose.nnwtheme", "Shared/Resources/SidebarKeyboardShortcuts.plist", "Shared/Resources/Tiqoe Dark.nnwtheme", "Shared/Article Rendering/main.js", "Shared/Resources/Promenade.nnwtheme", "Shared/Resources/Verdana Revival.nnwtheme", "Shared/ShareExtension/SafariExt.js", "Shared/Resources/DetailKeyboardShortcuts.plist", "Shared/Resources/Hyperlegible.nnwtheme", "Shared/Resources/ContentRules.json", "Shared/Article Rendering/template.html", "Shared/Resources/TimelineKeyboardShortcuts.plist", "Shared/Widget/WidgetDataEncoder.swift", "Shared/Widget/WidgetDeepLinks.swift", "iOS/NetNewsWire-iOS-Bridging-Header.h", "iOS/UIKit Extensions/SFSafariViewController+Extras.h", "iOS/UIKit Extensions/SFSafariViewController+Extras.m", "iOS/Resources/Assets.xcassets", "iOS/Resources/Thanks.rtf", "iOS/Resources/blank.html", "iOS/Resources/page.html", "iOS/Resources/NetNewsWire.entitlements", "iOS/Resources/Dedication.rtf", "iOS/IntentsExtension/NetNewsWire_iOS_IntentsExtension.entitlements", "iOS/Resources/Info.plist", "iOS/Resources/NetNewsWire-dev.entitlements", "iOS/Settings/SettingsTableViewCell.xib", "iOS/ShareExtension/NetNewsWire_iOS_ShareExtension.entitlements", "iOS/Add/AddFeedSelectFolderTableViewCell.xib", "iOS/Settings/Settings.storyboard", "iOS/ShareExtension/ShareFolderPickerAccountCell.xib", "iOS/Resources/main_ios.js", "iOS/Add/Add.storyboard", "iOS/Resources/About.rtf", "iOS/ShareExtension/Info.plist", "iOS/ShareExtension/ShareFolderPickerFolderCell.xib", "iOS/Inspector/Inspector.storyboard", "iOS/IntentsExtension/Info.plist", "iOS/Account/Account.storyboard", "iOS/Resources/Credits.rtf", "iOS/Settings/SettingsComboTableViewCell.xib", "iOS/IntentsExtension", "iOS/Widget", "iOS/ShareExtension", "iOS/Base.lproj", "iOS/Resources/PrivacyInfo.xcprivacy"],
            // Use `Shared` only. The `iOS/` tree imports UIKit
            // throughout (CloudKitAccountViewController.swift etc.)
            // which macOS doesn't ship, and the macOS `Mac/` tree
            // is a full AppKit app with its own `@main` entry
            // point that would conflict with `QuillNetNewsWire`.
            // `Shared/` alone still references `AppDefaults`,
            // `Browser`, `Node`, `appDelegate` etc. from `Mac/`
            // (~1655 errors on macOS) — full NetNewsWire UI
            // integration is out of scope for this checkpoint.
            // Document the gap; CI keeps the target on
            // best-effort.
            sources: ["Shared"],
            swiftSettings: nnwSwiftSettings
        ),
    ]
}
#endif
// NOTE: `QuillNetNewsWire` no longer comes from the upstream
// NetNewsWireLogic block above. The Shared+Mac coupling
// produces ~1655 unresolved-symbol errors on macOS and the
// ObjC pieces (RSCoreObjC / RSDatabaseObjC) refuse to
// compile against swift-corelibs-foundation on Linux. The
// real executable target now points at the self-contained
// `QuillNetNewsWireCore` (Foundation XMLParser-backed) in the
// cross-platform target block earlier in this file.

// WireGuard Apple upstream. The path-based targets only exist if
// `.upstream/wireguard-apple/...` is populated. When absent we skip
// both WireGuardKitC and WireGuardKit (and `QuillWireGuardCore`
// drops its WireGuardKit dependency further down).
//
// Linux gate: WireGuardKitC.h uses Darwin-only types
// (`u_int32_t`, `u_char`, `sockaddr_ctl`) and pulls in macOS
// kernel-control APIs. CommonCryptoLinux covers x25519.c's
// `<CommonCrypto/CommonRandom.h>` but not the header-side
// Darwinisms. Linux WireGuard therefore runs as a configuration
// manager shell backed by `QuillWireGuardCore` fixtures until a
// real privileged backend adapter lands.
#if !os(Linux)
if wireguardUpstreamPresent {
    targets += [
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
        )
    ]
}
#endif

// CodeEdit upstream — macOS-only (it's a pure AppKit/SwiftUI Mac app
// using NSTextView, NSDocument, NSApplicationDelegateAdaptor, Sparkle,
// and a stack of CodeEditApp's own packages). The Linux path can't
// compile this without source modifications because so much of the
// surface is non-conditional AppKit. Also gated on the vendored
// CodeEditSymbols checkout being present (see top-of-file note).
#if !os(Linux)
if codeEditSymbolsUpstreamPresent && codeEditSourceUpstreamPresent {
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
}
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
    .target(name: "UniformTypeIdentifiers", dependencies: [], path: "Sources/UniformTypeIdentifiersShim"),
    .target(name: "Network", dependencies: [], path: "Sources/NetworkShim"),
    .target(name: "NetworkExtension", dependencies: ["Network"], path: "Sources/NetworkExtensionShim"),
    // QuillAppKit — compile-only AppKit shadow. Target named `AppKit`
    // so upstream `import AppKit` resolves to this swiftmodule on
    // Linux. Phase A: type stubs only. Phase B will back the heavy
    // hitters (NSWindow, NSView, NSPasteboard, etc.) with GTK4.
    // AppKit shim: pin to Swift 5 language mode so the many
    // static `let` cursor/color/etc. constants don't trip Swift
    // 6's strict-concurrency check ("static property is not
    // concurrency-safe because it is nonisolated global shared
    // mutable state"). The shim is compile-time scaffolding for
    // generated Enchanted source, not runtime-shared global
    // state.
    .target(
        name: "AppKit",
        dependencies: ["QuillFoundation", "QuillUIKit"],
        path: "Sources/QuillAppKit",
        swiftSettings: [
            .swiftLanguageMode(.v5),
            .unsafeFlags(["-strict-concurrency=minimal"])
        ]
    ),
    // GTK4-backed runtime for QuillAppKit. Separate target so the
    // bare AppKit module stays a clean shadow (no transitive CGtk4
    // dep visible to clients like swift-sharing's `canImport(AppKit)`
    // branch). Apps that want the runtime backing import QuillAppKitGTK.
    .target(
        name: "QuillAppKitGTK",
        dependencies: ["AppKit", "CGtk4"],
        path: "Sources/QuillAppKitGTK",
        swiftSettings: [
            .swiftLanguageMode(.v5),
            .unsafeFlags(["-strict-concurrency=minimal"])
        ]
    ),
    // Runtime demo: exercises NSPasteboard.general's Phase B backing
    // (Wayland / X11 / file-backed tier) end-to-end. Writes a string,
    // reads it back, asserts the round-trip succeeded. Linux-only —
    // on macOS the real NSPasteboard works without any QuillAppKit
    // shim, so the demo target is unnecessary there.
    .executableTarget(
        name: "QuillAppKitPasteboardDemo",
        dependencies: ["AppKit", "QuillAppKitGTK"],
        path: "Sources/QuillAppKitPasteboardDemo",
        swiftSettings: [
            .swiftLanguageMode(.v5),
            .unsafeFlags(["-strict-concurrency=minimal"])
        ]
    ),
    // Smoke test for QuillAppKit. Exercises realistic AppKit usage
    // (NSWindowController, NSViewController, NSOutlineViewDelegate,
    // NSStatusItem, NSPasteboard, NSApplicationDelegate) so that
    // missing types surface as compile errors here before they land
    // in a real upstream app.
    .target(
        name: "QuillAppKitSmoke",
        dependencies: ["AppKit"],
        path: "Sources/QuillAppKitSmoke",
        swiftSettings: [
            .swiftLanguageMode(.v5),
            .unsafeFlags(["-strict-concurrency=minimal"])
        ]
    ),
    // Generic backend interaction smoke app. CI's
    // `scripts/linux-backend-interaction-check.sh` builds this
    // executable to validate that QuillUI button taps and sheet
    // presentations round-trip through SwiftOpenUI's GTK4
    // backend through QuillApp (open-panel / sidebar / banner /
    // sheet modes).
    .executableTarget(
        name: "QuillGtkInteractionSmoke",
        dependencies: ["QuillUIGtk", "QuillInteractionSmokeSupport"],
        path: "Sources/QuillGtkInteractionSmoke"
    ),
    // Apple-framework compatibility shims that the generated
    // Enchanted package references by canonical name. Each target
    // shadows a real Apple module on Linux; the matching products
    // are added below.
    // CYCLE-BREAK: these UI-adjacent shims re-export
    // QuillFoundation/QuillUIKit directly instead of depending on
    // QuillShims, because QuillShims depends on them.
    .target(name: "UIKit", dependencies: ["QuillFoundation", "QuillUIKit"], path: "Sources/UIKitShim"),
    .target(name: "MessageUI", dependencies: ["QuillFoundation", "QuillUIKit"], path: "Sources/MessageUIShim"),
    .target(name: "SafariServices", dependencies: ["QuillFoundation", "QuillUIKit"], path: "Sources/SafariServicesShim"),
    .target(name: "MobileCoreServices", dependencies: ["QuillFoundation"], path: "Sources/MobileCoreServicesShim"),
    .target(name: "AsyncAlgorithms", dependencies: [], path: "Sources/AsyncAlgorithms"),
    .target(name: "Carbon", dependencies: [], path: "Sources/Carbon"),
    .target(name: "CoreGraphics", dependencies: ["QuillKit"], path: "Sources/CoreGraphics"),
    .target(name: "Security", dependencies: ["QuillKit"], path: "Sources/Security"),
    .target(name: "AVFoundation", dependencies: ["QuillKit"], path: "Sources/AVFoundation"),
    .target(name: "Speech", dependencies: ["QuillKit", "AVFoundation"], path: "Sources/Speech"),
    .target(name: "ApplicationServices", dependencies: ["QuillKit"], path: "Sources/ApplicationServices"),
    .target(name: "ServiceManagement", dependencies: ["QuillKit"], path: "Sources/ServiceManagement"),
    .target(name: "Alamofire", dependencies: ["Security"], path: "Sources/Alamofire"),
    .target(name: "MarkdownUI", dependencies: ["SwiftUI"], path: "Sources/MarkdownUI"),
    .target(name: "Splash", dependencies: ["SwiftUI"], path: "Sources/Splash"),
    .target(name: "ActivityIndicatorView", dependencies: ["SwiftUI"], path: "Sources/ActivityIndicatorView"),
    .target(name: "WrappingHStack", dependencies: ["SwiftUI"], path: "Sources/WrappingHStack"),
    .target(name: "Vortex", dependencies: ["SwiftUI"], path: "Sources/Vortex"),
    .target(name: "KeyboardShortcuts", dependencies: ["SwiftUI"], path: "Sources/KeyboardShortcuts"),
    .target(name: "PhotosUI", dependencies: ["SwiftUI"], path: "Sources/PhotosUI"),
    .target(name: "Magnet", dependencies: ["AppKit"], path: "Sources/Magnet"),
    // Linux `import Combine` resolves to this re-export over
    // OpenCombine — Apple's Combine isn't part of swift-corelibs.
    .target(
        name: "Combine",
        dependencies: [
            .product(name: "OpenCombine", package: "OpenCombine"),
            .product(name: "OpenCombineDispatch", package: "OpenCombine"),
            .product(name: "OpenCombineFoundation", package: "OpenCombine")
        ],
        path: "Sources/Combine"
    ),
    // Combine-dependent shims.
    .target(name: "OllamaKit", dependencies: ["Combine", "QuillKit"], path: "Sources/OllamaKit"),
    .target(name: "Sparkle", dependencies: ["Combine"], path: "Sources/Sparkle"),
    // IOKit: header-only C target. `module.modulemap` exposes
    // `IOKit` and its `IOKit.usb` submodule; `dummy.c` is an empty
    // translation unit so SwiftPM treats this as a buildable C
    // target rather than a documentation-only directory.
    .target(
        name: "IOKit",
        path: "Sources/IOKit",
        publicHeadersPath: "."
    ),
])
// Linux-only target that compiles a hand-picked set of real
// CodeEdit upstream files (the ones that import AppKit only,
// with no dependency on Sparkle/CodeEditSourceEditor/SwiftUI/etc.)
// to prove QuillAppKit's surface is sufficient for production
// Mac code with zero source modifications. Gated on the upstream
// being fetched (run `scripts/fetch-upstream.sh`).
if codeEditSourceUpstreamPresent {
    targets.append(
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
    )
}
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
#if os(Linux)
// OpenCombine backs the Linux `Combine` compatibility shim
// (Sources/Combine re-exports OpenCombine / OpenCombineDispatch /
// OpenCombineFoundation). macOS uses the SDK Combine module.
allPackageDependencies.append(
    .package(url: "https://github.com/OpenCombine/OpenCombine.git", from: "0.14.0")
)
#endif
#if !os(Linux)
if codeEditSymbolsUpstreamPresent {
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
}
#endif

// Qt builds must not load the GTK/SwiftOpenUI graph. SwiftPM evaluates
// dependency manifests before target planning, so keeping SwiftOpenUI in the
// package dependency list is enough to pull in its GTK pkg-config warnings even
// for a native Qt-only smoke app.
#if os(Linux)
if quillUILinuxBuildBackend == .qt {
    products = [
        .executable(name: "quill-wireguard-qt", targets: ["QuillWireGuardQt"]),
        .executable(name: "quill-qt-interaction-smoke", targets: ["QuillQtInteractionSmoke"])
    ]
    allPackageDependencies = []
    targets = [
        .target(
            name: "QuillWireGuardCore",
            dependencies: quillWireGuardCoreDependencies,
            path: "Sources/QuillWireGuardCore"
        ),
        .systemLibrary(
            name: "CQt6Widgets",
            path: "Sources/CQt6Widgets",
            providers: [
                .apt(["qt6-base-dev"])
            ]
        ),
        .target(
            name: "CQuillQt6WidgetsShim",
            dependencies: ["CQt6Widgets"],
            path: "Sources/CQuillQt6WidgetsShim",
            publicHeadersPath: "include",
            cxxSettings: [
                .unsafeFlags(qt6WidgetsCxxFlags)
            ],
            linkerSettings: [
                .unsafeFlags(qt6WidgetsLinkerFlags)
            ]
        ),
        .target(
            name: "QuillWireGuardQtNativeRuntime",
            dependencies: ["QuillWireGuardCore", "CQuillQt6WidgetsShim"],
            path: "Sources/QuillWireGuardQtNativeRuntime",
            swiftSettings: appSwiftSettings
        ),
        .executableTarget(
            name: "QuillWireGuardQt",
            dependencies: ["QuillWireGuardQtNativeRuntime"],
            path: "Sources/QuillWireGuardQt",
            swiftSettings: quillWireGuardQtSwiftSettings
        ),
        .executableTarget(
            name: "QuillQtInteractionSmoke",
            dependencies: ["CQuillQt6WidgetsShim"],
            path: "Sources/QuillQtInteractionSmoke"
        )
    ]
}
#endif

let packageTestTargets: [Target] = {
    #if os(Linux)
    if quillUILinuxBuildBackend == .qt {
        return []
    }
    #endif

    return [
        {
            // QuillShimsTests links the Linux compatibility shims
            // so the test file can `import AsyncAlgorithms` etc.
            // and surface link errors fast.
            #if os(Linux)
            let testDeps: [Target.Dependency] = [
                "QuillShims", "SwiftUI",
                "AsyncAlgorithms", "Carbon", "CoreGraphics", "Security",
                "AVFoundation", "Speech", "ApplicationServices",
                "ServiceManagement", "Alamofire", "MarkdownUI", "Splash",
                "ActivityIndicatorView", "WrappingHStack", "Vortex",
                "KeyboardShortcuts", "PhotosUI", "Magnet", "Combine",
                "OllamaKit", "Sparkle", "IOKit", "KeychainSwift"
            ]
            #else
            let testDeps: [Target.Dependency] = ["QuillShims"]
            #endif
            return .testTarget(name: "QuillShimsTests", dependencies: testDeps)
        }(),
        .testTarget(
            name: "KeychainSwiftTests",
            dependencies: ["KeychainSwift"],
            swiftSettings: appSwiftSettings
        ),
        .testTarget(
            name: "QuillChatKitTests",
            dependencies: ["QuillChatKit"],
            swiftSettings: appSwiftSettings
        ),
        // Pins the SwiftData-shaped persistence shim: model
        // lifecycle operations, QuillPredicate lowering,
        // relationship persistence, and generated-source helper
        // scripts used by compatibility profiles.
        .testTarget(
            name: "QuillDataTests",
            dependencies: ["QuillData"],
            swiftSettings: appSwiftSettings
        ),
        // QuillKitTests covers QuillClipboard / diagnostics /
        // capability matrix / launch service / speech backend —
        // pure-Foundation surface. Tests that need upstream
        // packages or full generated apps stay explicitly listed
        // here instead of being discovered accidentally.
        .testTarget(
            name: "QuillKitTests",
            dependencies: ["QuillKit"],
            swiftSettings: appSwiftSettings
        ),
        // Covers IceCubesAPI — the self-contained Mastodon API
        // surface (HTMLString tag/entity stripping, Account +
        // Status snake_case JSON decoding, Timelines endpoint
        // query construction, MastodonClient defaults). All pure
        // Foundation / URL types, no transitive
        // CombineSchedulers pull-in.
        .testTarget(
            name: "QuillIceCubesCoreTests",
            dependencies: ["QuillIceCubesCore"],
            swiftSettings: appSwiftSettings
        ),
        // Pins the RSS 2.0 + Atom parser inside
        // QuillNetNewsWireCore via @testable import — feeds it
        // fixture XML strings (no URLSession), asserts title /
        // link / pubDate / description decoding, CDATA support,
        // Untitled + id fallbacks, and RSSItem's derived URL +
        // plain-text properties (HTML tag stripping and the
        // shared entity set).
        .testTarget(
            name: "QuillNetNewsWireCoreTests",
            dependencies: ["QuillNetNewsWireCore"],
            swiftSettings: appSwiftSettings
        ),
        // Pins QuillCodeEditCore: the `ProjectFile.extension`
        // computed property (used by the sidebar's icon switch),
        // ProjectFile identity / uniqueness, and the QuillSample
        // fixture project's shape. Pure-Foundation deps.
        .testTarget(
            name: "QuillCodeEditCoreTests",
            dependencies: ["QuillCodeEditCore"],
            swiftSettings: appSwiftSettings
        ),
        // Pins QuillTelegramCore's `TelegramFolderFilter` —
        // the All/Personal/Work pill-row filter behind the
        // sidebar — plus fixture invariants (folder coverage,
        // non-empty messages, unique ids, pill membership).
        .testTarget(
            name: "QuillTelegramCoreTests",
            dependencies: ["QuillTelegramCore"],
            swiftSettings: appSwiftSettings
        ),
        // Pins QuillIINACore: PlaylistItem identity + fixture
        // invariants (non-empty playlist, title/duration shape,
        // mm:ss duration format, the four Blender shorts named
        // in Checkpoint 89).
        .testTarget(
            name: "QuillIINACoreTests",
            dependencies: ["QuillIINACore"],
            swiftSettings: appSwiftSettings
        ),
        // Pins QuillSignalCore: Message + Conversation identity,
        // ChatMessage conformance (verifies the type still
        // routes through QuillChatKit), and fixture invariants
        // (non-empty conversations, non-empty messages, unique
        // ids, self-messages tagged "Me", named conversations).
        .testTarget(
            name: "QuillSignalCoreTests",
            dependencies: ["QuillSignalCore", "QuillChatKit"],
            swiftSettings: appSwiftSettings
        ),
        // Pins QuillWireGuardCore: deterministic tunnel fixtures,
        // backend availability reporting, and wg-quick export text
        // used by the Linux configuration-manager shell.
        .testTarget(
            name: "QuillWireGuardCoreTests",
            dependencies: ["QuillWireGuardCore"],
            swiftSettings: appSwiftSettings
        ),
        // Cross-platform Apple-framework and app rendering parity checks.
        // Keeping this registered prevents the parity suite from drifting
        // while QuillUI's GTK and Qt hosts evolve in parallel.
        .testTarget(
            name: "QuillParityTests",
            dependencies: quillParityTestDependencies,
            swiftSettings: appSwiftSettings
        ),
        // Pins the QuillUI core library's public surface:
        // QuillPlatform.name reports the host, QuillUIVersion is
        // semver-shaped, and QuillApp.run resolves. Keeps QuillUI
        // itself on the test-target scorecard.
        .testTarget(
            name: "QuillUITests",
            dependencies: ["QuillUI", "QuillUIGtk", "QuillUIQt", "QuillInteractionSmokeSupport"],
            swiftSettings: appSwiftSettings
        )
    ]
}()

let package = Package(
    name: "QuillUI",
    defaultLocalization: "en",
    platforms: [.macOS(.v14), .iOS(.v14)],
    products: products,
    dependencies: allPackageDependencies,
    targets: targets + packageTestTargets
)
