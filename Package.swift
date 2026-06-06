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
// the canonical Linux GTK/Qt app products. Run
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

// SPIKE flag for the generic SwiftUI→Qt backend (BackendQt).
//
// The Qt graph deliberately EXCLUDES SwiftOpenUI (see the comment above the
// `quillUILinuxBuildBackend == .qt` block) so the existing native-Qt apps build
// without dragging in SwiftOpenUI's GTK pkg-config graph. The generic backend
// vertical slice needs SwiftOpenUI linked into the Qt graph — but ONLY when
// explicitly opted in, so the default Qt build (and its CI gate) is byte-for-
// byte unchanged. Setting QUILLUI_QT_GENERIC=1 (alongside QUILLUI_LINUX_BACKEND=qt)
// re-adds SwiftOpenUI and the BackendQt targets + quill-qt-generic-smoke product.
let quillUIQtGenericEnvironmentKey = "QUILLUI_QT_GENERIC"
let quillUIQtGenericEnabled: Bool = {
    let raw = ProcessInfo.processInfo.environment[quillUIQtGenericEnvironmentKey]?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
    switch raw {
    case "1", "true", "yes", "on":
        return true
    default:
        return false
    }
}()

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

func pkgConfigIncludeFlags(_ name: String) -> [String] {
    pkgConfigArguments(name, ["--cflags-only-I"])
}

func pkgConfigSwiftImporterFlags(_ name: String) -> [String] {
    pkgConfigIncludeFlags(name).flatMap { ["-Xcc", $0] }
}

func pkgConfigLinkerFlags(_ name: String) -> [String] {
    pkgConfigArguments(name, ["--libs-only-L", "--libs-only-l"])
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
let qt6WidgetsIncludeFlags: [String] = pkgConfigIncludeFlags("Qt6Widgets")
let qt6WidgetsLinkerFlags: [String] = pkgConfigLinkerFlags("Qt6Widgets")
let qt6WidgetsCxxFlags: [String] = qt6WidgetsIncludeFlags + ["-std=c++17", "-fPIC", "-Wno-deprecated-literal-operator"]
let gdkPixbufSwiftImporterFlags: [String] = pkgConfigSwiftImporterFlags("gdk-pixbuf-2.0")
let gdkPixbufLinkerFlags: [String] = pkgConfigLinkerFlags("gdk-pixbuf-2.0")
let gtk4SwiftImporterFlags: [String] = pkgConfigSwiftImporterFlags("gtk4")
let gtk4LinkerFlags: [String] = pkgConfigLinkerFlags("gtk4")

let quillUIGTKSwiftImporterSettings: [SwiftSetting] = quillUILinuxBuildBackend == .gtk ? [
    .unsafeFlags(gdkPixbufSwiftImporterFlags),
    .unsafeFlags(gtk4SwiftImporterFlags)
] : []
let quillUIGTKLinkerSettings: [LinkerSetting] = quillUILinuxBuildBackend == .gtk ? [
    .unsafeFlags(gdkPixbufLinkerFlags),
    .unsafeFlags(gtk4LinkerFlags)
] : []

if quillUILinuxBuildBackend == .qt && !qt6WidgetsPresent {
    fatalError("\(quillUILinuxBuildBackendEnvironmentKey)=qt requires the Qt6Widgets pkg-config package (install qt6-base-dev).")
}
#else
let quillUILinuxBuildBackend: QuillUILinuxBuildBackend = .gtk
let qt6WidgetsPresent: Bool = false
let qt6WidgetsIncludeFlags: [String] = []
let qt6WidgetsLinkerFlags: [String] = []
let qt6WidgetsCxxFlags: [String] = []
let gdkPixbufSwiftImporterFlags: [String] = []
let gdkPixbufLinkerFlags: [String] = []
let gtk4SwiftImporterFlags: [String] = []
let gtk4LinkerFlags: [String] = []
let quillUIGTKSwiftImporterSettings: [SwiftSetting] = []
let quillUIGTKLinkerSettings: [LinkerSetting] = []
#endif
#if os(Linux)
let nnwUpstreamPresent: Bool = upstreamPresent(".upstream/netnewswire/Modules/RSCore")
#else
// The .upstream NetNewsWire full-source tree is a Linux-only port: it pulls
// macOS-incompatible RSCore/Account/etc. sources that clash with the Quill
// shadow framework (e.g. duplicate ImageLuminanceType, unresolved RSTree.Node).
// macOS CI never has it (fresh clone). Gating to a Linux host also stops a local
// macOS checkout that *does* have .upstream populated from trying to build it,
// which otherwise breaks `swift build` / `swift test` on macOS. The
// quill-netnewswire product still exists on macOS via the self-contained
// QuillNetNewsWireCore.
let nnwUpstreamPresent: Bool = false
#endif
let wireguardUpstreamPresent: Bool = upstreamPresent(".upstream/wireguard-apple/Sources/WireGuardKit")
let codeEditSourceUpstreamPresent: Bool = upstreamPresent(".upstream/codeedit/CodeEdit")
let codeEditSymbolsUpstreamPresent: Bool = upstreamPresent(".upstream/codeeditsymbols")
// Signal-iOS upstream-slice gates (per-worktree `.upstream/...`, not committed).
// `signalUpstreamPresent` → the real signalapp/Signal-iOS source tree.
// `libsignalUpstreamPresent` → real signalapp/libsignal (LibSignalClient Swift
// wrapper + its Rust libsignal_ffi). Signal is compiled ON Linux against
// QuillUI's Apple-framework shim products, so the targets are `#if os(Linux)`.
let signalUpstreamPresent: Bool = upstreamPresent(".upstream/signal-ios/SignalServiceKit")
let libsignalUpstreamPresent: Bool = upstreamPresent(".upstream/libsignal/swift/Sources/LibSignalClient")
// Real Dimillian/IceCubesApp Models + NetworkClient, vendored Linux-only.
// The upstream iOS platform pin is a manifest constraint, not a source one —
// the data/network layer is portable Swift+SwiftSoup; UI-coupled bits resolve
// against the repo's SwiftUI shim + IceCubesShims. See fetch-upstream.sh.
let iceCubesUpstreamPresent: Bool = upstreamPresent(".upstream/icecubes/Packages/Models/Sources/Models")

enum QuillCanonicalLinuxAppQtRuntime {
    case genericQtNative
    case wireGuardQtNative

    var targetDependency: Target.Dependency {
        switch self {
        case .genericQtNative:
            return "QuillGenericQtNativeRuntime"
        case .wireGuardQtNative:
            return "QuillWireGuardQtNativeRuntime"
        }
    }
}

struct QuillCanonicalLinuxAppSpec {
    var product: String
    var target: String
    var qtPath: String
    var qtRuntime: QuillCanonicalLinuxAppQtRuntime

    var productDeclaration: Product {
        .executable(name: product, targets: [target])
    }
}

let quillCanonicalLinuxApps: [QuillCanonicalLinuxAppSpec] = [
    .init(product: "quill-icecubes", target: "QuillIceCubes", qtPath: "Sources/QuillIceCubesQt", qtRuntime: .genericQtNative),
    .init(product: "quill-netnewswire", target: "QuillNetNewsWire", qtPath: "Sources/QuillNetNewsWireQt", qtRuntime: .genericQtNative),
    .init(product: "quill-codeedit", target: "QuillCodeEdit", qtPath: "Sources/QuillCodeEditQt", qtRuntime: .genericQtNative),
    .init(product: "quill-signal", target: "QuillSignal", qtPath: "Sources/QuillSignalQt", qtRuntime: .genericQtNative),
    .init(product: "quill-telegram", target: "QuillTelegram", qtPath: "Sources/QuillTelegramQt", qtRuntime: .genericQtNative),
    .init(product: "quill-iina", target: "QuillIINA", qtPath: "Sources/QuillIINAQt", qtRuntime: .genericQtNative),
    .init(product: "quill-wireguard", target: "QuillWireGuard", qtPath: "Sources/QuillWireGuardQt", qtRuntime: .wireGuardQtNative)
]
let quillCanonicalLinuxAppProducts: [Product] = quillCanonicalLinuxApps.map(\.productDeclaration)

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
    // QuillSourceLowering is the SwiftSyntax-based replacement for the
    // regex transformations in scripts/lower-swiftdata-for-quilldata.sh
    // and scripts/lower-swiftui-source-for-linux.sh. The SwiftData CLI
    // ships as `quill-source-lower`; the SwiftUI CLI (in-place edits)
    // ships as `quill-lower-swiftui`. QuillDoctor scans an external
    // Apple SwiftPM project's imports and reports coverage against the
    // QuillUI compatibility matrix; the CLI ships as `quill-doctor`.
    .library(name: "QuillSourceLowering", targets: ["QuillSourceLowering"]),
    .executable(name: "quill-source-lower", targets: ["quill-source-lower"]),
    .executable(name: "quill-lower-swiftui", targets: ["quill-lower-swiftui"]),
    .executable(name: "quill-lower-appkit", targets: ["quill-lower-appkit"]),
    .library(name: "QuillDoctor", targets: ["QuillDoctor"]),
    .executable(name: "quill-doctor", targets: ["quill-doctor"]),
    // QuillPaint is the renderer-agnostic control paint layer. Apps using
    // QuillUI on Linux paint through QuillPaint's PaintContext protocol;
    // backend integrations (Cairo on GTK, Skia/QPainter on Qt, CoreGraphics
    // for Mac-reference snapshots) live in separate adapter targets.
    .library(name: "QuillPaint", targets: ["QuillPaint"]),
    // CoreGraphics adapter — Apple-only. Generates Mac-reference snapshots
    // from the same paint code that Linux backends use, so reference
    // images can't drift from production output.
    .library(name: "QuillPaintCoreGraphics", targets: ["QuillPaintCoreGraphics"]),
    // Cairo adapter — Linux/GTK backend.
    .library(name: "QuillPaintCairo", targets: ["QuillPaintCairo"]),
    // CLI that regenerates the Mac-reference PNG fixture set under
    // Tests/Fixtures/MacReference/ using QuillPaintCoreGraphics. Apple-only.
    .executable(name: "quill-render-mac-references", targets: ["quill-render-mac-references"]),
    // Standalone decode-contract check for the quill-signal-bridge protocol.
    // Foundation-only (depends on QuillSignalKit), so it builds without the GTK
    // backend; run as its own product to assert BridgeMessage JSON decoding.
    .executable(name: "quill-signal-decode-check", targets: ["QuillSignalDecodeCheck"])
] + quillCanonicalLinuxAppProducts

#if !os(Linux)
products.append(.executable(name: "quill-wireguard-qt", targets: ["QuillWireGuardQt"]))
#endif

// `quill-netnewswire` stays in the canonical app product roster even when the
// upstream NetNewsWire tree is absent because it is backed by the self-contained
// QuillNetNewsWireCore Foundation/XMLParser reader.

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
    .library(name: "Cocoa", targets: ["Cocoa"]),
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
    .library(name: "CoreWLAN", targets: ["CoreWLAN"]),
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
    "QuillPaint",
    // QuillFoundation provides `RSImage` (which QuillUI's Linux
    // `NSImage` typealiases to) and other CoreGraphics-shaped
    // bridge types. macOS uses Apple's real frameworks instead.
    "QuillFoundation",
    "QuillSwiftUICompatibility",
    "UniformTypeIdentifiers",
    .product(name: "SwiftOpenUI", package: "SwiftOpenUI"),
    "CGdkPixbuf",
    .product(name: "CGTK", package: "SwiftOpenUI"),
    .product(name: "BackendGTK4", package: "SwiftOpenUI")
]
#else
let quillUIDependencies: [Target.Dependency] = [
    "QuillKit",
    "QuillPaint",
    .product(name: "SwiftOpenUI", package: "SwiftOpenUI")
]
#endif

#if os(Linux)
let quillChatKitDependencies: [Target.Dependency] = ["QuillFoundation", "SwiftUI"]
#else
let quillChatKitDependencies: [Target.Dependency] = ["QuillFoundation"]
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
] + quillUIGTKSwiftImporterSettings

// QuillIceCubesCore consumes the real vendored Models when present (gtk-Linux);
// gated so macOS / qt (where the Models target isn't built) keep the reimpl.
var quillIceCubesCoreDependencies: [Target.Dependency] = ["QuillUI", "QuillFoundation"]
var quillIceCubesCoreSwiftSettings: [SwiftSetting] = appSwiftSettings
#if os(Linux)
if iceCubesUpstreamPresent && quillUILinuxBuildBackend == .gtk {
    quillIceCubesCoreDependencies.append("Models")
    quillIceCubesCoreSwiftSettings.append(.define("ICECUBES_REAL_MODELS"))
}
#endif

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

// Native Qt entry points are split from the GTK/SwiftOpenUI app graph. Linux
// chooses one host graph with QUILLUI_LINUX_BACKEND=gtk|qt: the default GTK
// graph keeps SwiftOpenUI scenes, while the Qt graph swaps app-specific Qt
// products to native Qt Widgets hosts fed by small JSON snapshots.
var quillWireGuardCoreDependencies: [Target.Dependency] = []
// Build the real upstream WireGuardKit (config model + keypair gen) wherever it's
// vendored — now Linux too (the Darwin/CommonCrypto blockers are shimmed). Core
// depends on it so CI compiles it; Core keeps its own model until a follow-up
// swaps in WireGuardKit's TunnelConfiguration. NOT in the native-Qt Linux graph:
// that path reassigns `targets` to a minimal list that omits the WireGuardKit
// upstream targets (and the Network/NetworkExtension shims they need).
if wireguardUpstreamPresent && quillUILinuxBuildBackend != .qt {
    quillWireGuardCoreDependencies.append("WireGuardKit")
    quillWireGuardCoreDependencies.append("QuillWireGuardUpstreamConfig")
}
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

let quillLinuxShimTestDependencies: [Target.Dependency] = [
    "QuillShims", "SwiftUI",
    "AsyncAlgorithms", "Carbon", "CoreGraphics", "Security",
    "AVFoundation", "Speech", "ApplicationServices",
    "ServiceManagement", "Alamofire", "MarkdownUI", "Splash",
    "ActivityIndicatorView", "WrappingHStack", "Vortex",
    "KeyboardShortcuts", "PhotosUI", "Magnet", "Combine",
    "OllamaKit", "Sparkle", "IOKit", "KeychainSwift"
]
let quillLinuxCompatibilityModuleTestDependencies: [Target.Dependency] = [
    "QuillUI", "QuillKit", "SwiftData", "AppKit", "UIKit", "os"
] + quillLinuxShimTestDependencies
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

#if os(Linux)
let quillGenericQtSwiftSettings: [SwiftSetting] =
    appSwiftSettings + (quillUILinuxBuildBackend == .qt ? [.define("QUILLUI_GENERIC_QT_NATIVE_BACKEND")] : [])
#else
let quillGenericQtSwiftSettings: [SwiftSetting] = appSwiftSettings
#endif

func quillCanonicalLinuxAppQtTarget(_ app: QuillCanonicalLinuxAppSpec) -> Target {
    let swiftSettings: [SwiftSetting]

    switch app.qtRuntime {
    case .genericQtNative:
        swiftSettings = quillGenericQtSwiftSettings
    case .wireGuardQtNative:
        swiftSettings = quillWireGuardQtSwiftSettings
    }

    return .executableTarget(
        name: app.target,
        dependencies: [app.qtRuntime.targetDependency],
        path: app.qtPath,
        swiftSettings: swiftSettings
    )
}

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

let quillDataPackageDependencies: [Package.Dependency] = [
    .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "600.0.0"),
    .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    // Signal's wire format (pod 'SwiftProtobuf' 1.36.1). Used by
    // SignalServiceKit's generated `*.pb.swift` + 23 hand-written imports.
    .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.36.1"),
    // CryptoKit-compatible crypto. Signal imports CryptoKit 26×; the Linux
    // `CryptoKit` shim re-exports swift-crypto's `Crypto` (Apple's own
    // API-compatible reimplementation) under that name.
    .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0")
]

let cSQLiteTarget: Target = .systemLibrary(
    name: "CSQLite",
    pkgConfig: "sqlite3",
    providers: [
        .apt(["libsqlite3-dev"]),
        .brew(["sqlite"])
    ]
)

let cCairoTarget: Target = .systemLibrary(
    name: "CCairo",
    pkgConfig: "cairo",
    providers: [
        .apt(["libcairo2-dev"]),
        .brew(["cairo"])
    ]
)

// Real system zlib (libz) — SignalServiceKit's CRC32 + GzipStreamTransform
// `import zlib` and use the genuine C API (z_stream / deflate / inflate / crc32).
// libz is present on Linux (zlib1g-dev) and macOS, so this is a REAL systemLibrary
// (gzip actually works), not an inert framework shim. Module name is `zlib` so
// the upstream `import zlib` resolves unmodified.
let cZlibTarget: Target = .systemLibrary(
    name: "zlib",
    pkgConfig: "zlib",
    providers: [
        .apt(["zlib1g-dev"]),
        .brew(["zlib"])
    ]
)

// QuillDataMacros declares the @QuillModel / @Attribute /
// @Relationship / @QuillPredicate / @Observable macros used
// by QuillData. The compiler loads it as an out-of-process
// build plugin; without a `.macro(…)` declaration here,
// `#externalMacro(module: "QuillDataMacros", …)` references
// fail with "plugin for module 'QuillDataMacros' not found".
let quillDataMacroTarget: Target = .macro(
    name: "QuillDataMacros",
    dependencies: [
        .product(name: "SwiftSyntax", package: "swift-syntax"),
        .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
        .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
        .product(name: "SwiftCompilerPlugin", package: "swift-syntax")
    ],
    path: "Sources/QuillDataMacros"
)

let quillDataTarget: Target = .target(
    name: "QuillData",
    dependencies: [
        "QuillDataMacros",
        "CSQLite",
        .product(name: "GRDB", package: "GRDB.swift")
    ]
)

let quillEnchantedDataTarget: Target = .target(
    name: "QuillEnchantedData",
    dependencies: ["QuillData"],
    path: "Sources/QuillEnchantedData",
    swiftSettings: appSwiftSettings
)

// QuillRSParser's HTMLMetadata does `import CoreGraphics` (CGSize/CGFloat).
// On Darwin the system framework satisfies it; on Linux the in-tree shim must
// be an explicit dep (SwiftPM does not auto-resolve an `import` to a same-
// package target). Declared as a statement-level `#if os(Linux)` helper (the
// idiom used by quillLinuxShimTestDependencies) rather than an inline array
// `#if` (illegal here) or a `.target(_:condition:)` (which leaves the dep in
// the macOS manifest and trips a spurious "source files should be located
// under Sources/CoreGraphics"). Empty on macOS.
#if os(Linux)
let quillRSParserPlatformDeps: [Target.Dependency] = ["CoreGraphics"]
#else
let quillRSParserPlatformDeps: [Target.Dependency] = []
#endif

var targets: [Target] = [
    cSQLiteTarget,
    cCairoTarget,
    cZlibTarget,
    // Cassowary constraint solver (vendored nucleic/kiwi, C++), exposed to Swift via a
    // pure-C ABI. Backs Auto Layout (NSLayoutConstraint) for the AppKit→Qt compatibility
    // layer — issue #231, milestone M0. Default graph only (no Qt dependency).
    .target(
        name: "CKiwi",
        path: "Sources/CKiwi",
        exclude: ["KIWI-LICENSE"],
        sources: ["CKiwiBridge.cpp"],
        publicHeadersPath: "include",
        cxxSettings: [
            .headerSearchPath("."),
            .unsafeFlags(["-std=c++17"])
        ]
    ),
    .target(
        name: "QuillAutoLayout",
        dependencies: ["CKiwi"],
        path: "Sources/QuillAutoLayout",
        swiftSettings: appSwiftSettings
    ),
    .target(
        name: "QuillUI",
        dependencies: quillUIDependencies,
        swiftSettings: quillUIGTKSwiftImporterSettings,
        linkerSettings: quillUIGTKLinkerSettings
    ),
    .target(
        name: "QuillUIGtk",
        dependencies: ["QuillUI"],
        path: "Sources/QuillUIGtk",
        swiftSettings: appSwiftSettings
    ),
    .target(
        name: "QuillUIQt",
        dependencies: ["QuillUI"],
        path: "Sources/QuillUIQt",
        swiftSettings: appSwiftSettings
    ),
    .target(
        name: "QuillInteractionSmokeSupport",
        dependencies: ["QuillUI"],
        path: "Sources/QuillInteractionSmokeSupport",
        swiftSettings: appSwiftSettings
    ),
    .systemLibrary(
        name: "CGdkPixbuf",
        path: "Sources/CGdkPixbuf",
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
        providers: [
            .apt(["libgtk-4-dev"])
        ]
    ),
    quillDataMacroTarget,
    quillDataTarget,
    // SwiftSyntax-based replacement for the SwiftData lowering regex
    // pipeline in scripts/lower-swiftdata-for-quilldata.sh. The library
    // is the long-lived ground truth; quill-source-lower is the CLI
    // wrapper that mirrors the shell script's SOURCE_DIR + OUTPUT_DIR
    // contract for generated-source profiles.
    .target(
        name: "QuillSourceLowering",
        dependencies: [
            .product(name: "SwiftSyntax", package: "swift-syntax"),
            .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
            .product(name: "SwiftParser", package: "swift-syntax")
        ],
        path: "Sources/QuillSourceLowering"
    ),
    .executableTarget(
        name: "quill-source-lower",
        dependencies: ["QuillSourceLowering"],
        path: "Sources/quill-source-lower"
    ),
    .executableTarget(
        name: "quill-lower-swiftui",
        dependencies: ["QuillSourceLowering"],
        path: "Sources/quill-lower-swiftui"
    ),
    .executableTarget(
        name: "quill-lower-appkit",
        dependencies: ["QuillSourceLowering"],
        path: "Sources/quill-lower-appkit"
    ),
    .target(
        name: "QuillDoctor",
        dependencies: [
            .product(name: "SwiftSyntax", package: "swift-syntax"),
            .product(name: "SwiftParser", package: "swift-syntax")
        ],
        path: "Sources/QuillDoctor"
    ),
    .executableTarget(
        name: "quill-doctor",
        dependencies: ["QuillDoctor"],
        path: "Sources/quill-doctor"
    ),
    .target(
        name: "QuillPaint",
        dependencies: [],
        path: "Sources/QuillPaint"
    ),
    .target(
        name: "QuillPaintCoreGraphics",
        dependencies: ["QuillPaint"],
        path: "Sources/QuillPaintCoreGraphics"
    ),
    .target(
        name: "QuillPaintCairo",
        dependencies: ["QuillPaint", "CCairo"],
        path: "Sources/QuillPaintCairo"
    ),
    .executableTarget(
        name: "quill-render-mac-references",
        dependencies: ["QuillPaint", "QuillPaintCoreGraphics"],
        path: "Sources/quill-render-mac-references"
    ),
    .target(
        name: "QuillKit",
        dependencies: []
    ),
    .target(
        name: "QuillFoundation",
        dependencies: ["QuillKit"],
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
        name: "QuillEnchantedShared",
        dependencies: ["QuillEnchantedData", "QuillFoundation"],
        path: "Sources/QuillEnchantedShared"
    ),
    quillEnchantedDataTarget,
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
        dependencies: ["QuillUI", "QuillFoundation", "QuillRSParser", "QuillArticles", "QuillData"],
        swiftSettings: appSwiftSettings
    ),
    // Minimal RSCore-shaped shim. Reproduces the slice of
    // upstream Ranchero-Software/NetNewsWire's RSCore surface
    // (String.md5String first, more arrive as upstream parser
    // sources are vendored over) so we can bring RSParser /
    // Articles / RSWeb / Account into the Linux build via
    // SwiftPM `moduleAliases: ["RSCore": "QuillRSCoreShim"]`
    // without dragging RSCore's AppKit/UIKit/os imports or its
    // ObjC sibling. Pure-Foundation target — compiles on macOS
    // and Linux unchanged.
    .target(
        name: "QuillRSCoreShim",
        dependencies: [],
        swiftSettings: appSwiftSettings
    ),
    // Vendored Ranchero-Software/NetNewsWire RSParser sources
    // (Sources/RSParser → Sources/QuillRSParser) with the lone
    // `import RSCore` rewritten to `import QuillRSCoreShim`.
    //
    // Goes around the dead-code upstream RSCore wiring lower in
    // this file (which fails because RSCoreObjC requires
    // <Foundation/Foundation.h> on Linux). The shim provides
    // the only RSCore symbol RSParser actually touches
    // (String.md5String) — see QuillRSCoreShim above.
    //
    // Refresh procedure: re-run `cp -R .upstream/netnewswire/
    // Modules/RSParser/Sources/RSParser/. Sources/QuillRSParser/`
    // and `sed -i 's/^import RSCore$/import QuillRSCoreShim/'`
    // across the tree, then re-run the parser tests.
    .target(
        name: "QuillRSParser",
        // CoreGraphics (Linux-only) added via quillRSParserPlatformDeps — see
        // the helper's definition above for why the Linux graph needed it and
        // why a `.target(_:condition:)` breaks macOS.
        dependencies: [
            "QuillRSCoreShim",
            "Tidemark",
        ] + quillRSParserPlatformDeps,
        path: "Sources/QuillRSParser",
        swiftSettings: appSwiftSettings
    ),
    // Vendored Ranchero-Software/NetNewsWire Articles module
    // (Sources/Articles → Sources/QuillArticles). Pure-model
    // target — Article, Author, Attachment, ArticleStatus — used
    // by upstream for in-memory + persistence article shape.
    //
    // Only RSCore symbol touched: String.md5String (for content-
    // addressed article IDs and author IDs), routed through
    // QuillRSCoreShim via the same `import RSCore` →
    // `import QuillRSCoreShim` rewrite as QuillRSParser.
    //
    // `import os` resolves to Apple's system framework on Darwin
    // and the Quill osShim on Linux — no explicit dep needed
    // (the Quill os library product is gated #if os(Linux)).
    //
    // Refresh procedure mirrors QuillRSParser: `cp -R .upstream/
    // netnewswire/Modules/Articles/Sources/Articles/.
    // Sources/QuillArticles/` then `sed -i
    // 's/^import RSCore$/import QuillRSCoreShim/'`.
    .target(
        name: "QuillArticles",
        dependencies: ["QuillRSCoreShim"],
        path: "Sources/QuillArticles",
        swiftSettings: appSwiftSettings
    ),
    // Minimal RSWeb shim — target named `RSWeb` so vendored `import RSWeb`
    // resolves to it verbatim. Grows toward real RSWeb as Account needs more.
    .target(
        name: "RSWeb",
        path: "Sources/QuillRSWebShim",
        swiftSettings: appSwiftSettings
    ),
    // Vendored Ranchero-Software/NetNewsWire Account module — incremental
    // bring-up: AccountBehavior / UnreadCountProvider / ContainerIdentifier /
    // SidebarItemIdentifier / AccountError. Grows as RSWeb/RSDatabase land.
    .target(
        name: "QuillAccount",
        dependencies: ["RSWeb", "QuillFoundation"],
        path: "Sources/QuillAccount",
        swiftSettings: appSwiftSettings
    ),
    // Vendored Ranchero-Software/NetNewsWire RSTree module
    // (Sources/RSTree → Sources/QuillRSTree). Pure-Foundation
    // tree data structures: Node, NodePath, RSTree,
    // TopLevelRepresentedObject, TreeController. Used in
    // upstream by the sidebar feed-tree controller; the
    // Quill feedsPane will migrate to it after vendoring.
    //
    // The upstream Sources/RSTree directory has one extra file
    // (NSOutlineView+RSTree.swift) that imports AppKit; it's
    // intentionally NOT copied here so the target stays
    // pure-Foundation. The audit at docs/netnewswire-audit.md
    // already confirmed the rest builds standalone on Linux.
    //
    // Refresh procedure: re-run the per-file cp loop in
    // .upstream/netnewswire/Modules/RSTree/Sources/RSTree
    // (skipping NSOutlineView+RSTree.swift) — RSTree has no
    // RSCore dependency today so the import-rewrite sed step
    // QuillRSParser/QuillArticles need does not apply here.
    .target(
        name: "QuillRSTree",
        dependencies: [],
        path: "Sources/QuillRSTree",
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
        dependencies: quillIceCubesCoreDependencies,
        swiftSettings: quillIceCubesCoreSwiftSettings
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
    // QuillSignalKit — unix-socket client for the quill-signal-bridge daemon
    // (presage/libsignal Rust engine). The real backend behind QuillSignal,
    // replacing the fixture model.
    .target(
        name: "QuillSignalKit",
        swiftSettings: appSwiftSettings
    ),
    .target(
        name: "QuillSignalCore",
        dependencies: ["QuillUI", "QuillChatKit", "QuillSignalKit"],
        swiftSettings: appSwiftSettings
    ),
    .executableTarget(
        name: "QuillSignal",
        dependencies: ["QuillSignalCore", "QuillUI"],
        swiftSettings: appSwiftSettings
    ),
    // Decode-contract check: asserts the bridge wire protocol decodes into
    // BridgeMessage. Foundation-only (QuillSignalKit), no GTK — fast to build/run.
    .executableTarget(
        name: "QuillSignalDecodeCheck",
        dependencies: ["QuillSignalKit"],
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
        dependencies: ["QuillUI", "QuillFoundation"],
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
        dependencies: ["QuillUI", "QuillFoundation"],
        swiftSettings: appSwiftSettings
    ),
    .executableTarget(
        name: "QuillCodeEdit",
        dependencies: ["QuillCodeEditCore", "QuillUI"],
        swiftSettings: appSwiftSettings
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
targets += [
    .executableTarget(
        name: "QuillWireGuardQt",
        dependencies: quillWireGuardQtDependencies,
        path: "Sources/QuillWireGuardQt",
        swiftSettings: quillWireGuardQtSwiftSettings
    )
]
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
// WireGuardKitC.h's Darwin types (`u_int32_t`, `u_char`,
// `sockaddr_ctl`) are resolved by fetch-upstream's `<sys/types.h>`
// patch; CommonCryptoLinux maps x25519.c's
// `<CommonCrypto/CommonRandom.h>` → getrandom(2). So the config
// model (TunnelConfiguration parsing, keypair generation, IPv4/v6
// helpers) compiles on Linux too — the runtime files are excluded
// via wireGuardKitExcludes. Verified building on swift:6.2-noble.
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
        ),
        // The real wg-quick string parser (TunnelConfiguration(fromWgQuickConfig:)
        // / asWgQuickConfig()) lives in the App's Shared/Model, extending
        // WireGuardKit's TunnelConfiguration. Compile it as its own target so the
        // real parser is available unmodified (fetch-upstream adds its
        // `import WireGuardKit`).
        .target(
            name: "QuillWireGuardUpstreamConfig",
            dependencies: ["WireGuardKit"],
            path: ".upstream/wireguard-apple",
            sources: [
                "Sources/Shared/Model/TunnelConfiguration+WgQuickConfig.swift",
                "Sources/Shared/Model/String+ArrayConversion.swift"
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
    // Conformance: compile WireGuard's REAL macOS KeyValueRow (unmodified upstream
    // AppKit) against the reimplementation via the Cocoa shadow. The build IS the
    // test. Linux-only — the Cocoa/AppKit shadows it depends on are #if os(Linux);
    // on macOS the real frameworks are used (issue #231, M3 conformance capstone).
    #if os(Linux)
    // ringlogger C (Sources/Shared/Logging/ringlogger.c) — the ring-buffer
    // backing for WireGuard's Logger.swift (open_log / write_msg_to_log /
    // write_log_to_file / close_log). Pure POSIX C (mmap), compiles on Linux.
    // Excludes the sibling Logger.swift (compiled by the conformance Swift
    // target) + test_ringlogger.c; ringlogger.h is the public header.
    targets.append(
        .target(
            name: "WireGuardRingLoggerC",
            path: ".upstream/wireguard-apple/Sources/Shared/Logging",
            exclude: ["Logger.swift", "test_ringlogger.c"],
            sources: ["ringlogger.c"],
            publicHeadersPath: "."
        )
    )
    targets.append(
        .target(
            name: "QuillWireGuardConformanceUI",
            dependencies: ["Cocoa", "NetworkExtension", "os", "WireGuardRingLoggerC"],
            path: ".upstream/wireguard-apple",
            sources: [
                // Shared logging: Logger.swift (wg_log) over the ringlogger C
                // ring buffer (import WireGuardRingLoggerC) + the `os` shadow.
                "Sources/Shared/Logging/Logger.swift",
                // First real MODEL file: TunnelStatus maps NEVPNStatus -> app
                // status, compiling against the NetworkExtension shadow (uses
                // NEVPNStatus incl. .reasserting, #338). Its @objc enum is
                // stripped by fetch-upstream's (now whole-app) lowering. Grows
                // this target toward the single-app-module.
                "Sources/WireGuardApp/Tunnel/TunnelStatus.swift",
                // ActivateOnDemandOption: maps on-demand config <-> NEOnDemandRule[]
                // (NE on-demand surface from #338/#340 + wg_log from #345).
                "Sources/WireGuardApp/Tunnel/ActivateOnDemandOption.swift",
                // App error model: WireGuardAppError protocol + AlertText typealias
                // + WireGuardResult<T> — self-contained (Foundation only); used pervasively
                // by the rest of the model layer.
                "Sources/WireGuardApp/WireGuardAppError.swift",
                "Sources/WireGuardApp/WireGuardResult.swift",
                "Sources/WireGuardApp/UI/macOS/View/KeyValueRow.swift",
                // First real ViewController: a full NSViewController (NSButton,
                // target-action, Auto Layout) compiling against the shadow after
                // fetch-upstream's AppKit lowering. No app-level deps (no `tr`).
                "Sources/WireGuardApp/UI/macOS/ViewController/ButtonedDetailViewController.swift",
                // Second real ViewController + its `tr` localization helper.
                // Exercises NSStackView(views:)/setCustomSpacing, NSEdgeInsets,
                // NSTextField(labelWithAttributedString:) (added in #314).
                "Sources/WireGuardApp/LocalizationHelper.swift",
                "Sources/WireGuardApp/UI/macOS/ViewController/UnusableTunnelDetailViewController.swift"
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    )
    #endif
}

// ── Signal-iOS upstream-slice (Linux / QuillOS) ─────────────────────────
// Compile the REAL signalapp/Signal-iOS against QuillUI's Linux
// Apple-framework shim products (UIKit / AVFoundation / Network / os / …),
// real GRDB + SwiftProtobuf, and real libsignal. Unlike WireGuard (a
// fixture shell on Linux) Signal is meant to BUILD on Linux, so these
// targets are gated `#if os(Linux)`. Source comes from `.upstream/signal-ios`
// and `.upstream/libsignal` (fetched per-worktree, never committed).
//
// libsignal wiring mirrors libsignal's own swift/Package.swift: `SignalFfi`
// is a systemLibrary whose module.modulemap does `link "signal_ffi"`, and
// `libsignal_ffi.a` is produced by `cargo build -p libsignal-ffi --release`
// into `.upstream/libsignal/target/release/` (the -L path below). The Swift
// wrapper compiles independently of the .a; the .a is only needed when a
// downstream executable/test links.
#if os(Linux)
if libsignalUpstreamPresent {
    targets += [
        .systemLibrary(
            name: "SignalFfi",
            path: ".upstream/libsignal/swift/Sources/SignalFfi"
        ),
        .target(
            name: "LibSignalClient",
            dependencies: ["SignalFfi"],
            path: ".upstream/libsignal/swift/Sources/LibSignalClient",
            // libsignal v0.94.1's Swift predates Swift 6 strict-concurrency;
            // build it in v5 language mode (revisit if it compiles clean).
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedLibrary("stdc++"),
                .unsafeFlags(["-L.upstream/libsignal/target/release"])
            ]
        )
    ]
}
#endif

// CryptoKit Linux shim → swift-crypto's `Crypto` (API-compatible). Canonical
// Apple framework name so upstream `import CryptoKit` resolves here on Linux.
#if os(Linux)
targets.append(
    .target(
        name: "CryptoKit",
        dependencies: [.product(name: "Crypto", package: "swift-crypto")],
        path: "Sources/CryptoKitShim"
    )
)
#endif

// CommonCrypto Linux shim → OpenSSL libcrypto (the AES subset Signal uses in
// CipherContext / Cryptography / PaddingBucket / ProvisioningCipher). A C target
// whose public umbrella is the canonical <CommonCrypto/CommonCrypto.h>, so
// upstream `import CommonCrypto` resolves here. Links system libcrypto (apt
// libssl-dev).
#if os(Linux)
targets.append(
    .target(
        name: "CommonCrypto",
        path: "Sources/CommonCryptoShim",
        publicHeadersPath: "include",
        linkerSettings: [.linkedLibrary("crypto")]
    )
)
#endif

// SignalRingRTC Linux shim — faithful type-surface of signalapp/ringrtc
// v2.69.1 for the NON-calling SSK paths (CallLinkRootKey + RingRTC logging).
// Real voice/video calling is WebRTC + a Rust FFI; deferred. See
// Sources/SignalRingRTCShim/SignalRingRTC.swift.
#if os(Linux)
targets.append(
    .target(
        name: "SignalRingRTC",
        path: "Sources/SignalRingRTCShim"
    )
)
#endif

// os_unfair_lock C shim. Signal's TSMutex.swift `import os.lock` (the `os`
// framework's clang `lock` submodule), which doesn't exist on Linux and can't
// be added to QuillUI's Swift `os` module. This C target provides the exact
// os_unfair_lock surface as a spinlock; TSMutex's import is patched to use it on
// Linux (scripts/fetch-upstream.sh).
#if os(Linux)
targets.append(
    .target(
        name: "COSUnfairLock",
        path: "Sources/COSUnfairLock",
        publicHeadersPath: "include"
    )
)
#endif

// Contacts Linux shim — Apple's Contacts framework value types (CNContact,
// CNLabeledValue, CNPhoneNumber, CNPostalAddress, …) for Signal's vCard /
// contact-import paths. System address-book access (CNContactStore) is deferred
// (returns empty / .denied). See Sources/ContactsShim/Contacts.swift.
#if os(Linux)
targets.append(
    .target(
        name: "Contacts",
        path: "Sources/ContactsShim"
    )
)
#endif

// libPhoneNumber-iOS Linux shim. The upstream is ObjC (no Linux build); Signal
// wraps it for E.164 phone-number parsing/formatting. Best-effort E.164
// implementation; full libphonenumber metadata behavior deferred. See
// Sources/libPhoneNumberShim/libPhoneNumber_iOS.swift.
#if os(Linux)
targets.append(
    .target(
        name: "libPhoneNumber_iOS",
        path: "Sources/libPhoneNumberShim"
    )
)
#endif

// Batch of thin Apple-framework / pod shims SignalServiceKit imports but that
// don't exist on Linux. Each is a placeholder module so `import X` resolves;
// concrete symbols are filled in as `cannot find type` errors surface. Behavior
// is deferred (system UI / payments / Siri / telephony / etc. aren't available
// on QuillOS). Sources live under Sources/AppleFrameworkShims/<Name>.
let signalAppleFrameworkShims = [
    "ContactsUI", "Intents", "PassKit", "LocalAuthentication", "Accelerate",
    "QuartzCore", "ImageIO", "CoreServices", "CoreImage", "AuthenticationServices",
    "UserNotifications", "SystemConfiguration", "StoreKit", "NaturalLanguage",
    "DeviceCheck", "CoreTelephony", "CFNetwork", "AudioToolbox", "AVFAudio",
    "CocoaLumberjack", "SDWebImage", "SDWebImageWebPCoder", "blurhash",
    "ObjCAssoc", "System", "notify",
    // NOTE: "zlib" is intentionally NOT here — it's a real systemLibrary
    // (cZlibTarget, links libz) rather than an inert Swift shim, so it's added to
    // SignalServiceKit's dependencies explicitly below.
]
#if os(Linux)
for shimName in signalAppleFrameworkShims {
    // Each shim may build on QuillFoundation's Core Graphics / Foundation shadow
    // types (e.g. ImageIO's CGImageSource returns QuillFoundation's CGImage).
    // QuillFoundation depends only on QuillKit, so this introduces no cycle; the
    // edge is inert for shims that do not import QuillFoundation.
    targets.append(.target(name: shimName, dependencies: ["QuillFoundation"], path: "Sources/AppleFrameworkShims/\(shimName)"))
}
#endif

// SignalServiceKit — the foundation target (1412 Swift files). Compiled on
// Linux against QuillUI's Apple-framework shim targets + LibSignalClient +
// GRDB + SwiftProtobuf. Excluded for the first build:
//  • Signal's ObjC core-model layer (TSMessage/TSInteraction/TSOutgoingMessage/
//    TSGroupModel/TSYapDatabaseObject/BaseModel + OWSAsserts/OWSLogs, ~35 .m/.h).
//    These #import <Foundation/Foundation.h> (ObjC Foundation) which does not
//    exist on swift-corelibs-foundation; they get PORTED to Swift incrementally
//    (the central milestone-4 challenge — hundreds of Swift files subclass them).
//  • tests/ (260 unit-test files), Calls/ (RingRTC), Payments/ (MobileCoin).
//  • Non-source resources SPM would reject (.proto/.crt/.cer/.pch/.py/.md/Makefile).
#if os(Linux)
if signalUpstreamPresent && libsignalUpstreamPresent {
    let signalServiceKitExcludes: [String] = [
        "tests",
        // Calls/ and Payments/ are mixed-language: their only ObjC files are model
        // /interaction classes ported under QuillPort (TSCall, OWSGroupCallMessage,
        // TSPaymentModels). Exclude just those ObjC files so the dirs' Swift
        // compiles.
        "Calls/Individual/TSCall.h", "Calls/Individual/TSCall.m",
        "Calls/Group/OWSGroupCallMessage.h", "Calls/Group/OWSGroupCallMessage.m",
        "Payments/TSPaymentModels.h", "Payments/TSPaymentModels.m",
        "Concurrency/Threading.h", "Concurrency/Threading.m",
        "Debugging/DebuggerUtils.h", "Debugging/DebuggerUtils.m",
        "Debugging/OWSAsserts.h", "Debugging/OWSAsserts.m",
        "Debugging/OWSLogs.h", "Debugging/OWSLogs.m",
        "Groups/TSGroupModel.h", "Groups/TSGroupModel.m",
        "Messages/Interactions/OWSDisappearingConfigurationUpdateInfoMessage.h",
        "Messages/Interactions/OWSDisappearingConfigurationUpdateInfoMessage.m",
        "Messages/Interactions/OWSVerificationStateChangeMessage.h",
        "Messages/Interactions/OWSVerificationStateChangeMessage.m",
        "Messages/Interactions/Quotes/TSQuotedMessage.h",
        "Messages/Interactions/Quotes/TSQuotedMessage.m",
        "Messages/Interactions/TSErrorMessage.h", "Messages/Interactions/TSErrorMessage.m",
        "Messages/Interactions/TSIncomingMessage.h", "Messages/Interactions/TSIncomingMessage.m",
        "Messages/Interactions/TSInfoMessage.h", "Messages/Interactions/TSInfoMessage.m",
        "Messages/Interactions/TSInteraction.h", "Messages/Interactions/TSInteraction.m",
        "Messages/Interactions/TSMessage.h", "Messages/Interactions/TSMessage.m",
        "Messages/Interactions/TSOutgoingMessage.h", "Messages/Interactions/TSOutgoingMessage.m",
        "Messages/Interactions/TSUnreadIndicatorInteraction.h",
        "Messages/Interactions/TSUnreadIndicatorInteraction.m",
        "Messages/InvalidKeyMessages/TSInvalidIdentityKeyErrorMessage.h",
        "Messages/InvalidKeyMessages/TSInvalidIdentityKeyErrorMessage.m",
        "Messages/InvalidKeyMessages/TSInvalidIdentityKeyReceivingErrorMessage.h",
        "Messages/InvalidKeyMessages/TSInvalidIdentityKeyReceivingErrorMessage.m",
        "Messages/InvalidKeyMessages/TSInvalidIdentityKeySendingErrorMessage.h",
        "Messages/InvalidKeyMessages/TSInvalidIdentityKeySendingErrorMessage.m",
        "Messages/OWSAddToContactsOfferMessage.h", "Messages/OWSAddToContactsOfferMessage.m",
        "Messages/OWSAddToProfileWhitelistOfferMessage.h",
        "Messages/OWSAddToProfileWhitelistOfferMessage.m",
        "Messages/OWSReadTracking.h",
        "Messages/OWSRecoverableDecryptionPlaceholder.h",
        "Messages/OWSRecoverableDecryptionPlaceholder.m",
        "Messages/OWSUnknownContactBlockOfferMessage.h",
        "Messages/OWSUnknownContactBlockOfferMessage.m",
        "Messages/OWSUnknownProtocolVersionMessage.h",
        "Messages/OWSUnknownProtocolVersionMessage.m",
        "Messages/Payments/OWSArchivedPaymentMessage.h",
        "Messages/Payments/OWSIncomingArchivedPaymentMessage.h",
        "Messages/Payments/OWSIncomingArchivedPaymentMessage.m",
        "Messages/Payments/OWSIncomingPaymentMessage.h",
        "Messages/Payments/OWSIncomingPaymentMessage.m",
        "Messages/Payments/OWSOutgoingArchivedPaymentMessage.h",
        "Messages/Payments/OWSOutgoingArchivedPaymentMessage.m",
        "Messages/Payments/OWSOutgoingPaymentMessage.h",
        "Messages/Payments/OWSOutgoingPaymentMessage.m",
        "Messages/Payments/OWSPaymentMessage.h",
        "Protos/Backups/Backup.proto", "Protos/Backups/README.md",
        "Protos/Backups/parse-libsignal-comparator-failure.py",
        "Protos/Makefile",
        "Protos/Specifications/CallQualitySurvey.proto",
        "Protos/Specifications/DeviceTransfer.proto",
        "Protos/Specifications/FingerprintProtocol.proto",
        "Protos/Specifications/Groups.proto",
        "Protos/Specifications/MobileCoinExternal.proto",
        "Protos/Specifications/Provisioning.proto",
        "Protos/Specifications/README.md",
        "Protos/Specifications/Registration.proto",
        "Protos/Specifications/SessionRecord.proto",
        "Protos/Specifications/SignalIOS.proto",
        "Protos/Specifications/SignalService.proto",
        "Protos/Specifications/StorageService.proto",
        "Protos/Specifications/svr2.proto",
        "Resources/Certificates/GIAG2.crt", "Resources/Certificates/GSR2.crt",
        "Resources/Certificates/GSR4.crt", "Resources/Certificates/GTSR1.crt",
        "Resources/Certificates/GTSR2.crt", "Resources/Certificates/GTSR3.crt",
        "Resources/Certificates/GTSR4.crt", "Resources/Certificates/isrgrootx1.crt",
        "Resources/Certificates/signal-messenger.cer",
        "Security/OWSVerificationState.h",
        "SignalServiceKit-Prefix.pch", "SignalServiceKit.h",
        "Storage/BaseModel.h", "Storage/BaseModel.m",
        "Storage/Database/SSKAccessors+SDS.h",
        "Storage/TSYapDatabaseObject.h", "Storage/TSYapDatabaseObject.m",
    ]
    targets += [
        .target(
            name: "SignalServiceKit",
            dependencies: [
                "LibSignalClient",
                "UIKit", "AVFoundation", "Network", "os", "Security", "CoreGraphics",
                "CryptoKit", "CommonCrypto", "SignalRingRTC", "COSUnfairLock", "Contacts",
                "libPhoneNumber_iOS", "UniformTypeIdentifiers", "zlib", "QuillFoundation",
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
            ] + signalAppleFrameworkShims.map { Target.Dependency.target(name: $0) },
            path: ".upstream/signal-ios/SignalServiceKit",
            exclude: signalServiceKitExcludes,
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
    .target(name: "os", dependencies: ["QuillKit"], path: "Sources/osShim"),
    .target(
        name: "QuillSwiftUICompatibility",
        dependencies: [.product(name: "SwiftOpenUI", package: "SwiftOpenUI")],
        path: "Sources/QuillSwiftUICompatibility"
    ),
    .target(
        name: "SwiftUI",
        dependencies: ["QuillUI", "QuillSwiftUICompatibility"],
        path: "Sources/SwiftUIShim"
    ),
    .target(name: "UniformTypeIdentifiers", dependencies: [], path: "Sources/UniformTypeIdentifiersShim"),
    .target(name: "Network", dependencies: [], path: "Sources/NetworkShim"),
    .target(name: "NetworkExtension", dependencies: ["Network"], path: "Sources/NetworkExtensionShim"),
    .testTarget(name: "NetworkExtensionTests", dependencies: ["NetworkExtension"], path: "Tests/NetworkExtensionTests"),
    // os shim — covers the two os_log overloads (Apple message-first + the
    // xctest type-first) coexisting unambiguously; see Sources/osShim.
    .testTarget(name: "osTests", dependencies: ["os"], path: "Tests/osTests"),
    // CoreWLAN — Wi-Fi SSID shadow (the last missing framework module for the
    // macOS WireGuard app; see Sources/CoreWLAN). Internal Linux shadow.
    .target(name: "CoreWLAN", dependencies: [], path: "Sources/CoreWLAN"),
    .testTarget(name: "CoreWLANTests", dependencies: ["CoreWLAN"], path: "Tests/CoreWLANTests"),
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
        dependencies: ["QuillFoundation", "QuillUIKit", "QuillKit"],
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
            .unsafeFlags(["-strict-concurrency=minimal"]),
            .unsafeFlags(gtk4SwiftImporterFlags)
        ],
        linkerSettings: [
            .unsafeFlags(gtk4LinkerFlags)
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
        path: "Sources/QuillGtkInteractionSmoke",
        swiftSettings: appSwiftSettings
    ),
    // Apple-framework compatibility shims that the generated
    // Enchanted package references by canonical name. Each target
    // shadows a real Apple module on Linux; the matching products
    // are added below.
    // CYCLE-BREAK: these UI-adjacent shims re-export
    // QuillFoundation/QuillUIKit/QuillKit directly instead of depending on
    // QuillShims, because QuillShims depends on them.
    .target(name: "UIKit", dependencies: ["QuillFoundation", "QuillUIKit", "QuillKit", "UserNotifications"], path: "Sources/UIKitShim"),
    // Cocoa umbrella shadow: `import Cocoa` re-exports the AppKit shadow + Foundation,
    // so unmodified macOS app source that `import Cocoa` recompiles unchanged.
    .target(name: "Cocoa", dependencies: ["AppKit"], path: "Sources/CocoaShim"),
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
    .package(name: "SwiftOpenUI", path: "third_party/SwiftOpenUI")
] + quillDataPackageDependencies
#if os(Linux)
// OpenCombine backs the Linux `Combine` compatibility shim
// (Sources/Combine re-exports OpenCombine / OpenCombineDispatch /
// OpenCombineFoundation). macOS uses the SDK Combine module.
allPackageDependencies.append(
    .package(url: "https://github.com/OpenCombine/OpenCombine.git", from: "0.14.0")
)
#endif
#if os(Linux)
// SwiftSoup (pure-Swift HTML parser) backs the vendored IceCubes Models
// HTMLString. Scoped to the gtk Linux build: the qt-native product build
// evaluates the manifest with a trimmed dependency set that can't resolve
// SwiftSoup, and the Models target isn't a dependency of any qt app anyway.
if iceCubesUpstreamPresent && quillUILinuxBuildBackend == .gtk {
allPackageDependencies.append(
    .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.4.3")
)
}
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
    products = quillCanonicalLinuxAppProducts + [
        .library(name: "QuillGenericQtNativeRuntime", targets: ["QuillGenericQtNativeRuntime"]),
        .executable(name: "quill-qt-interaction-smoke", targets: ["QuillQtInteractionSmoke"])
    ]
    allPackageDependencies = quillDataPackageDependencies
    targets = [
        cSQLiteTarget,
        quillDataMacroTarget,
        quillDataTarget,
        .target(
            name: "QuillKit",
            dependencies: []
        ),
        .target(
            name: "QuillFoundation",
            dependencies: ["QuillKit"],
            path: "Sources/QuillFoundation"
        ),
        .target(
            name: "QuillEnchantedShared",
            dependencies: ["QuillEnchantedData", "QuillFoundation"],
            path: "Sources/QuillEnchantedShared"
        ),
        quillEnchantedDataTarget,
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
        // --- AppKit→Qt reimplementation (issue #231, M1) ---
        // The AppKit shadow + its Qt runtime backing + Auto Layout, pulled into
        // the qt graph so unmodified `import AppKit` code can be recompiled and
        // rendered through Qt6. All GTK-free.
        .target(
            name: "QuillUIKit",
            dependencies: ["QuillFoundation"],
            path: "Sources/QuillUIKit"
        ),
        .target(
            name: "AppKit",
            dependencies: ["QuillFoundation", "QuillUIKit", "QuillKit"],
            path: "Sources/QuillAppKit",
            swiftSettings: [
                .swiftLanguageMode(.v5),
                .unsafeFlags(["-strict-concurrency=minimal"])
            ]
        ),
        .target(
            name: "CKiwi",
            path: "Sources/CKiwi",
            exclude: ["KIWI-LICENSE"],
            sources: ["CKiwiBridge.cpp"],
            publicHeadersPath: "include",
            cxxSettings: [
                .headerSearchPath("."),
                .unsafeFlags(["-std=c++17"])
            ]
        ),
        .target(
            name: "QuillAutoLayout",
            dependencies: ["CKiwi"],
            path: "Sources/QuillAutoLayout",
            swiftSettings: appSwiftSettings
        ),
        .target(
            name: "CQuillAppKitQt",
            dependencies: ["CQt6Widgets"],
            path: "Sources/CQuillAppKitQt",
            publicHeadersPath: "include",
            cxxSettings: [
                .unsafeFlags(qt6WidgetsCxxFlags)
            ],
            linkerSettings: [
                .unsafeFlags(qt6WidgetsLinkerFlags)
            ]
        ),
        .target(
            name: "QuillAppKitQt",
            dependencies: ["AppKit", "CQuillAppKitQt", "QuillAutoLayout"],
            path: "Sources/QuillAppKitQt",
            swiftSettings: appSwiftSettings
        ),
        .target(
            name: "QuillQtNativeRuntimeSupport",
            path: "Sources/QuillQtNativeRuntimeSupport",
            swiftSettings: appSwiftSettings
        ),
        .target(
            name: "QuillGenericQtNativeRuntime",
            dependencies: [.target(name: "QuillEnchantedShared"), "CQuillQt6WidgetsShim", "QuillQtNativeRuntimeSupport"],
            path: "Sources/QuillGenericQtNativeRuntime",
            swiftSettings: appSwiftSettings
        ),
        .target(
            name: "QuillWireGuardQtNativeRuntime",
            dependencies: ["QuillWireGuardCore", "CQuillQt6WidgetsShim", "QuillQtNativeRuntimeSupport"],
            path: "Sources/QuillWireGuardQtNativeRuntime",
            swiftSettings: appSwiftSettings
        ),
        .executableTarget(
            name: "QuillQtInteractionSmoke",
            dependencies: ["CQuillQt6WidgetsShim"],
            path: "Sources/QuillQtInteractionSmoke"
        )
    ] + quillCanonicalLinuxApps.map(quillCanonicalLinuxAppQtTarget)

    // --- Generic SwiftUI→Qt backend (BackendQt), opt-in via QUILLUI_QT_GENERIC ---
    //
    // Everything below is gated so the default Qt build is unchanged. When the
    // flag is on we (1) re-add SwiftOpenUI to the Qt dependency graph, (2) add a
    // CQtBridge C++ wrapper, the BackendQt Swift renderer, and a sibling
    // quill-qt-generic-smoke executable that renders a REAL SwiftUI tree through
    // QtBackend().run(QtSmokeApp.self). The 9 production apps keep their existing
    // per-app C++ shims and are not touched.
    if quillUIQtGenericEnabled {
        allPackageDependencies.append(
            .package(name: "SwiftOpenUI", path: "third_party/SwiftOpenUI")
        )
        targets += [
            .target(
                name: "CQtBridge",
                path: "Sources/CQtBridge",
                publicHeadersPath: "include",
                cxxSettings: [
                    .unsafeFlags(qt6WidgetsCxxFlags)
                ],
                linkerSettings: [
                    .unsafeFlags(qt6WidgetsLinkerFlags)
                ]
            ),
            .target(
                name: "BackendQt",
                dependencies: [
                    .product(name: "SwiftOpenUI", package: "SwiftOpenUI"),
                    .product(name: "SwiftOpenUISymbols", package: "SwiftOpenUI"),
                    "CQtBridge"
                ],
                path: "Sources/BackendQt",
                swiftSettings: appSwiftSettings + [
                    .define("QUILLUI_QT_GENERIC")
                ]
            ),
            .executableTarget(
                name: "QuillQtGenericSmoke",
                dependencies: ["BackendQt"],
                path: "Sources/QuillQtGenericSmoke",
                swiftSettings: appSwiftSettings + [
                    .define("QUILLUI_QT_GENERIC")
                ]
            )
        ]
        products.append(
            .executable(name: "quill-qt-generic-smoke", targets: ["QuillQtGenericSmoke"])
        )
    }
}
#endif

let packageTestTargets: [Target] = {
    #if os(Linux)
    if quillUILinuxBuildBackend == .qt {
        return [
            // Runs inside the stripped Qt graph itself. This keeps
            // `QUILLUI_LINUX_BACKEND=qt swift test` useful without
            // reintroducing the GTK/SwiftOpenUI dependency graph.
            .testTarget(
                name: "QuillAppKitQtTests",
                dependencies: ["QuillAppKitQt", "AppKit"],
                swiftSettings: appSwiftSettings
            ),
            // Pure model-layer tests for the reimplemented AppKit
            // (NSTableView / NSOutlineView data-source + tree logic). No Qt
            // rendering — just exercises the AppKit module on Linux.
            .testTarget(
                name: "QuillAppKitTests",
                dependencies: ["AppKit"],
                swiftSettings: appSwiftSettings
            ),
            .testTarget(
                name: "QuillQtBackendManifestTests",
                dependencies: ["QuillGenericQtNativeRuntime", "QuillQtNativeRuntimeSupport", "QuillEnchantedShared"],
                swiftSettings: appSwiftSettings
            )
        ]
    }
    #endif

    var tests: [Target] = [
        {
            // QuillShimsTests links the Linux compatibility shims
            // so the test file can `import AsyncAlgorithms` etc.
            // and surface link errors fast.
            #if os(Linux)
            let testDeps: [Target.Dependency] = quillLinuxShimTestDependencies
            #else
            let testDeps: [Target.Dependency] = ["QuillShims"]
            #endif
            return .testTarget(name: "QuillShimsTests", dependencies: testDeps)
        }(),
        .testTarget(
            name: "QuillAutoLayoutTests",
            dependencies: ["QuillAutoLayout"],
            swiftSettings: appSwiftSettings
        ),
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
        // Salvaged QuillEnchantedData persistence coverage (ConversationStore /
        // legacy SQLite store) from the deleted QuillEnchantedTests target —
        // reimpl retirement, epic #188.
        .testTarget(
            name: "QuillEnchantedDataTests",
            dependencies: ["QuillEnchantedData"],
            swiftSettings: appSwiftSettings
        ),
        .testTarget(
            name: "QuillSourceLoweringTests",
            dependencies: ["QuillSourceLowering"],
            swiftSettings: appSwiftSettings
        ),
        .testTarget(
            name: "QuillDoctorTests",
            dependencies: ["QuillDoctor"],
            swiftSettings: appSwiftSettings
        ),
        .testTarget(
            name: "QuillPaintTests",
            dependencies: ["QuillPaint"],
            swiftSettings: appSwiftSettings
        ),
        .testTarget(
            name: "QuillPaintCoreGraphicsTests",
            dependencies: ["QuillPaintCoreGraphics", "QuillPaint"],
            swiftSettings: appSwiftSettings
        ),
        .testTarget(
            name: "QuillPaintCairoTests",
            dependencies: ["QuillPaintCairo", "QuillPaint"],
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
        .testTarget(
            name: "QuillFoundationTests",
            dependencies: ["QuillFoundation"],
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
            dependencies: ["QuillNetNewsWireCore", "QuillArticles"],
            swiftSettings: appSwiftSettings
        ),
        // Pins QuillRSCoreShim against RFC 1321 MD5 test vectors
        // plus the upstream Insecure.MD5.hash equivalence (empty
        // string, "a", "abc", and the message digest test set
        // from the RFC). Guards against shim drift if the
        // pure-Swift MD5 ever gets touched.
        .testTarget(
            name: "QuillRSCoreShimTests",
            dependencies: ["QuillRSCoreShim"],
            swiftSettings: appSwiftSettings
        ),
        // Pins the live RSWeb clone (Sources/QuillRSWebShim, the `RSWeb`
        // module) — HTTP value types vendored verbatim from NetNewsWire's
        // RSWeb. Foundation-only surface.
        .testTarget(
            name: "QuillRSWebShimTests",
            dependencies: ["RSWeb"],
            swiftSettings: appSwiftSettings
        ),
        // Smoke tests for the vendored upstream RSParser. Pins
        // RSS 2.0 + Atom + FeedType detection so the
        // import-rewrite path (RSCore → QuillRSCoreShim) and the
        // cross-platform compile both stay green when upstream
        // refreshes.
        .testTarget(
            name: "QuillRSParserTests",
            dependencies: ["QuillRSParser"],
            swiftSettings: appSwiftSettings
        ),
        // Smoke tests for the vendored upstream Articles module.
        // Pins articleID synthesis (md5 over accountID+feedID+
        // uniqueID via QuillRSCoreShim), authorID content
        // addressing, and ArticleStatus value-equality.
        .testTarget(
            name: "QuillArticlesTests",
            dependencies: ["QuillArticles"],
            swiftSettings: appSwiftSettings
        ),
        .testTarget(
            name: "QuillAccountTests",
            dependencies: ["QuillAccount"],
            swiftSettings: appSwiftSettings
        ),
        // Smoke tests for the vendored upstream RSTree module.
        // Pins Node parent/child wiring, indexPath, and the
        // TreeController.rebuild() path the sidebar feedsPane
        // migration will lean on.
        .testTarget(
            name: "QuillRSTreeTests",
            dependencies: ["QuillRSTree"],
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

    #if os(Linux)
    // Exercises the Apple-framework compatibility modules that real
    // generated Enchanted source imports on Linux. This target stays out of
    // the stripped Qt manifest graph so `QUILLUI_LINUX_BACKEND=qt swift
    // test` does not reintroduce SwiftOpenUI/GTK.
    tests.append(.testTarget(
        name: "QuillCompatibilityModuleTests",
        dependencies: quillLinuxCompatibilityModuleTestDependencies,
        swiftSettings: appSwiftSettings
    ))
    #endif

    return tests
}()

// Real Dimillian/IceCubesApp data + network layer, compiled from upstream
// source on Linux (the iOS manifest pin is irrelevant on Linux). Targets are
// NAMED `Models` / `NetworkClient` so upstream's own `import Models` resolves.
// SwiftData/ is excluded (Apple-only local cache); the ~3 UI-coupled files
// resolve against the repo `SwiftUI` shim + the auto-imported IceCubesShims
// (LocalizedStringKey, RelativeDateTimeFormatter, AttributedString markdown).
#if os(Linux)
if iceCubesUpstreamPresent && quillUILinuxBuildBackend == .gtk {
    targets += [
        .target(
            name: "IceCubesShims",
            path: "Sources/IceCubesShims"
        ),
        .target(
            name: "Models",
            dependencies: [
                "SwiftUI",
                "IceCubesShims",
                .product(name: "SwiftSoup", package: "SwiftSoup"),
            ],
            path: ".upstream/icecubes/Packages/Models/Sources/Models",
            exclude: ["SwiftData"],
            swiftSettings: [
                .unsafeFlags(["-Xfrontend", "-import-module", "-Xfrontend", "IceCubesShims"])
            ]
        ),
        // Real Dimillian/IceCubesApp NetworkClient. Compiles unmodified once
        // fetch-upstream.sh's patch_icecubes adds `import FoundationNetworking`
        // (the Linux Foundation networking split) and rewrites `import OSLog`
        // to the repo `os` shim. Named so upstream `import NetworkClient` resolves.
        .target(
            name: "NetworkClient",
            dependencies: [
                "Models",
                "SwiftUI",
                "IceCubesShims",
                "Combine",
                "os",
            ],
            path: ".upstream/icecubes/Packages/NetworkClient/Sources/NetworkClient",
            swiftSettings: [
                .unsafeFlags(["-Xfrontend", "-import-module", "-Xfrontend", "IceCubesShims"])
            ]
        ),
    ]
}
#endif

let package = Package(
    name: "QuillUI",
    defaultLocalization: "en",
    platforms: [.macOS(.v14), .iOS(.v14)],
    products: products,
    dependencies: allPackageDependencies,
    targets: targets + packageTestTargets
)
