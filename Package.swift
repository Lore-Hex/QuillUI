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
// The NNW upstream slice (Account/Shared module train) does not yet compile
// green on Linux (e.g. Account/OPMLFile.swift #selector needs lowering), and
// `swift test` compiles every declared target — so gating these targets on
// directory presence alone keeps the whole Linux CI lane red, since the
// default CI fetch populates .upstream/netnewswire. Opt-in via env while the
// slice campaign drives it to zero errors:
//   QUILLUI_NNW_UPSTREAM=1 swift build --target NetNewsWireSharedCore
let nnwUpstreamEnabled: Bool = nnwUpstreamPresent
    && ProcessInfo.processInfo.environment["QUILLUI_NNW_UPSTREAM"] == "1"
let wireguardUpstreamPresent: Bool = upstreamPresent(".upstream/wireguard-apple/Sources/WireGuardKit")
// The QuillWireGuardConformanceUI target (the AppKit UI compile-conformance for
// the real WireGuard macOS app) is incomplete WIP: its `sources:` list has grown
// to include files (TunnelsManager/TunnelEditViewController/…) whose lowered
// source references shim symbols the target never injected (QuillTimer,
// NSKeyValueObservation, ObjCAssoc) plus residual broken-lowering errors — its
// swiftSettings has been bare `[.swiftLanguageMode(.v5)]` since the target was
// created (#276), so the `-import-module` shim injection other Linux source
// targets rely on was never present here. `swift test` compiles it, so it has
// been silently red, masked behind the duplicate-Account manifest error and the
// IceCubes-lane errors. Make it opt-in so the WireGuard conformance lane can
// drive it to green without keeping the whole repo's Linux CI red. WireGuardKit
// (the real library) and the C shims still build unconditionally. Re-enable with
// QUILLUI_WIREGUARD_CONFORMANCE_UI=1 once it compiles. See the unbreak issue.
let wireGuardConformanceUIEnabled: Bool = wireguardUpstreamPresent
    && ProcessInfo.processInfo.environment["QUILLUI_WIREGUARD_CONFORMANCE_UI"] == "1"
let codeEditSourceUpstreamPresent: Bool = upstreamPresent(".upstream/codeedit/CodeEdit")
let codeEditSymbolsUpstreamPresent: Bool = upstreamPresent(".upstream/codeeditsymbols")
// Signal-iOS upstream-slice gates (per-worktree `.upstream/...`, not committed).
// `signalUpstreamPresent` → the real signalapp/Signal-iOS source tree.
// `libsignalUpstreamPresent` → real signalapp/libsignal (LibSignalClient Swift
// wrapper + its Rust libsignal_ffi). Signal is compiled ON Linux against
// QuillUI's Apple-framework shim products, so the targets are `#if os(Linux)`.
let signalUpstreamPresent: Bool = upstreamPresent(".upstream/signal-ios/SignalServiceKit")
let libsignalUpstreamPresent: Bool = upstreamPresent(".upstream/libsignal/swift/Sources/LibSignalClient")
let signalAppTargetPresent: Bool = signalUpstreamPresent
    && FileManager.default.fileExists(atPath: ".upstream/signal-ios/Signal/ConversationView")
    && !FileManager.default.fileExists(atPath: ".upstream/signal-ios/Signal/Calls")
// rjwalters/SolderScope — first community-requested conformance app: a real
// macOS SwiftUI USB-microscope viewer (MIT) compiled UNMODIFIED on Linux
// against the SwiftUI/AppKit/AVFoundation/CoreImage shim surface.
let solderScopeUpstreamPresent: Bool = upstreamPresent(".upstream/solderscope/SolderScope")
// SceneKit conformance lane (docs/scenekit-conformance.md) — all MIT:
// nicklockwood/Euclid (pure-Swift 3D geometry/CSG lib + a UIKit/SceneKit
// Example app) and nicklockwood/ShapeScript (real shipped macOS app whose
// entire viewport is SceneKit) plus its two pure-Swift deps. ShapeScript
// pins Euclid 0.8.x via SwiftPM URL deps upstream; we compile it against
// .upstream/euclid (HEAD == 0.8.14 today) as path-based targets instead so
// every source stays unmodified and locally inspectable. Fetch via
// `scripts/fetch-upstream.sh scenekit`.
let euclidUpstreamPresent: Bool = upstreamPresent(".upstream/euclid/Sources")
let svgPathUpstreamPresent: Bool = upstreamPresent(".upstream/svgpath/Sources")
let shapeScriptUpstreamPresent: Bool = upstreamPresent(".upstream/shapescript/ShapeScript")
// In-repo SceneKit fixture apps (Sources/QuillSceneKitFixtures): authored
// solar-system + molecule viewers exercising a small, known SCN surface
// (SCNScene/SCNNode/SCNSphere/SCNCylinder, materials, lights, camera,
// actions, SceneView) ahead of the real apps. RED until the SceneKit shim
// grows that surface, so they are opt-in:
let quillUISceneKitFixturesEnabled: Bool =
    ProcessInfo.processInfo.environment["QUILLUI_SCENEKIT_FIXTURES"] == "1"
// Real Dimillian/IceCubesApp Models + NetworkClient, vendored Linux-only.
// The upstream iOS platform pin is a manifest constraint, not a source one —
// the data/network layer is portable Swift+SwiftSoup; UI-coupled bits resolve
// against the repo's SwiftUI shim + IceCubesShims. See fetch-upstream.sh.
let iceCubesUpstreamPresent: Bool = upstreamPresent(".upstream/icecubes/Packages/Models/Sources/Models")

// The vendored-IceCubes Linux graph (Models → … → IceCubesLinuxApp) builds
// under gtk (default) and — for the dual-backend mission — under qt when the
// generic SwiftOpenUI→Qt backend is enabled (QUILLUI_QT_GENERIC=1). The plain
// qt build resets the target graph and never sees these targets.
#if os(Linux)
// The vendored-IceCubes flagship lane does not yet CLEAN-build on Linux: a
// per-package onion of standard SwiftUI shim gaps (onHover/contentShape/
// minimumScaleFactor/foregroundStyle-palette/Font.footnote/… across
// DesignSystem → AppAccount → StatusKit → Timeline → …) was masked by warm
// build caches and only surfaces on CI's clean build, so `swift test` (the
// hard Linux gate) fails to compile it — blocking every PR. Make it opt-in
// while the shim-completion campaign drives it to clean-green, exactly like
// the NNW-slice and WireGuard-conformance-UI gates. The shim additions in
// this PR (QuillSwiftUICompatibility/IceCubesDesignSystemModifiers.swift) are
// real progress toward re-enabling; enable with QUILLUI_ICECUBES=1.
let iceCubesLinuxGraphEnabled = iceCubesUpstreamPresent
    && ProcessInfo.processInfo.environment["QUILLUI_ICECUBES"] == "1"
    && (quillUILinuxBuildBackend == .gtk
        || (quillUILinuxBuildBackend == .qt && quillUIQtGenericEnabled))

// The SwiftUI shim renders through exactly one backend: BackendGTK4 (a
// SwiftOpenUI product) by default, or the in-package BackendQt target under
// the qt-generic dual-backend path. The plain qt build resets the target
// graph and never builds the shim, so its dormant BackendGTK4 reference is
// unchanged there.
let swiftUIShimBackendDependency: Target.Dependency =
    (quillUILinuxBuildBackend == .qt && quillUIQtGenericEnabled)
    ? "BackendQt"
    : .product(name: "BackendGTK4", package: "SwiftOpenUI")
#else
let iceCubesLinuxGraphEnabled = false
#endif

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
    .library(name: "QuillObjCCompatibility", targets: ["QuillObjCCompatibility"]),
    .library(name: "QuillRS", targets: ["QuillRS"]),
    .library(name: "QuillUIKit", targets: ["QuillUIKit"]),
    .library(name: "QuillWebKit", targets: ["QuillWebKit"]),
    .library(name: "QuillShims", targets: ["QuillShims"]),
    .library(name: "WebKit", targets: ["WebKit"]),
    .library(name: "JavaScriptCore", targets: ["JavaScriptCore"]),
    .library(name: "Compression", targets: ["Compression"]),
    .library(name: "MediaPlayer", targets: ["MediaPlayer"]),
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
    .executable(name: "quill-lower-foundation", targets: ["quill-lower-foundation"]),
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
    .executable(name: "quill-render-mac-references", targets: ["quill-render-mac-references"])
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
    .library(name: "MobileCoreServices", targets: ["MobileCoreServices"]),
    .library(name: "WebKit", targets: ["WebKit"]),
    .library(name: "LinkPresentation", targets: ["LinkPresentation"]),
    .library(name: "AppIntents", targets: ["AppIntents"]),
    .library(name: "RevenueCat", targets: ["RevenueCat"]),
    .library(name: "WishKit", targets: ["WishKit"]),
    .library(name: "SFSafeSymbols", targets: ["SFSafeSymbols"])
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

if quillUILinuxBuildBackend == .gtk && signalUpstreamPresent && libsignalUpstreamPresent {
    // signal-ui-render: the UIKit→GTK4 renderer host. Renders real QuillUIKit
    // (and, wired up, SignalUI) UIViewController view trees to an on-screen
    // GTK window. First-light demo proves the pipeline; Signal's own VCs follow.
    products.append(.executable(name: "signal-ui-render", targets: ["SignalUIRender"]))
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
    .library(name: "CryptoKit", targets: ["CryptoKit"]),
    .library(name: "CoreImage", targets: ["CoreImage"]),
    .library(name: "AVFoundation", targets: ["AVFoundation"]),
    .library(name: "AVKit", targets: ["AVKit"]),
    .library(name: "Photos", targets: ["Photos"]),
    .library(name: "CoreTransferable", targets: ["CoreTransferable"]),
    .library(name: "QuickLook", targets: ["QuickLook"]),
    .library(name: "FoundationModels", targets: ["FoundationModels"]),
    .library(name: "Speech", targets: ["Speech"]),
    .library(name: "ApplicationServices", targets: ["ApplicationServices"]),
    .library(name: "ServiceManagement", targets: ["ServiceManagement"]),
    .library(name: "Alamofire", targets: ["Alamofire"]),
    .library(name: "MarkdownUI", targets: ["MarkdownUI"]),
    .library(name: "Splash", targets: ["Splash"]),
    .library(name: "ActivityIndicatorView", targets: ["ActivityIndicatorView"]),
	    .library(name: "ButtonKit", targets: ["ButtonKit"]),
	    .library(name: "WrappingHStack", targets: ["WrappingHStack"]),
	    .library(name: "Bodega", targets: ["Bodega"]),
	    .library(name: "SwiftUIIntrospect", targets: ["SwiftUIIntrospect"]),
	    .library(name: "Vortex", targets: ["Vortex"]),
    .library(name: "KeyboardShortcuts", targets: ["KeyboardShortcuts"]),
    .library(name: "PhotosUI", targets: ["PhotosUI"]),
    .library(name: "Magnet", targets: ["Magnet"]),
    .library(name: "Combine", targets: ["Combine"]),
    .library(name: "Observation", targets: ["Observation"]),
    .library(name: "Nuke", targets: ["Nuke"]),
    .library(name: "NukeUI", targets: ["NukeUI"]),
    .library(name: "EmojiText", targets: ["EmojiText"]),
    .library(name: "Gifu", targets: ["Gifu"]),
    .library(name: "Charts", targets: ["Charts"]),
    .library(name: "LRUCache", targets: ["LRUCache"]),
    .library(name: "OllamaKit", targets: ["OllamaKit"]),
    .library(name: "Sparkle", targets: ["Sparkle"]),
    .library(name: "IOKit", targets: ["IOKit"]),
    .library(name: "COSUnfairLock", targets: ["COSUnfairLock"]),
    .library(name: "NaturalLanguage", targets: ["NaturalLanguage"]),
    .library(name: "ImageIO", targets: ["ImageIO"]),
    .library(name: "Accelerate", targets: ["Accelerate"]),
    .library(name: "AudioToolbox", targets: ["AudioToolbox"]),
    .library(name: "CoreHaptics", targets: ["CoreHaptics"]),
    .library(name: "CoreImage", targets: ["CoreImage"]),
    .library(name: "CoreLocation", targets: ["CoreLocation"]),
    .library(name: "CoreSpotlight", targets: ["CoreSpotlight"]),
    .library(name: "QuartzCore", targets: ["QuartzCore"]),
    .library(name: "CoreText", targets: ["CoreText"]),
    .library(name: "CoreVideo", targets: ["CoreVideo"]),
    .library(name: "CoreMedia", targets: ["CoreMedia"]),
    .library(name: "Vision", targets: ["Vision"]),
    .library(name: "VideoToolbox", targets: ["VideoToolbox"]),
    .library(name: "IOSurface", targets: ["IOSurface"]),
    .library(name: "LinkPresentation", targets: ["LinkPresentation"]),
    .library(name: "Metal", targets: ["Metal"]),
    .library(name: "MetalKit", targets: ["MetalKit"]),
    .library(name: "MetalPerformanceShaders", targets: ["MetalPerformanceShaders"]),
    .library(name: "StoreKit", targets: ["StoreKit"]),
    // Telegram-Mac app-target products.
    .library(name: "AVKit", targets: ["AVKit"]),
    .library(name: "Quartz", targets: ["Quartz"]),
    .library(name: "QuickLook", targets: ["QuickLook"]),
    .library(name: "Contacts", targets: ["Contacts"]),
    .library(name: "OSLog", targets: ["OSLog"]),
    .library(name: "AppIntents", targets: ["AppIntents"]),
    .library(name: "CoreMediaIO", targets: ["CoreMediaIO"]),
    .library(name: "MapKit", targets: ["MapKit"]),
    .library(name: "SceneKit", targets: ["SceneKit"]),
    .library(name: "RealityKit", targets: ["RealityKit"]),
    .library(name: "Firebase", targets: ["Firebase"]),
    .library(name: "FirebaseCrashlytics", targets: ["FirebaseCrashlytics"]),
    .library(name: "Lottie", targets: ["Lottie"]),
    .library(name: "TdBinding", targets: ["TdBinding"]),
    .library(name: "UserNotifications", targets: ["UserNotifications"]),
    .library(name: "CoreServices", targets: ["CoreServices"]),
    .library(name: "LocalAuthentication", targets: ["LocalAuthentication"]),
    .library(name: "Zip", targets: ["Zip"])
]
#endif

#if os(Linux)
let appKitShadowDependencies: [Target.Dependency] = [
    "QuillFoundation", "QuillUIKit", "QuillKit",
    "QuartzCore", "CoreVideo", "ImageIO", "CoreText", "CoreImage", "CoreServices",
    // NSBitmapImageRep's real raster encode (rung 4) goes through gdk-pixbuf.
    "CGdkPixbuf",
]
let quillWebKitDependencies: [Target.Dependency] = ["QuillFoundation", "AppKit"]
// UIView.layer: on Linux, QuillUIKit (and the UIKit umbrella that re-exports
// it) needs the in-tree QuartzCore shim. On Apple platforms CALayer comes from
// the real QuartzCore via AppKit/UIKit — and the shim target doesn't exist, so
// the dependency must vanish entirely (a `.when(platforms:)` condition would
// still dangle: SwiftPM validates named targets even when the condition is off).
let quillUIKitDependencies: [Target.Dependency] = [
    "QuillFoundation", "QuillKit", "CoreGraphics", "QuartzCore",
    "CoreTransferable", "UniformTypeIdentifiers",
]
let uiKitShimDependencies: [Target.Dependency] =
    ["QuillFoundation", "QuillUIKit", "QuillKit", "CoreGraphics", "UserNotifications", "QuartzCore", "CoreTransferable", "CoreText"]
// V4L2 capture backend (#515): Linux-only system library; Apple graphs
// keep the pure compile-surface AVFoundation.
let quillV4L2Dependencies: [Target.Dependency] = ["CV4L2"]
#else
let appKitShadowDependencies: [Target.Dependency] = [
    "QuillFoundation", "QuillUIKit", "QuillKit",
]
let quillWebKitDependencies: [Target.Dependency] = ["QuillFoundation"]
let quillUIKitDependencies: [Target.Dependency] = ["QuillFoundation", "QuillKit"]
let uiKitShimDependencies: [Target.Dependency] =
    ["QuillFoundation", "QuillUIKit", "QuillKit", "UserNotifications"]
let quillV4L2Dependencies: [Target.Dependency] = []
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
    "CoreTransferable",
    "UIKit",
    "UniformTypeIdentifiers",
    "Observation",
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
let wrappingHStackDependencies: [Target.Dependency] = [
    "SwiftUI",
    "Observation",
    .product(name: "BackendGTK4", package: "SwiftOpenUI"),
    .product(name: "CGTK", package: "SwiftOpenUI"),
    .product(name: "CGTKBridge", package: "SwiftOpenUI"),
]
#else
let wrappingHStackDependencies: [Target.Dependency] = []
#endif

#if os(Linux)
let quillChatKitDependencies: [Target.Dependency] = ["QuillFoundation", "SwiftUI"]
#else
let quillChatKitDependencies: [Target.Dependency] = ["QuillFoundation"]
#endif

let nnwSwiftSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v5),
    // -module-alias: NNW's Account module is compiled as target "NNWAccount"
    // because the vendored-IceCubes lane also ships a module named Account
    // (Sources/IceCubesAccountModuleAlias) and SwiftPM forbids two targets
    // with one name in a package — the default CI fetch populates BOTH
    // upstreams, which collided once NNW upstream's Modules/ restructure
    // flipped nnwUpstreamPresent true. The alias keeps NNW's unmodified
    // sources' `import Account` resolving to NNWAccount; targets that don't
    // import Account ignore it.
    .unsafeFlags(["-module-alias", "Account=NNWAccount"]),
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

#if os(Linux)
let quillSwiftTestingAppleOverlaySwiftSettings: [SwiftSetting] = appSwiftSettings + [
    // Swift Testing declares platform cross-import overlays such as
    // _Testing_UIKit/_Testing_CoreImage on Apple SDKs. Linux test targets
    // intentionally import QuillUI's shadow Apple modules, so disable those
    // SDK overlay lookups when Testing and SwiftUI/AppKit/UIKit meet.
    .unsafeFlags(["-Xfrontend", "-disable-cross-import-overlays"])
]
#else
let quillSwiftTestingAppleOverlaySwiftSettings: [SwiftSetting] = appSwiftSettings
#endif

#if os(Linux)
let quillArticlesDependencies: [Target.Dependency] = ["QuillRSCoreShim", "os"]
// QuillRSCoreShim's vendored Cache uses OSAllocatedUnfairLock via `import os`
// (the os shadow target on Linux), same as Articles' AuthorCache.
let quillRSCoreShimDependencies: [Target.Dependency] = ["QuillFoundation", "os"]
let swiftUIIntrospectTargetDependencies: [Target.Dependency] = ["SwiftUI"]
#else
let quillArticlesDependencies: [Target.Dependency] = ["QuillRSCoreShim"]
let quillRSCoreShimDependencies: [Target.Dependency] = []
let swiftUIIntrospectTargetDependencies: [Target.Dependency] = []
#endif

// QuillIceCubesCore consumes the real vendored Models when present (gtk-Linux);
// gated so macOS / qt (where the Models target isn't built) keep the reimpl.
var quillIceCubesCoreDependencies: [Target.Dependency] = ["QuillUI", "QuillFoundation"]
var quillIceCubesCoreSwiftSettings: [SwiftSetting] = appSwiftSettings
#if os(Linux)
if iceCubesLinuxGraphEnabled {
    quillIceCubesCoreDependencies.append("Models")
    quillIceCubesCoreSwiftSettings.append(.define("ICECUBES_REAL_MODELS"))
}
#endif

#if os(Linux)
let quillShimsDependencies: [Target.Dependency] = [
    "QuillKit", "QuillData", "QuillSwiftUICompatibility", "CoreGraphics", "os",
    "QuillFoundation", "QuillWebKit", "QuillUIKit", "QuillRS",
    "AppKit", "UIKit", "Combine", "MessageUI", "SafariServices", "MobileCoreServices",
    "Zip", "Tidemark", "UniformTypeIdentifiers", "Network", "NetworkExtension",
    "KeychainSwift", "NetNewsWireContext"
]
#else
let quillShimsDependencies: [Target.Dependency] = [
    "QuillKit", "QuillData",
    "QuillFoundation", "QuillWebKit", "QuillUIKit", "QuillRS"
]
#endif

#if os(Linux)
let nnwLogicDependencies: [Target.Dependency] = [
    "RSCore", "NNWAccount", "Articles", "RSParser", "ArticlesDatabase",
    "RSWeb", "RSTree", "QuillShims", "Zip", "os"
]
#else
let nnwLogicDependencies: [Target.Dependency] = [
    "RSCore", "NNWAccount", "Articles", "RSParser", "ArticlesDatabase",
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
    "AVFoundation", "AudioToolbox", "Speech", "ApplicationServices",
    "ServiceManagement", "Alamofire", "MarkdownUI", "Splash",
    "ActivityIndicatorView", "ButtonKit", "WrappingHStack", "Vortex",
    "KeyboardShortcuts", "PhotosUI", "Magnet", "Combine",
    "OllamaKit", "Sparkle", "IOKit", "CoreSpotlight", "Vision", "KeychainSwift"
]
let quillLinuxCompatibilityModuleTestDependencies: [Target.Dependency] = [
    // "SwiftUI" comes from quillLinuxShimTestDependencies; keep it in that
    // shared list so SwiftPM passes the C module search paths for the
    // GTK-backed NSViewRepresentable mount everywhere the shadow is imported.
    "QuillUI", "QuillKit", "QuillFoundation", "SwiftData", "AppKit", "UIKit", "os"
] + quillLinuxShimTestDependencies
let quillLinuxCompatibilityModuleTestSwiftSettings: [SwiftSetting] = quillSwiftTestingAppleOverlaySwiftSettings
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
let wireGuardKitDependencies: [Target.Dependency] = ["WireGuardKitC", "WireGuardKitGo", "Network", "NetworkExtension"]
// All WireGuardKit Swift files now compile on Linux: DNSResolver / IPAddress+AddrInfo /
// PacketTunnelSettingsGenerator (engine networking, via the Network/NetworkExtension shims
// + os-gate/C-type patches) and WireGuardAdapter (the Go-engine bridge, over the
// WireGuardKitGo Linux stub shim). Nothing left to exclude.
let wireGuardKitExcludes: [String] = []
#else
let wireGuardKitDependencies: [Target.Dependency] = ["WireGuardKitC"]
let wireGuardKitExcludes: [String] = ["WireGuardAdapter.swift"]
#endif

var quillDataPackageDependencies: [Package.Dependency] = [
    .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "600.0.0"),
    .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0")
]
// SwiftProtobuf is Signal-only (SSK's *.pb.swift wire format), while swift-crypto
// is now a general Linux Apple-framework shim dependency because both Signal and
// IceCubes import CryptoKit.
if signalUpstreamPresent {
    quillDataPackageDependencies.append(
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.36.1")
    )
}

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
// swift-syntax's SwiftSyntaxBuilder/SwiftParser have a `#if canImport(os)`
// logging path. In this workspace `canImport(os)` can find the os SHADOW
// module once it's built (SwiftPM exposes sibling modules in the shared
// build dir), and then executables/plugins linking these targets need the
// os symbols — a failed macro-plugin link surfaces as bare `error: fatalError`
// "Corrupted JSON" diagnostics. Declaring the dependency makes the link
// deterministic. Empty on Apple platforms (real os framework; no shim target).
// gtk-graph only: the qt manifest graph does not declare the os shadow
// target (and without the module present, the canImport(os) race this dep
// neutralizes cannot occur there).
#if os(Linux)
let swiftSyntaxOSLinkDependencies: [Target.Dependency] =
    quillUILinuxBuildBackend == .gtk ? ["os"] : []
#else
let swiftSyntaxOSLinkDependencies: [Target.Dependency] = []
#endif

// The SwiftUI SHADOW target exists only on Linux; on Apple platforms
// `import SwiftUI` is the real SDK and there is no target to depend on.
#if os(Linux)
let swiftUIShadowTestDependencies: [Target.Dependency] = ["SwiftUI"]
#else
let swiftUIShadowTestDependencies: [Target.Dependency] = []
#endif

// The representable GTK mount rides only in the gtk graph; the Qt mount rides
// only in the opt-in generic Qt graph. The default qt graph keeps the SwiftUI
// shadow out entirely, so native Qt app builds stay SwiftOpenUI/GTK-free.
#if os(Linux)
let swiftUIShadowMountDependencies: [Target.Dependency] =
    quillUILinuxBuildBackend == .gtk
    ? ["QuillAppKitGTK", "Observation", swiftUIShimBackendDependency]
    : (quillUILinuxBuildBackend == .qt && quillUIQtGenericEnabled ? ["QuillAppKitQt", "Observation", swiftUIShimBackendDependency] : [])
let swiftUIShadowMountSwiftSettings: [SwiftSetting] = {
    if quillUILinuxBuildBackend == .gtk {
        return [.define("QUILLUI_SWIFTUI_GTK_MOUNT"), .unsafeFlags(gtk4SwiftImporterFlags)]
    }
    if quillUILinuxBuildBackend == .qt && quillUIQtGenericEnabled {
        // Phase-1 Qt representable mount (drawing host); see #535.
        return [.define("QUILLUI_SWIFTUI_QT_MOUNT")]
    }
    return []
}()
// Core deps for the SwiftUI shadow per graph (codex-535 helper, re-added):
// the qt-generic path keeps QuillUI out of the shadow's closure.
let swiftUIShadowCoreDependencies: [Target.Dependency] =
    quillUILinuxBuildBackend == .qt && quillUIQtGenericEnabled
        ? ["QuillSwiftUICompatibility", "AppKit", "Combine"]
        : ["QuillUI", "QuillSwiftUICompatibility", "AppKit", "Combine"]
#endif

let quillDataMacroTarget: Target = .macro(
    name: "QuillDataMacros",
    dependencies: [
        .product(name: "SwiftSyntax", package: "swift-syntax"),
        .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
        .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
        .product(name: "SwiftCompilerPlugin", package: "swift-syntax")
    ] + swiftSyntaxOSLinkDependencies,
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
    .target(
        name: "QuillObjCCompatibility",
        path: "Sources/QuillObjCCompatibility",
        publicHeadersPath: "include"
    ),
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
        dependencies: ["QuillUI", "QuillPaintCairo", "CCairo"],
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
        // NO pkgConfig here (SourceHygiene contract): SwiftPM's native
        // pkg-config emits prohibited-flag warnings, so gtk flags route
        // through the filtered helpers. Consumers that import CGtk4 carry
        // gtk4SwiftImporterFlags; modules that embed it as an implementation
        // detail (the SwiftUI shadow's GTK mount) use @_implementationOnly
        // imports so their swiftmodules never expose CGtk4 to flagless
        // dependents.
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
        // "os": swift-syntax's SwiftSyntaxBuilder/SwiftParser have a
        // `#if canImport(os)` logging path. In this workspace `canImport(os)`
        // can find the os SHADOW module once it's built (SwiftPM exposes
        // sibling modules in the shared build dir), and then every executable
        // linking QuillSourceLowering needs the os symbols. Declaring the dep
        // here makes the link deterministic instead of build-order-dependent.
        dependencies: [
            .product(name: "SwiftSyntax", package: "swift-syntax"),
            .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
            .product(name: "SwiftParser", package: "swift-syntax")
        ] + swiftSyntaxOSLinkDependencies,
        path: "Sources/QuillSourceLowering"
    ),
    .executableTarget(
        name: "quill-source-lower",
        dependencies: ["QuillSourceLowering"],
        path: "Sources/quill-source-lower"
    ),
    .executableTarget(
        name: "quill-lower-foundation",
        dependencies: ["QuillSourceLowering"],
        path: "Sources/quill-lower-foundation"
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
        dependencies: quillWebKitDependencies,
        path: "Sources/QuillWebKit"
    ),
    .target(
        name: "WebKit",
        dependencies: ["QuillWebKit"],
        path: "Sources/WebKitShim"
    ),
    .target(
        name: "JavaScriptCore",
        dependencies: [],
        path: "Sources/JavaScriptCoreShim"
    ),
    .target(
        name: "Compression",
        dependencies: [],
        path: "Sources/CompressionShim"
    ),
    .target(
        name: "MediaPlayer",
        dependencies: ["QuillFoundation"],
        path: "Sources/MediaPlayerShim"
    ),
    .target(
        name: "QuillUIKit",
        dependencies: quillUIKitDependencies,
        path: "Sources/QuillUIKit"
    ),
    .target(
        name: "QuillRS",
        dependencies: ["QuillFoundation", "QuillUIKit", "QuillKit", "QuillData"],
        path: "Sources/QuillRS"
    ),
    .target(
        name: "NetNewsWireContext",
        dependencies: ["QuillFoundation"],
        path: "Sources/NetNewsWireContext"
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
    // Pure-Swift replacements for NetNewsWire's RSDatabase ObjC/FMBD island.
    // The module names intentionally match upstream so imported NNW source can
    // keep `import RSDatabase` / `import RSDatabaseObjC` unchanged on Linux.
    .target(
        name: "RSDatabaseObjC",
        dependencies: ["CSQLite"],
        path: "Sources/RSDatabaseObjC",
        swiftSettings: appSwiftSettings
    ),
    .target(
        name: "RSDatabase",
        dependencies: ["RSDatabaseObjC"],
        path: "Sources/RSDatabaseShim",
        swiftSettings: appSwiftSettings
    ),
    .target(
        name: "SwiftData",
        dependencies: ["QuillData", .product(name: "SwiftOpenUI", package: "SwiftOpenUI")],
        path: "Sources/SwiftData"
    ),
    .target(name: "LRUCache", dependencies: [], path: "Sources/LRUCache"),
    .target(name: "Bodega", dependencies: [], path: "Sources/Bodega"),
    .target(name: "SwiftUIIntrospect", dependencies: swiftUIIntrospectTargetDependencies, path: "Sources/SwiftUIIntrospect"),
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
        dependencies: ["QuillUI", "QuillFoundation", "QuillRSParser", "QuillArticles", "QuillArticlesDatabase", "QuillData", "QuillFeedFinder", "QuillRSCoreShim"],
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
        dependencies: quillRSCoreShimDependencies,
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
        dependencies: quillArticlesDependencies,
        path: "Sources/QuillArticles",
        swiftSettings: appSwiftSettings
    ),
    // QuillData-backed ArticlesDatabase-compatible surface. This is the
    // first cross-platform replacement for upstream NetNewsWire's
    // FMDatabase/RSDatabase-backed article store: same key public type names,
    // but no ObjC SQLite wrapper dependency.
    .target(
        name: "QuillArticlesDatabase",
        dependencies: ["QuillArticles", "QuillData", "QuillRSParser"],
        path: "Sources/QuillArticlesDatabase",
        swiftSettings: appSwiftSettings
    ),
    // Minimal RSWeb shim — target named `RSWeb` so vendored `import RSWeb`
    // resolves to it verbatim. Grows toward real RSWeb as Account needs more.
    .target(
        name: "RSWeb",
        dependencies: ["QuillRSCoreShim"],
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
    // Vendored Ranchero-Software/NetNewsWire ActivityLog module.
    // Upstream FeedFinder and account refresh paths now depend on this
    // Foundation-only activity lifecycle model, so keep the module name
    // upstream-shaped (`ActivityLog`) to allow later imports to stay verbatim.
    .target(
        name: "ActivityLog",
        path: "Sources/QuillActivityLog",
        resources: [.process("Resources")],
        swiftSettings: appSwiftSettings
    ),
    // Vendored Ranchero-Software/NetNewsWire FeedFinder module
    // (Sources/FeedFinder → Sources/QuillFeedFinder). Brings up the
    // network-free part of FeedFinder: HTMLFeedFinder (detects feeds in
    // already-fetched HTML via QuillRSParser) + FeedSpecifier (candidate-feed
    // model + scoring/merging). Named QuillFeedFinder to avoid the dead
    // upstream `FeedFinder` target name; consuming code rewrites
    // `import FeedFinder` → `import QuillFeedFinder` like the other vendored
    // modules. `FeedFinder.find()` (live download) is deferred until RSWeb's
    // Downloader + RSCore's Data.isProbablyHTML are brought up.
    .target(
        name: "QuillFeedFinder",
        dependencies: ["QuillRSCoreShim", "QuillRSParser", "RSWeb", "ActivityLog"],
        path: "Sources/QuillFeedFinder",
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
            name: "NNWAccount",
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

#if os(Linux)
if nnwUpstreamEnabled {
    targets += [
        .target(
            name: "RSCore",
            dependencies: ["QuillRSCoreShim", "UIKit"],
            path: "Sources/RSCoreShimModule",
            swiftSettings: appSwiftSettings
        ),
        .target(
            name: "Articles",
            dependencies: ["QuillArticles"],
            path: "Sources/ArticlesShimModule",
            swiftSettings: appSwiftSettings
        ),
        .target(
            name: "RSParser",
            dependencies: ["QuillRSParser"],
            path: "Sources/RSParserShimModule",
            swiftSettings: appSwiftSettings
        ),
        .target(
            name: "ArticlesDatabase",
            dependencies: ["RSCore", "RSParser", "Articles", "RSDatabase", "RSDatabaseObjC", "QuillShims", "os"],
            path: ".upstream/netnewswire/Modules/ArticlesDatabase/Sources/ArticlesDatabase",
            swiftSettings: nnwSwiftSettings
        ),
        .target(
            name: "SyncDatabase",
            dependencies: ["RSCore", "Articles", "RSDatabase", "RSDatabaseObjC", "QuillShims"],
            path: ".upstream/netnewswire/Modules/SyncDatabase/Sources/SyncDatabase",
            swiftSettings: nnwSwiftSettings
        ),
        .target(
            name: "ErrorLog",
            dependencies: ["RSCore", "RSDatabase", "RSDatabaseObjC", "QuillShims"],
            path: ".upstream/netnewswire/Modules/ErrorLog/Sources/ErrorLog",
            swiftSettings: nnwSwiftSettings
        ),
        .target(
            name: "FeedFinder",
            dependencies: ["RSWeb", "RSParser", "RSCore", "ActivityLog", "QuillShims", "os"],
            path: ".upstream/netnewswire/Modules/FeedFinder/Sources/FeedFinder",
            swiftSettings: nnwSwiftSettings
        ),
        .target(
            name: "NewsBlur",
            dependencies: ["Secrets", "RSWeb", "RSParser", "RSCore", "QuillShims", "os"],
            path: ".upstream/netnewswire/Modules/NewsBlur/Sources/NewsBlur",
            swiftSettings: nnwSwiftSettings
        ),
        .target(
            // Module "Account" to NNW's unmodified sources via -module-alias
            // in nnwSwiftSettings (the IceCubes lane owns the bare name).
            name: "NNWAccount",
            dependencies: [
                "RSCore", "Articles", "RSParser", "RSDatabase", "RSDatabaseObjC",
                "ArticlesDatabase", "SyncDatabase", "RSWeb", "Secrets", "ErrorLog",
                "ActivityLog", "FeedFinder", "NewsBlur", "AuthenticationServices",
                "QuillShims", "os"
            ],
            path: ".upstream/netnewswire/Modules/Account/Sources/Account",
            exclude: ["CloudKit"],
            swiftSettings: nnwSwiftSettings
        ),
    ]
}
#endif

if nnwUpstreamEnabled {
    targets += [
        .target(
            name: "Images",
            // NNW's Account compiles as the NNWAccount target (the bare
            // "Account" belongs to the IceCubes lane); this in-repo shim
            // imports it directly (no module-alias, so it uses the real
            // target name rather than NNW's aliased `import Account`).
            dependencies: ["NNWAccount", "Articles", "RSCore"],
            path: "Sources/ImagesShimModule",
            swiftSettings: appSwiftSettings
        )
    ]

    targets += [
        .target(
            name: "NetNewsWireSharedCore",
            dependencies: ["NNWAccount", "ActivityLog", "AppKit", "Articles", "ArticlesDatabase", "Images", "QuillShims", "RSCore", "RSParser", "RSTree", "SwiftUI", "UIKit"],
            path: ".upstream/netnewswire/Shared",
            exclude: [
                "Activity/ActivityManager.swift",
                "Article Extractor/ArticleExtractor.swift",
                "Article Rendering/ArticleRenderer.swift",
                "Article Rendering/WebViewConfiguration.swift",
                "DefaultAccountNames.xcstrings",
                "Localizable.xcstrings",
                "Article Rendering/core.css",
                "Article Rendering/main.js",
                "Article Rendering/newsfoot.js",
                "Article Rendering/stylesheet.css",
                "Article Rendering/template.html",
                "ArticleStyles/ArticleTheme.swift",
                "ArticleStyles/ArticleThemeDownloader.swift",
                "ArticleStyles/ArticleThemesManager.swift",
                "Commands/DeleteCommand.swift",
                "ExtensionPoints",
                "Extensions/IconImageView.swift",
                "Extensions/NSAttributedString+Extensions.swift",
                "Resources",
                "ShareExtension/SafariExt.js",
                "Timeline/FetchRequestOperation.swift",
                "Timeline/FetchRequestQueue.swift",
                "Tree",
                "Widget/WidgetDataDecoder.swift",
                "Widget/WidgetDataEncoder.swift",
            ],
            sources: [
                "AccountType+Helpers.swift",
                "AccountStats/AccountStatsViewModel.swift",
                "ActivityLog/ActivityLogViewModel.swift",
                "Activity/ActivityType.swift",
                "AppNotifications.swift",
                "Assets.swift",
                "Article Extractor/ExtractedArticle.swift",
                "Article Rendering/ArticleRenderingSpecialCases.swift",
                "Article Rendering/ArticleTextSize.swift",
                "ArticleStyles/ArticleTheme+Notifications.swift",
                "ArticleSpecifier.swift",
                "ArticleStyles/ArticleThemePlist.swift",
                "Commands/MarkCommandValidationStatus.swift",
                "Commands/MarkStatusCommand.swift",
                "CurrentActivity/CurrentActivityViewModel.swift",
                "Dinosaurs/DinosaursViewModel.swift",
                "Extensions/ArticleStringFormatter.swift",
                "Extensions/ArticleUtilities.swift",
                "Extensions/AddFeedDefaultContainer.swift",
                "Extensions/CacheCleaner.swift",
                "Extensions/Node+Extensions.swift",
                "Extensions/RSImage+Extensions.swift",
                "Extensions/SmallIconProvider.swift",
                "Exporters/OPMLExporter.swift",
                "HelpURL.swift",
                "IconImageCache.swift",
                "Importers/DefaultFeedsImporter.swift",
                "Settings/AddCloudKitAccount.swift",
                "ShareExtension/ExtensionContainers.swift",
                "ShareExtension/ExtensionContainersFile.swift",
                "ShareExtension/ExtensionFeedAddRequest.swift",
                "ShareExtension/ExtensionFeedAddRequestFile.swift",
                "ShareExtension/ShareDefaultContainer.swift",
                "SmartFeeds/PseudoFeed.swift",
                "SmartFeeds/SearchFeedDelegate.swift",
                "SmartFeeds/SearchTimelineFeedDelegate.swift",
                "SmartFeeds/SmartFeed.swift",
                "SmartFeeds/SmartFeedDelegate.swift",
                "SmartFeeds/SmartFeedPasteboardWriter.swift",
                "SmartFeeds/SmartFeedsController.swift",
                "SmartFeeds/StarredFeedDelegate.swift",
                "SmartFeeds/TodayFeedDelegate.swift",
                "SmartFeeds/UnreadFeed.swift",
                "Timeline/ArticleArray.swift",
                "Timeline/ArticleSorter.swift",
                "Timer/AccountRefreshTimer.swift",
                "Timer/ArticleStatusSyncTimer.swift",
                "Timer/RefreshInterval.swift",
                "UserInfoKey.swift",
                "UserNotifications/UserNotificationManager.swift",
                "Widget/WidgetData.swift",
                "Widget/WidgetDataDecoder.swift",
                "Widget/WidgetDeepLinks.swift",
            ],
            resources: [.process("Importers/DefaultFeeds.opml")],
            swiftSettings: nnwSwiftSettings
        )
    ]
}

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
//
// Collected into a shared array (not appended to `targets` directly) so BOTH the
// default/GTK graph AND the qt graph can include this GTK-free WireGuard
// conformance dep-tree — the qt graph's wholesale `targets =` reassignment would
// otherwise discard these default-graph appends. Appended to `targets` for the
// default graph immediately after the block; the qt branch appends it too.
var wireGuardConformanceTargets: [Target] = []
if wireguardUpstreamPresent {
    wireGuardConformanceTargets += [
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
            swiftSettings: [
                .swiftLanguageMode(.v5),
                .unsafeFlags(["-strict-concurrency=minimal", "-default-isolation", "MainActor"])
            ]
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
    wireGuardConformanceTargets.append(
        .target(
            name: "WireGuardRingLoggerC",
            path: ".upstream/wireguard-apple/Sources/Shared/Logging",
            exclude: ["Logger.swift", "test_ringlogger.c"],
            sources: ["ringlogger.c"],
            publicHeadersPath: "."
        )
    )
    // Vendored minizip (Sources/WireGuardApp/ZipArchive/3rdparty/minizip) — the
    // zip/unzip C backing ZipArchive.swift uses (zipOpen / unzOpen64 / …). Links
    // system zlib (-lz); bzip2 is `#ifdef HAVE_BZIP2`-guarded so we don't define
    // it (no libbz2 needed). zlib.h resolves via the system include path. Same
    // shape as WireGuardRingLoggerC.
    wireGuardConformanceTargets.append(
        .target(
            name: "WireGuardMinizipC",
            path: ".upstream/wireguard-apple/Sources/WireGuardApp/ZipArchive/3rdparty/minizip",
            exclude: ["MiniZip64_info.txt"],
            sources: ["zip.c", "unzip.c", "ioapi.c"],
            publicHeadersPath: ".",
            linkerSettings: [.linkedLibrary("z")]
        )
    )
    // highlighter.c — WireGuard's wg-quick-config syntax highlighter (the
    // `enum highlight_type` { HighlightSection, HighlightField, … } + highlight_config
    // span scanner) backing ConfTextStorage/ConfTextColorTheme. Self-contained POSIX
    // C (no external lib). It shares the View/ dir with the conformance target's
    // .swift cells, so exclude those (the C target compiles only highlighter.c;
    // highlighter.h is its public header) — same overlap pattern as WireGuardRingLoggerC.
    wireGuardConformanceTargets.append(
        .target(
            name: "WireGuardHighlighterC",
            path: ".upstream/wireguard-apple/Sources/WireGuardApp/UI/macOS/View",
            exclude: ["ButtonRow.swift", "ConfTextColorTheme.swift", "ConfTextStorage.swift",
                      "ConfTextView.swift", "DeleteTunnelsConfirmationAlert.swift", "KeyValueRow.swift",
                      "LogViewCell.swift", "OnDemandWiFiControls.swift", "TunnelListRow.swift"],
            sources: ["highlighter.c"],
            publicHeadersPath: "."
        )
    )
    if wireGuardConformanceUIEnabled {
    wireGuardConformanceTargets.append(
        .target(
            name: "QuillWireGuardConformanceUI",
            dependencies: ["Cocoa", "NetworkExtension", "os", "WireGuardRingLoggerC", "WireGuardMinizipC", "WireGuardHighlighterC", "CoreWLAN", "LocalAuthentication", "ServiceManagement", "Security", "WireGuardKit", "QuillWireGuardUpstreamConfig", "QuillFoundation"],
            path: ".upstream/wireguard-apple",
            sources: [
                // Shared logging: Logger.swift (wg_log) over the ringlogger C
                // ring buffer (import WireGuardRingLoggerC) + the `os` shadow.
                "Sources/Shared/Logging/Logger.swift",
                // Shared Keychain: SecItem* + the legacy macOS keychain-ACL APIs
                // (SecTrustedApplication/SecAccess) via the Security shim. wg_log
                // for failures. No real keychain on Linux (compile-only).
                "Sources/Shared/Keychain.swift",
                // Shared FileManager+Extension: app-group / log-file URLs + deleteFile;
                // Foundation + os/wg_log. (networkExtensionLastErrorFileURL used by TunnelsManager.)
                "Sources/Shared/FileManager+Extension.swift",
                // NETunnelProviderProtocol+Extension: defines PacketTunnelProviderError
                // + the protocol<->TunnelConfiguration bridge. Breaks the modularity
                // wall via fetch-upstream patches (asWgQuickConfig/fromWgQuickConfig
                // made public in QuillWireGuardUpstreamConfig + import patch).
                "Sources/Shared/Model/NETunnelProviderProtocol+Extension.swift",
                // TunnelErrors: WireGuardAppError conformances + localizedUIString;
                // needs PacketTunnelProviderError (above) + tr + NEVPNError + wg_log.
                "Sources/WireGuardApp/Tunnel/TunnelErrors.swift",
                // TunnelsManager + TunnelContainer (the model layer core). Uses KVO
                // (observe(\.status)) + objc_*AssociatedObject — compile shims in
                // QuillFoundation; splitToArray made public in UpstreamConfig.
                // TunnelConfiguration+UapiConfig: the UAPI parser (fromUapiConfig:basedOn:),
                // used by TunnelsManager. Uses ParserState/ParseError (made public).
                "Sources/WireGuardApp/Tunnel/TunnelConfiguration+UapiConfig.swift",
                "Sources/WireGuardApp/Tunnel/TunnelsManager.swift",
                // TunnelViewModel: config edit/validation VM (pure Foundation +
                // WireGuardKit + splitToArray; no AppKit/KVO). Used by TunnelEdit/Detail VCs.
                "Sources/WireGuardApp/UI/TunnelViewModel.swift",
                // ActivateOnDemandViewModel: on-demand config edit VM (Foundation;
                // TunnelContainer + ActivateOnDemandOption, both in-target). Dep of
                // TunnelEditViewController + TunnelDetailTableViewController.
                "Sources/WireGuardApp/UI/ActivateOnDemandViewModel.swift",
                // Error presentation: ErrorPresenterProtocol + macOS ErrorPresenter
                // (NSAlert-based; WireGuardAppError -> alert). Used by the VCs.
                "Sources/WireGuardApp/UI/ErrorPresenterProtocol.swift",
                "Sources/WireGuardApp/UI/macOS/ErrorPresenter.swift",
                // TunnelListRow: NSView cell binding to a TunnelContainer via KVO
                // (observe(\.name)/(\.status)) — exercises the KVO shims (#355).
                "Sources/WireGuardApp/UI/macOS/View/TunnelListRow.swift",
                // Log viewer support files: LogViewHelper (reads the ringlogger C
                // ring buffer → timestamped entries; import WireGuardRingLoggerC) +
                // LogViewCell (NSTableCellView; lowered to conform to QuillReusableView
                // so it's dequeuable). LogViewController itself is still deferred on C
                // (cancelOperation override-from-extension); its A wall (the @Sendable
                // Timer block) is now solved by QuillTimer.make + the lowering rewrite.
                "Sources/WireGuardApp/UI/LogViewHelper.swift",
                "Sources/WireGuardApp/UI/macOS/View/LogViewCell.swift",
                // NSTableView+Reuse: the generic dequeueReusableCell<T: NSView &
                // QuillReusableView>() the tables use — the B-wall fix (the cell type
                // is constrained to a protocol requiring init(), so T() compiles
                // without forcing required init() onto NSView repo-wide).
                "Sources/WireGuardApp/UI/macOS/NSTableView+Reuse.swift",
                // LogViewController: the NSTableView-backed log viewer — the first full
                // VC that needed ALL THREE concurrency/init/extension walls solved:
                // A (its @Sendable Timer → QuillTimer.make via the lowering),
                // B (dequeues LogViewTimestampCell/LogViewMessageCell, which conform to
                //    QuillReusableView with required init()),
                // C (its `override func cancelOperation` lives in an `extension` —
                //    the lowering moves it into the class body so the override is legal
                //    without an ObjC runtime).
                "Sources/WireGuardApp/UI/macOS/ViewController/LogViewController.swift",
                // ParseError+WireGuardAppError: retroactively conforms WireGuardKit's
                // TunnelConfiguration.ParseError (public enum in QuillWireGuardUpstreamConfig)
                // to the app's WireGuardAppError → localized alertText. Foundation-only
                // logic (tr + AlertText, both already here); no AppKit/concurrency surface.
                "Sources/WireGuardApp/UI/macOS/ParseError+WireGuardAppError.swift",
                // DeleteTunnelsConfirmationAlert: NSAlert subclass (delete confirmation).
                "Sources/WireGuardApp/UI/macOS/View/DeleteTunnelsConfirmationAlert.swift",
                // Shared NotificationToken: a Foundation-only NotificationCenter
                // observer wrapper (+ NotificationCenter.observe); used by the model
                // layer (TunnelsManager/LogViewController). No ObjC.
                "Sources/Shared/NotificationToken.swift",
                // First real MODEL file: TunnelStatus maps NEVPNStatus -> app
                // status, compiling against the NetworkExtension shadow (uses
                // NEVPNStatus incl. .reasserting, #338). Its @objc enum is
                // stripped by fetch-upstream's (now whole-app) lowering. Grows
                // this target toward the single-app-module.
                "Sources/WireGuardApp/Tunnel/TunnelStatus.swift",
                // StatusItemController: the macOS menu-bar status item (NSStatusBar/
                // NSStatusItem + an animated NSImage on a Timer). Binds a
                // TunnelContainer's status to the status-bar icon. Plain class (not
                // @MainActor); its Timer closure touches only non-@MainActor members,
                // so it compiles whether or not the lowering rewrites the Timer to
                // QuillTimer.make. No table (no dequeueReusableCell/B), no extension
                // override (C). Needs NSStatusItem.squareLength (added to the shadow).
                "Sources/WireGuardApp/UI/macOS/StatusItemController.swift",
                // MainMenu: the macOS menu bar (NSMenu subclass) — App/File/Edit/Tunnel/Window
                // submenus built with NSMenu.addItem(withTitle:action:keyEquivalent:) +
                // NSMenuItem.separator() + keyEquivalentModifierMask; actions are Selector("…")
                // routed to NSApp/NSApp.delegate/responder chain (no @objc methods of its own).
                // First file of the app-BOOTSTRAP layer (after the full VC/view layer).
                "Sources/WireGuardApp/UI/macOS/MainMenu.swift",
                // StatusMenu: the status-bar dropdown (NSMenu subclass) + TunnelMenuItem
                // (NSMenuItem subclass observing tunnel name/status via KVO). Builds the
                // per-tunnel menu, manage/import/about/quit items; @objc actions lowered to
                // an injected quillPerform (QuillSelectorDispatching). The biggest bootstrap
                // file; dep of TunnelsTracker.
                "Sources/WireGuardApp/UI/macOS/StatusMenu.swift",
                // TunnelsTracker: observes each tunnel's status (KVO) + the TunnelsManager
                // list/activation delegates, forwarding changes to StatusMenu / StatusItemController /
                // ManageTunnelsRootViewController.tunnelsListVC (all in-target). Plain class,
                // import Cocoa, ErrorPresenter for activation failures.
                "Sources/WireGuardApp/UI/macOS/TunnelsTracker.swift",
                // LaunchedAtLoginDetector + MacAppStoreUpdateDetector: inspect the open/quit
                // Apple events (NSAppleEventDescriptor + kCoreEventClass/kAEOpenApplication/
                // kAEQuitApplication/keySenderPIDAttr) and call Darwin C (clock_gettime_nsec_np/
                // proc_pidpath) — all shadowed in QuillFoundation/AppleEventsShim.swift (Linux:
                // these features don't exist, so compile-faithful stubs). FileManager.loginHelperTimestampURL ✓.
                "Sources/WireGuardApp/UI/macOS/LaunchedAtLoginDetector.swift",
                "Sources/WireGuardApp/UI/macOS/MacAppStoreUpdateDetector.swift",
                // AppDelegate/Application remain intentionally deferred from this
                // Linux conformance target: the upstream app bootstrap is
                // @MainActor-heavy and still needs a stronger AppKit actor/AppleEvent
                // compatibility pass. The real model, menus, trackers, view
                // controllers, import/export flow, and network extension stay in
                // the conformance build so the useful WireGuard surface remains
                // compiled while CI stays green.
                // The NE EXTENSION (the macOS product's other half): PacketTunnelProvider
                // (NEPacketTunnelProvider subclass — startTunnel/stopTunnel/handleAppMessage
                // driving the now-complete WireGuardKit WireGuardAdapter) + ErrorNotifier.
                // Compiled alongside the app in this target (it already deps NetworkExtension
                // + WireGuardKit + os). Imports WireGuardKit via a fetch-upstream patch.
                "Sources/WireGuardNetworkExtension/PacketTunnelProvider.swift",
                "Sources/WireGuardNetworkExtension/ErrorNotifier.swift",
                // ActivateOnDemandOption: maps on-demand config <-> NEOnDemandRule[]
                // (NE on-demand surface from #338/#340 + wg_log from #345).
                "Sources/WireGuardApp/Tunnel/ActivateOnDemandOption.swift",
                // App error model: WireGuardAppError protocol + AlertText typealias
                // + WireGuardResult<T> — self-contained (Foundation only); used pervasively
                // by the rest of the model layer.
                "Sources/WireGuardApp/WireGuardAppError.swift",
                "Sources/WireGuardApp/WireGuardResult.swift",
                // ZIP subsystem (config import/export): ZipArchive wraps the vendored
                // minizip C (import WireGuardMinizipC) + zlib; ZipImporter/ZipExporter
                // are Foundation logic (parse/serialize .conf via wg-quick — import
                // WireGuardKit + QuillWireGuardUpstreamConfig). Critical path to
                // ImportPanelPresenter → TunnelsListTableViewController.
                "Sources/WireGuardApp/ZipArchive/ZipArchive.swift",
                "Sources/WireGuardApp/ZipArchive/ZipImporter.swift",
                "Sources/WireGuardApp/ZipArchive/ZipExporter.swift",
                // TunnelImporter: routes imported .zip/.conf URLs through ZipImporter
                // + the wg-quick parser into TunnelsManager.addMultiple (DispatchGroup).
                "Sources/WireGuardApp/UI/TunnelImporter.swift",
                // ImportPanelPresenter: NSOpenPanel (.conf/.zip) -> TunnelImporter.
                // @MainActor (UI presenter touching sourceVC.view.window); its caller is
                // the @MainActor VC action handleImportTunnelAction.
                "Sources/WireGuardApp/UI/macOS/ImportPanelPresenter.swift",
                "Sources/WireGuardApp/UI/macOS/View/KeyValueRow.swift",
                // ButtonRow: the action-button cell dequeued by TunnelDetailTableViewController
                // (NSButton momentaryPushIn/rounded + onButtonClicked). Conforms QuillReusableView
                // (required init()) for generic dequeue; target-action lowered to QuillSelectorDispatching.
                "Sources/WireGuardApp/UI/macOS/View/ButtonRow.swift",
                // NSColor+Hex: NSColor(hex:) convenience init (chains to the shadow's
                // new NSColor(red:green:blue:alpha:)). Foundation Scanner + AppKit only;
                // the color base for the conf-editor theme (ConfTextColorTheme, later).
                "Sources/WireGuardApp/UI/macOS/NSColor+Hex.swift",
                // ConfTextColorTheme: the conf-editor syntax color themes (Aqua +
                // DarkAqua) keyed by the highlighter C span types (HighlightSection
                // etc. — import WireGuardHighlighterC) → NSColor(hex:). First file of
                // the NSTextView text subsystem (ConfTextStorage/ConfTextView follow).
                "Sources/WireGuardApp/UI/macOS/View/ConfTextColorTheme.swift",
                // ConfTextStorage: NSTextStorage subclass — runs the highlighter C over
                // the wg-quick text + applies syntax colors (ConfTextColorTheme) to a
                // backing NSMutableAttributedString (import WireGuardHighlighterC). Uses
                // the shadow's new NSTextStorage designated init() + NSFontManager.convert/
                // convertWeight + NSFontTraitMask.
                "Sources/WireGuardApp/UI/macOS/View/ConfTextStorage.swift",
                // ConfTextView: NSTextView subclass (the wg-quick config editor) — the
                // LAST text-subsystem file. Hosts ConfTextStorage via a layout manager,
                // syntax-highlights on edit, themes via NSAppearance, NSTextViewDelegate.
                "Sources/WireGuardApp/UI/macOS/View/ConfTextView.swift",
                // OnDemandWiFiControls (OnDemandControlsRow): on-demand SSID controls
                // (NSTokenField + NSPopUpButton + CWWiFiClient SSIDs via CoreWLAN). Dep of
                // TunnelEditViewController + TunnelDetailTableViewController.
                "Sources/WireGuardApp/UI/macOS/View/OnDemandWiFiControls.swift",
                // TunnelEditViewController: the config-edit VC — the GATE for both table
                // VCs (each presents it). ConfTextView editor + KeyValueRow name/key fields
                // + OnDemandControlsRow + ActivateOnDemandViewModel + TunnelViewModel.
                // Imports WireGuardKit + QuillWireGuardUpstreamConfig (fetch-upstream patch);
                // @objc actions lowered; cancelOperation extension-override merged into class.
                "Sources/WireGuardApp/UI/macOS/ViewController/TunnelEditViewController.swift",
                // PrivateDataConfirmation: gates revealing a tunnel's private/pre-shared
                // key behind LAContext (import LocalAuthentication). Shared dep called by
                // BOTH remaining table VCs (TunnelsList + TunnelDetail). No auth backend
                // on Linux → the LocalAuthentication shadow always denies (safe default).
                "Sources/WireGuardApp/UI/PrivateDataConfirmation.swift",
                // TunnelDetailTableViewController: the tunnel-detail table VC (one of the two
                // remaining). Dequeues KeyValueRow/KeyValueImageRow/ButtonRow (all QuillReusableView);
                // presents TunnelEditViewController; PrivateDataConfirmation key-reveal gate;
                // ActivateOnDemandViewModel + TunnelViewModel; KVO via Cocoa shim; @objc actions
                // lowered to QuillSelectorDispatching. Imports WireGuardKit (TunnelConfiguration).
                "Sources/WireGuardApp/UI/macOS/ViewController/TunnelDetailTableViewController.swift",
                // TunnelsListTableViewController: the main tunnels list (the OTHER table VC).
                // NSPopUpButton add/action menus (popup.cell as? NSPopUpButtonCell — arrowPosition),
                // NSButton remove action, dequeues TunnelListRow (QuillReusableView ✓), declares its
                // own TunnelsListTableViewControllerDelegate, presents TunnelEditViewController for add;
                // NSMenuItemValidation; @objc actions lowered to QuillSelectorDispatching. import Cocoa only.
                "Sources/WireGuardApp/UI/macOS/ViewController/TunnelsListTableViewController.swift",
                // ManageTunnelsRootViewController: the SPLIT-VIEW ROOT — the LAST VC of the
                // WireGuard macOS UI. Hosts TunnelsListTableViewController (left) +
                // TunnelDetail/Unusable/Buttoned detail VCs (right) via addChild + Auto Layout
                // (NSLayoutGuide); routes toolbar/menu actions to children via
                // supplementalTarget(forAction:). import Cocoa only; no @objc (pre-lowered).
                "Sources/WireGuardApp/UI/macOS/ViewController/ManageTunnelsRootViewController.swift",
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
    }  // wireGuardConformanceUIEnabled
    #endif
}
// Default/GTK graph: include the WireGuard conformance dep-tree (a no-op when the
// upstream checkout is absent — the array is empty). The qt graph appends the same
// shared array in its own branch so it can render the real tunnel-list VC.
targets += wireGuardConformanceTargets

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
//
// Gated on signalUpstreamPresent: ONLY this target's C `#include <openssl/evp.h>`
// + `link "crypto"` require libssl-dev, which CI runners lack. Only SignalServiceKit
// depends on CommonCrypto (and SSK is itself gated), so excluding it on a fresh
// checkout / CI (signal absent) leaves no dangling dependency and the package builds
// identically to clean main. NOTE: the OTHER Signal shims (CryptoKit / the
// signalAppleFrameworkShims loop / etc.) stay ungated — they compile inertly on CI
// AND some are consumed by the always-built UIKit shim (e.g. UIKit →
// UserNotifications), so gating them would dangle that dependency and invalidate the
// whole manifest.
#if os(Linux)
if signalUpstreamPresent {
targets.append(
    .target(
        name: "CommonCrypto",
        path: "Sources/CommonCryptoShim",
        publicHeadersPath: "include",
        linkerSettings: [.linkedLibrary("crypto")]
    )
)
}
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
    // NOTE: "LocalAuthentication" is intentionally NOT here — it's a SHARED target
    // defined explicitly below (Sources/LocalAuthenticationShim), also depended on by
    // WireGuard's PrivateDataConfirmation. SSK depends on it via its explicit list
    // instead of this loop (the loop would create a duplicate target named the same).
    "ContactsUI", "Intents", "PassKit", "Accelerate",
    "LinkPresentation", "Metal", "MetalKit", "MetalPerformanceShaders",
    "QuartzCore", "CoreText", "ImageIO", "CoreServices", "CoreImage", "CoreLocation", "CoreSpotlight", "Vision", "AuthenticationServices",
    "UserNotifications", "SystemConfiguration", "StoreKit", "NaturalLanguage",
    "DeviceCheck", "CoreTelephony", "CFNetwork", "AudioToolbox", "AVFAudio", "CoreVideo", "CoreMedia", "VideoToolbox", "IOSurface",
    "CocoaLumberjack", "SDWebImage", "SDWebImageWebPCoder", "blurhash",
    "ObjCAssoc", "System", "notify",
    // Telegram-Mac app-target surface (scripts/generated-telegram-app-source-check.sh).
    // NOTE: "Contacts" is NOT here — Sources/ContactsShim already declares it.
    // NOTE: "AVKit" is NOT here either — it's an explicit shared target
    // (Sources/AVKit, SwiftUI VideoPlayer surface) used by both SignalUI and
    // the Telegram-Mac app graph.
    "Quartz", "QuickLook", "OSLog", "AppIntents", "CoreMediaIO",
    // NOTE: "Lottie" is NOT here — Sources/Lottie (Signal's LibMobileCoin dep)
    // already declares it explicitly.
    "MapKit", "SceneKit", "RealityKit", "Firebase", "FirebaseCrashlytics", "TdBinding",
    // NOTE: "zlib" is intentionally NOT here — it's a real systemLibrary
    // (cZlibTarget, links libz) rather than an inert Swift shim, so it's added to
    // SignalServiceKit's dependencies explicitly below.
]
// NOTE: NOT gated on signalUpstreamPresent — the always-built UIKit shim depends on
// some of these (e.g. UIKit → UserNotifications), so they must exist whenever Linux
// builds, or the package manifest dangles that dependency. They are inert placeholder
// modules that compile fine on CI without any signal upstream.
#if os(Linux)
for shimName in signalAppleFrameworkShims {
    // Each shim may build on QuillFoundation's Core Graphics / Foundation shadow
    // types (e.g. ImageIO's CGImageSource returns QuillFoundation's CGImage).
    // QuillFoundation depends only on QuillKit, so this introduces no cycle; the
    // edge is inert for shims that do not import QuillFoundation.
    let dependencies: [Target.Dependency]
    switch shimName {
    case "AudioToolbox", "UserNotifications":
        dependencies = ["QuillFoundation", "QuillKit"]
    case "CoreMedia":
        dependencies = ["QuillFoundation", "CoreVideo", "AudioToolbox"]
    case "CoreImage":
        // CIImage(cvPixelBuffer:) — the camera frame pipeline (#516).
        dependencies = ["QuillFoundation", "CoreVideo"]
    case "CoreVideo", "MetalPerformanceShaders":
        dependencies = ["QuillFoundation", "Metal"]
    case "MetalKit":
        dependencies = ["QuillFoundation", "Metal", "QuartzCore", "QuillUIKit"]
    case "SDWebImage":
        dependencies = ["QuillFoundation", "QuillUIKit"]
    case "VideoToolbox":
        dependencies = ["QuillFoundation", "CoreMedia", "CoreVideo"]
    case "QuartzCore":
        dependencies = ["QuillFoundation", "Metal"]
    case "Quartz":
        dependencies = ["QuillFoundation", "QuartzCore"]
    case "OSLog":
        dependencies = ["os"]
    case "IOSurface":
        dependencies = ["QuillFoundation", "CoreVideo"]
    case "AppIntents":
        dependencies = ["QuillFoundation", "UniformTypeIdentifiers"]
    case "Vision":
        // VNImageRequestHandler's init overloads take ImageIO's
        // CGImagePropertyOrientation and CoreVideo's CVPixelBuffer (face
        // detection / QR scanning). No cycle: neither shim imports Vision.
        dependencies = ["QuillFoundation", "ImageIO", "CoreVideo"]
    case "SceneKit":
        // SceneKit vends SwiftUI's `SceneView`; the scene-graph types use
        // QuillFoundation's CGFloat and Foundation's CGPoint. Rung 2c also
        // mirrors Apple's umbrella reach for UIKit/AppKit/CoreGraphics so Euclid
        // and ShapeScript's SceneKit interop files compile without source edits.
        // SwiftUI does not import SceneKit, so the SwiftUI edge remains acyclic.
        dependencies = ["QuillFoundation", "SwiftUI", "UIKit", "AppKit", "CoreGraphics"]
    case "RealityKit":
        dependencies = ["QuillFoundation", "UIKit", "Combine"]
    default:
        dependencies = ["QuillFoundation"]
    }
    targets.append(.target(name: shimName, dependencies: dependencies, path: "Sources/AppleFrameworkShims/\(shimName)"))
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
    let signalUIRenderDependencies: [Target.Dependency] = [
        "QuillUIKit", "UIKit", "QuillFoundation", "QuartzCore",
        "SignalUI", "SignalServiceKit",
        .product(name: "CGTK", package: "SwiftOpenUI"),
        .product(name: "CGTKBridge", package: "SwiftOpenUI"),
    ] + (signalAppTargetPresent ? ["SignalApp"] : [])
    targets += [
        .target(
            name: "SignalServiceKit",
            dependencies: [
                "LibSignalClient",
                "UIKit", "AVFoundation", "Network", "os", "Security", "CoreGraphics",
                // Shared LocalAuthentication shim (Sources/LocalAuthenticationShim) —
                // also used by WireGuard; depended on explicitly here rather than via the
                // signalAppleFrameworkShims loop to avoid a duplicate target definition.
                "LocalAuthentication",
                "CryptoKit", "CommonCrypto", "SignalRingRTC", "COSUnfairLock", "Contacts",
                "libPhoneNumber_iOS", "UniformTypeIdentifiers", "zlib", "QuillFoundation",
                .product(name: "GRDB", package: "GRDB.swift"),
                // Raw sqlite3 C symbols (SQLITE_OK / sqlite3_errmsg / sqlite3_step
                // ...) used by ~12 SSK files. On Apple these arrive via the
                // bridging header; on Linux GRDB vends them through its GRDBSQLite
                // system-library module (link "sqlite3"). inject-foundation adds
                // `import GRDBSQLite` to the files that need it.
                .product(name: "GRDBSQLite", package: "GRDB.swift"),
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
            ] + signalAppleFrameworkShims.map { Target.Dependency.target(name: $0) },
            path: ".upstream/signal-ios/SignalServiceKit",
            exclude: signalServiceKitExcludes,
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // signal-smoke: smallest-milestone executable proving the real
        // Signal-iOS toolchain LINKS + RUNS on QuillOS (Track B). Links
        // SignalServiceKit + libsignal_ffi.a and runs a pure in-memory
        // libsignal crypto primitive. `-use-ld=lld` is required: the default
        // bfd linker OOMs ("Killed") on the 194MB libsignal_ffi.a; lld links it
        // in ~44s. Gated like SSK (Linux + signal/libsignal upstream present),
        // so absent from CI / fresh checkouts.
        .executableTarget(
            name: "signal-smoke",
            dependencies: ["SignalServiceKit", "LibSignalClient"],
            path: "Sources/SignalSmoke",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.unsafeFlags(["-use-ld=lld"])]
        ),
        // signal-chat: the full chat window (conversation list / thread /
        // composer) driving quill-signal-bridge (presage + libsignal, real
        // Signal protocol) over its unix-socket line-JSON protocol. Pure
        // QuillUI -- no SSK link, so it builds in seconds.
        .executableTarget(
            name: "signal-chat",
            dependencies: ["QuillUI", "QuillUIGtk"],
            path: "Sources/SignalChat",
            swiftSettings: appSwiftSettings
        ),
        // signal-ui-render: UIKit→GTK4 renderer. First-light depends only on the
        // UIKit shim + GTK (fast build, no SignalUI link); the registry + mappers
        // turn a UIViewController's UIView tree into a GtkWidget window. SignalUI
        // is added here once the real-VC (Settings) wiring lands.
        .executableTarget(
            name: "SignalUIRender",
            dependencies: signalUIRenderDependencies,
            path: "Sources/SignalUIRender",
            swiftSettings: appSwiftSettings + [.unsafeFlags(gtk4SwiftImporterFlags)],
            // Link GTK4 + gdk-pixbuf (pulls glib/gobject/gio/pango/cairo) — needed
            // for g_*/gtk_*/gdk_* symbols. `-use-ld=lld`: the default BFD linker
            // OOM-kills on the huge SignalUI+SSK+libsignal+GRDB link (signal-smoke
            // uses lld for the same reason).
            linkerSettings: [
                .unsafeFlags(["-use-ld=lld"]),
                .unsafeFlags(gtk4LinkerFlags),
                .unsafeFlags(gdkPixbufLinkerFlags),
            ]
        ),
        // SignalUI: Signal-iOS's OWN UI framework (270 Swift files, UIKit-based),
        // compiled UNMODIFIED against QuillUI's UIKit layer + the framework shims.
        // This is the real Track B UI goal -- Signal's actual UI code running on
        // QuillOS, not a reimplementation. Tests + the 3 ObjC files are excluded
        // (ObjC ports follow the SSK QuillPort pattern if needed). Gated like SSK.
        .target(
            name: "SignalUI",
            dependencies: [
                "SignalServiceKit", "LibSignalClient",
                "UIKit", "AVFoundation", "Contacts", "SafariServices", "MessageUI",
                "UniformTypeIdentifiers", "Combine", "PhotosUI", "MobileCoreServices",
                "SwiftUI", "Photos", "ContactsUI", "MediaPlayer", "MetalKit", "Vision",
                "NaturalLanguage", "CoreServices", "Logging", "MobileCoin",
                "LibMobileCoin", "SDWebImage", "PureLayout", "Lottie", "BonMot",
                // Full import closure of SignalUI's 270 files (census via
                // grep of attributed+plain imports): AVKit (ConversationPicker
                // video previews), WebKit (CaptchaView's WKWebView), CoreImage
                // (image pipeline), SignalRingRTC (calling type-shim, same one
                // SSK builds against).
                "AVKit", "WebKit", "CoreImage", "SignalRingRTC",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: ".upstream/signal-ios/SignalUI",
            // Same concurrency posture as the AppKit shadow + SSK: Signal's
            // UIKit-era code predates strict concurrency; the shims' @MainActor
            // annotations otherwise reject thousands of legal UIKit-style calls.
            exclude: [
                "SignalUI.h",
                "UIKitExtensions/UIButton+DeprecationWorkaround.h",
                "UIKitExtensions/UIButton+DeprecationWorkaround.m",
                "Calls/CallLinkTest.swift",
                "Payments/MobileCoinHelperSDKTest.swift",
                "Utils/FormattedNumberFieldTest.swift",
                "RecipientPickers/RecipientPickerViewControllerTest.swift",
                "LinkPreview/LinkPreviewFetchStateTest.swift",
                "LinkPreview/HTMLMetadataTests.swift",
                "LinkPreview/LinkPreviewFetcherTest.swift",
                "UIKitExtensions/UIStackView+SignalUITest.swift",
                "FormatStyles/OWSByteCountFormatStyleTest.swift",
            ],
            swiftSettings: [.swiftLanguageMode(.v5), .unsafeFlags(["-strict-concurrency=minimal", "-default-isolation", "MainActor"])]
        ),
        .testTarget(
            name: "SignalServiceKitObjCPortTests",
            dependencies: ["SignalServiceKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
    // SignalApp: Signal-iOS's main *app* target (`Signal/`), home of the real
    // ConversationViewController + CVComponent message-cell pipeline. Brought to
    // Linux as a conversation-rendering slice: `quill-signal-prep-app.sh` prunes
    // the iOS-only subsystems (calling / device-transfer / backups) that need
    // un-shimmed frameworks, then lowers the remainder exactly like SignalUI.
    // Inert until the prep script has run against the disposable .upstream copy
    // (gated on a pruned-tree marker so a pristine fetch doesn't try to build it).
    if signalAppTargetPresent {
        targets += [
            .target(
                name: "SignalApp",
                dependencies: [
                    "SignalUI", "SignalServiceKit", "LibSignalClient",
                    "UIKit", "AVFoundation", "Contacts", "SafariServices", "MessageUI",
                    "UniformTypeIdentifiers", "Combine", "PhotosUI", "MobileCoreServices",
                    "SwiftUI", "Photos", "ContactsUI", "MediaPlayer", "MetalKit", "Vision",
                    "NaturalLanguage", "CoreServices", "Logging", "MobileCoin",
                    "LibMobileCoin", "SDWebImage", "PureLayout", "Lottie", "BonMot",
                    "AVKit", "WebKit", "CoreImage", "SignalRingRTC",
                    "StoreKit", "AuthenticationServices", "QuickLook", "QuartzCore",
                    .product(name: "GRDB", package: "GRDB.swift"),
                ],
                path: ".upstream/signal-ios/Signal",
                exclude: [
                    "Signal-Prefix.pch",
                ],
                resources: [
                    .copy("Symbols.xcassets"),
                ],
                swiftSettings: [.swiftLanguageMode(.v5), .unsafeFlags(["-strict-concurrency=minimal", "-default-isolation", "MainActor"])]
            )
        ]
    }
}
#endif

// V4L2 capture backend (#515): named non-variadic ioctl wrappers + the V4L2
// constants the Swift importer can't surface. shim.h self-gates on __linux__;
// no linkerSettings needed (ioctl/mmap live in libc).
#if os(Linux)
targets += [
    .systemLibrary(name: "CV4L2", path: "Sources/CV4L2"),
]
#endif

// SolderScope (rjwalters/SolderScope) — real macOS SwiftUI USB-microscope
// viewer compiled UNMODIFIED on Linux (no @objc/#selector anywhere; the only
// build-prep transform is quill-lower-appkit's `import os.log` → `import os`
// clang-submodule lowering). Exercises the SwiftUI app lifecycle +
// AVFoundation capture + CoreImage/CoreVideo surface. Inert on CI until
// fetch-upstream.sh populates .upstream/solderscope (gitignored).
#if os(Linux)
if solderScopeUpstreamPresent {
    products.append(.executable(name: "QuillSolderScope", targets: ["QuillSolderScope"]))
    targets += [
        .executableTarget(
            name: "QuillSolderScope",
            dependencies: [
                "QuillUI", "SwiftUI", "AppKit", "Combine", "os",
                "AVFoundation", "CoreImage", "CoreGraphics", "CoreVideo",
                "CoreMedia", "Accelerate", "UniformTypeIdentifiers",
                "QuillFoundation",
            ],
            path: ".upstream/solderscope/SolderScope",
            exclude: [
                "Metadata/SolderScope.entitlements",
                "Metadata/Info.plist",
            ],
            // -import-module Combine: on Apple platforms Foundation re-exports
            // Combine, so files with only `import Foundation` freely use
            // ObservableObject/@Published (SolderScope's CalibrationManager
            // does exactly this). corelibs Foundation can't, so emulate the
            // re-export at the app-target boundary.
            swiftSettings: appSwiftSettings + [
                .unsafeFlags(["-Xfrontend", "-import-module", "-Xfrontend", "Combine"])
            ]
        ),
    ]
}
#endif

// SceneKit conformance lane (docs/scenekit-conformance.md). Targets are
// inert on CI until fetch-upstream.sh populates the checkouts (use the
// `scenekit` meta-arm). Ladder: Euclid lib (pure Swift, can go green ahead
// of any SCN surface) → fixtures → Euclid Example → ShapeScript core/CLI →
// ShapeScript Viewer (real shipped macOS app, NSDocument-based AppKit).
#if os(Linux)
targets += [
    .executableTarget(
        name: "QuillSceneKitRenderSmoke",
        dependencies: ["SceneKit", "AppKit", "QuillFoundation", "QuillUI"],
        path: "Sources/QuillSceneKitRenderSmoke",
        swiftSettings: appSwiftSettings
    ),
]
products.append(.executable(name: "quill-scenekit-render-smoke", targets: ["QuillSceneKitRenderSmoke"]))

if euclidUpstreamPresent {
    // Euclid's Apple-framework interop files (Euclid+SceneKit/RealityKit/
    // AppKit/UIKit/CoreGraphics/CoreText/SIMD) are `#if canImport(...)`
    // gated upstream. Rung 2c intentionally pulls the SceneKit/AppKit/UIKit/
    // CoreGraphics surface into the dep graph, so Euclid's real SceneKit and
    // CoreGraphics mesh interop compiles for the example app. RealityKit
    // interop stays excluded until that deeper texture/material API is needed.
    // `.swiftLanguageMode(.v5)`: Euclid is Swift-5-mode code; the default
    // Swift 6 mode flags its global statics / @Sendable closures as
    // concurrency errors (Transform.identity, Polygon.codableClasses,
    // Utilities' permutation helpers). v5 mode downgrades them to warnings,
    // exactly as the other vendored upstreams (IceCubes, NNW) do.
    targets += [
        .target(
            name: "Euclid",
            // Rung 2c enables Euclid's SceneKit/UIKit/AppKit/CoreGraphics
            // interop. ShapeScript depends on Euclid, so this intentionally
            // wakes ShapeScript's SceneKit/CoreText importer surface too. Keep
            // RealityKit excluded for now; the Euclid example uses a small
            // RealityKit screen, but Euclid's own RealityKit mesh interop is a
            // deeper texture/material API and is not needed for this rung.
            dependencies: ["SceneKit", "UIKit", "AppKit", "CoreGraphics"],
            path: ".upstream/euclid/Sources",
            exclude: ["Euclid+RealityKit.swift"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Real UIKit + SceneKit demo app (one RealityKit screen, one
        // visionOS volumetric view) — the warm-up SCN conformance driver.
        // Red members here ARE the campaign work-list.
        .executableTarget(
            name: "QuillEuclidExample",
            dependencies: [
                "Euclid", "QuillUI", "SwiftUI", "UIKit", "SceneKit",
                "RealityKit", "Combine", "QuillFoundation",
            ],
            path: ".upstream/euclid/Example",
            exclude: [
                "Assets.xcassets",
                "Info.plist",
            ],
            swiftSettings: appSwiftSettings
        ),
        .executableTarget(
            name: "QuillEuclidRenderSmoke",
            dependencies: ["Euclid", "SceneKit", "UIKit", "QuillFoundation"],
            path: "Sources/QuillEuclidRenderSmoke",
            swiftSettings: appSwiftSettings
        ),
    ]
    products.append(.library(name: "Euclid", targets: ["Euclid"]))
    products.append(.executable(name: "quill-euclid-render-smoke", targets: ["QuillEuclidRenderSmoke"]))
}
if shapeScriptUpstreamPresent && euclidUpstreamPresent && svgPathUpstreamPresent {
    // NOTE: ShapeScript's "LRUCache" dependency resolves to the existing
    // in-repo stub target (Sources/LRUCache, a never-hitting no-op cache —
    // functionally correct, just uncached). Rung 1 may repoint that target
    // at .upstream/lrucache/Sources (fetch arm already exists) if real
    // caching matters; it is API-identical.
    targets += [
        .target(
            name: "SVGPath",
            dependencies: [],
            path: ".upstream/svgpath/Sources",
            // SVGPath's SwiftUI/CoreGraphics extensions are canImport-gated;
            // in this monorepo the shim modules are visible enough to wake
            // those files, so exclude them explicitly and leave the pure parser.
            exclude: ["Info.plist", "SVGPath+CoreGraphics.swift", "SVGPath+SwiftUI.swift"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // The REAL nicklockwood/LRUCache. ShapeScript's GeometryCache needs
        // its full API (setValue/removeValue/count/init(totalCostLimit:)),
        // which the repo's in-repo `LRUCache` stub (a no-op cache kept for
        // other consumers) lacks. Compiled under a distinct target name to
        // avoid the duplicate, then surfaced to ShapeScript's unmodified
        // `import LRUCache` via `-module-alias` (same pattern as NNWAccount).
        .target(
            name: "ShapeScriptLRUCache",
            dependencies: [],
            path: ".upstream/lrucache/Sources",
            exclude: ["Info.plist"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // The ShapeScript language core + CLI support Linux upstream (mesh
        // generation via Euclid). With Euclid's rung-2c SceneKit deps enabled,
        // ShapeScript's own SceneKit/CoreText importer files also wake and
        // compile against the authored shim surface. v5 mode matches upstream.
        .target(
            name: "ShapeScript",
            dependencies: ["Euclid", "ShapeScriptLRUCache", "SVGPath"],
            path: ".upstream/shapescript/ShapeScript",
            exclude: ["ShapeScript.xctestplan"],
            swiftSettings: [
                .swiftLanguageMode(.v5),
                .unsafeFlags(["-module-alias", "LRUCache=ShapeScriptLRUCache"]),
            ]
        ),
        // `shapescript <file.shape> <out.obj/.stl>` renders 3D models on
        // Linux with zero rendering surface — the rung-1 demo.
        .executableTarget(
            name: "QuillShapeScriptCLI",
            dependencies: ["ShapeScript"],
            path: ".upstream/shapescript/Viewer/CLI",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // The Viewer: a real shipped, NSDocument-based AppKit app whose
        // entire viewport is an SCNView — the flagship SceneKit target,
        // and an AppKit-reimplementation conformance driver in the same
        // breath. Mac + Shared sources only (iOS/ lives beside them).
        .executableTarget(
            name: "QuillShapeScriptViewer",
            dependencies: [
                "ShapeScript", "Euclid", "SVGPath", "QuillUI", "AppKit", "Cocoa",
                "SceneKit", "Combine", "os", "UniformTypeIdentifiers",
                "CoreServices", "QuillFoundation",
            ],
            path: ".upstream/shapescript/Viewer",
            exclude: [
                "Mac/Base.lproj",
                "Mac/Info.plist",
                "Mac/Viewer.entitlements",
                "Mac/Welcome.rtf",
                "Mac/WhatsNew.rtf",
                "Shared/AppIcon.icon",
                "Shared/Assets.xcassets",
                "Shared/Licenses.rtf",
                "Shared/Untitled.shape",
            ],
            sources: ["Mac", "Shared"],
            swiftSettings: appSwiftSettings
        ),
    ]
    products.append(.executable(name: "QuillShapeScriptCLI", targets: ["QuillShapeScriptCLI"]))
    products.append(.executable(name: "QuillShapeScriptViewer", targets: ["QuillShapeScriptViewer"]))
}
if quillUISceneKitFixturesEnabled {
    // Authored in-repo fixture apps (NOT upstream source): a solar-system
    // viewer and a ball-and-stick molecule viewer, written as faithful
    // macOS SwiftUI+SceneKit apps. They pin down the exact SCN surface the
    // real apps need, in a scene we fully control for pixel comparison.
    targets += [
        .executableTarget(
            name: "QuillSolarSystem",
            dependencies: [
                "QuillUI", "SwiftUI", "AppKit", "SceneKit", "Combine",
                "QuillFoundation",
            ],
            path: "Sources/QuillSceneKitFixtures/SolarSystem",
            swiftSettings: appSwiftSettings
        ),
        .executableTarget(
            name: "QuillMoleculeViewer",
            dependencies: [
                "QuillUI", "SwiftUI", "AppKit", "SceneKit", "Combine",
                "QuillFoundation",
            ],
            path: "Sources/QuillSceneKitFixtures/MoleculeViewer",
            swiftSettings: appSwiftSettings
        ),
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
        dependencies: ["QuillFoundation", "QuillKit", "QuillDataMacros", "Combine", .product(name: "SwiftOpenUI", package: "SwiftOpenUI")],
        path: "Sources/QuillSwiftUICompatibility"
    ),
    .target(
        name: "SwiftUI",
        // AppKit + Combine: Apple's macOS SwiftUI re-exports both; mirror it
        // (see Sources/SwiftUIShim/SwiftUI.swift). The NSViewRepresentable
        // GTK mount (GtkDrawingArea + Cairo-backed CGContext) is gtk-graph
        // only — the qt graph keeps the shadow GTK-free (compile-only
        // representables there until the Qt mount exists).
        dependencies: [
            "QuillSwiftUICompatibility", "AppKit", "UIKit", "CoreImage", "CoreTransferable", "Combine",
        ] + swiftUIShadowMountDependencies,
        path: "Sources/SwiftUIShim",
        // v5 + minimal concurrency matches the house settings (the GTK mount
        // crosses MainActor.assumeIsolated with non-Sendable view values).
        swiftSettings: [
            .swiftLanguageMode(.v5),
            .unsafeFlags(["-strict-concurrency=minimal"]),
        ] + swiftUIShadowMountSwiftSettings
    ),
    .target(name: "Observation", dependencies: ["QuillDataMacros"], path: "Sources/Observation"),
    .target(name: "UniformTypeIdentifiers", dependencies: [], path: "Sources/UniformTypeIdentifiersShim"),
    .target(name: "Network", dependencies: [], path: "Sources/NetworkShim"),
    .target(name: "NetworkExtension", dependencies: ["Network"], path: "Sources/NetworkExtensionShim"),
    .testTarget(name: "NetworkExtensionTests", dependencies: ["NetworkExtension"], path: "Tests/NetworkExtensionTests"),
    // LocalAuthentication shim — LAContext/LAPolicy/LAError so WireGuard's
    // PrivateDataConfirmation (key-reveal gate) recompiles; no auth backend on Linux.
    .target(name: "LocalAuthentication", dependencies: ["QuillKit"], path: "Sources/LocalAuthenticationShim"),
    .target(name: "AVKit", dependencies: ["SwiftUI", "AVFoundation"], path: "Sources/AVKit"),
    .testTarget(name: "LocalAuthenticationTests", dependencies: ["LocalAuthentication"], path: "Tests/LocalAuthenticationTests"),
    // WireGuardKitGo Linux stub — the wireguard-go cgo bridge (Go engine not built here);
    // lets WireGuardKit's WireGuardAdapter recompile. Compile-faithful, never runs on Linux.
    .target(name: "WireGuardKitGo", dependencies: [], path: "Sources/WireGuardKitGoShim"),
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
        dependencies: appKitShadowDependencies,
        path: "Sources/QuillAppKit",
        swiftSettings: [
            .swiftLanguageMode(.v5),
            .unsafeFlags(["-strict-concurrency=minimal"]),
            // The bitmap encoder (rung 4) imports CGdkPixbuf. Keep the importer
            // flags here for older/non-explicit module builds; the systemLibrary
            // target also carries pkgConfig so clean builds can compile its PCM.
            .unsafeFlags(gdkPixbufSwiftImporterFlags)
        ]
    ),
    // GTK4-backed runtime for QuillAppKit. Separate target so the
    // bare AppKit module stays a clean shadow (no transitive CGtk4
    // dep visible to clients like swift-sharing's `canImport(AppKit)`
    // branch). Apps that want the runtime backing import QuillAppKitGTK.
    .target(
        name: "QuillAppKitGTK",
        dependencies: ["AppKit", "CGtk4", .product(name: "CGTK", package: "SwiftOpenUI")],
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
    .target(name: "UIKit", dependencies: uiKitShimDependencies, path: "Sources/UIKitShim"),
    // Cocoa umbrella shadow: `import Cocoa` re-exports the AppKit shadow +
    // common AppKit-adjacent Apple modules, so source that relies on Cocoa as
    // an umbrella import recompiles unchanged.
    // so unmodified macOS app source that `import Cocoa` recompiles unchanged.
    .target(name: "Cocoa", dependencies: ["AppKit", "CoreGraphics", "CoreImage", "CoreText", "QuartzCore", "CoreServices"], path: "Sources/CocoaShim"),
    .target(name: "MessageUI", dependencies: ["QuillFoundation", "QuillUIKit"], path: "Sources/MessageUIShim"),
    .target(name: "SafariServices", dependencies: ["QuillFoundation", "QuillUIKit"], path: "Sources/SafariServicesShim"),
    .target(name: "MobileCoreServices", dependencies: ["QuillFoundation"], path: "Sources/MobileCoreServicesShim"),
    .target(name: "RevenueCat", dependencies: [], path: "Sources/RevenueCat"),
    .target(name: "WishKit", dependencies: ["SwiftUI"], path: "Sources/WishKit"),
    .target(name: "SFSafeSymbols", dependencies: [], path: "Sources/SFSafeSymbols"),
    .target(name: "AsyncAlgorithms", dependencies: [], path: "Sources/AsyncAlgorithms"),
    .target(name: "Carbon", dependencies: [], path: "Sources/Carbon"),
    .target(name: "CoreGraphics", dependencies: ["QuillKit", "QuillFoundation"], path: "Sources/CoreGraphics"),
    .target(name: "Security", dependencies: ["QuillKit"], path: "Sources/Security"),
    // CoreImage edge: Apple's AVFoundation re-exports CoreImage (SignalUI's
    // ScanQRCodeViewController reaches CIQRCodeDescriptor through
    // `import AVFoundation` alone); AVCaptureExtras.swift mirrors that with an
    // @_exported import. CoreImage depends only on QuillFoundation — no cycle.
    .target(name: "CoreHaptics", dependencies: [], path: "Sources/AppleFrameworkShims/CoreHaptics"),
    .target(name: "Photos", dependencies: ["QuillFoundation"], path: "Sources/PhotosShim"),
    .target(name: "CoreTransferable", dependencies: ["UniformTypeIdentifiers"], path: "Sources/CoreTransferable"),
    .target(name: "FoundationModels", dependencies: ["QuillDataMacros"], path: "Sources/FoundationModels"),
    // CV4L2 (Linux): named non-variadic ioctl wrappers + V4L2 constants the
    // Swift importer can't surface (variadic ioctl, _IOWR function-like
    // macros). The shim header self-gates on __linux__; the AVFoundation
    // capture/bridge code double-gates on canImport(CV4L2), so Apple-host
    // graphs never see it (the dependency is appended below, Linux-only).
    .target(name: "AVFoundation", dependencies: ["QuillKit", "QuillFoundation", "QuartzCore", "AudioToolbox", "CoreMedia", "CoreVideo", "CoreImage"] + quillV4L2Dependencies, path: "Sources/AVFoundation"),
    .target(name: "Speech", dependencies: ["QuillKit", "AVFoundation"], path: "Sources/Speech"),
    .target(name: "ApplicationServices", dependencies: ["QuillKit"], path: "Sources/ApplicationServices"),
    .target(name: "ServiceManagement", dependencies: ["QuillKit"], path: "Sources/ServiceManagement"),
    .target(name: "Alamofire", dependencies: ["Security"], path: "Sources/Alamofire"),
    .target(name: "MarkdownUI", dependencies: ["SwiftUI"], path: "Sources/MarkdownUI"),
    .target(name: "Splash", dependencies: ["SwiftUI"], path: "Sources/Splash"),
    .target(name: "ActivityIndicatorView", dependencies: ["SwiftUI"], path: "Sources/ActivityIndicatorView"),
    .target(name: "ButtonKit", dependencies: ["SwiftUI"], path: "Sources/ButtonKit"),
    .target(
        name: "WrappingHStack",
        dependencies: wrappingHStackDependencies,
        path: "Sources/WrappingHStack",
        swiftSettings: quillUIGTKSwiftImporterSettings,
        linkerSettings: quillUIGTKLinkerSettings
    ),
    .target(name: "Vortex", dependencies: ["SwiftUI"], path: "Sources/Vortex"),
    .target(name: "KeyboardShortcuts", dependencies: ["QuillKit", "SwiftUI"], path: "Sources/KeyboardShortcuts"),
    .target(name: "PhotosUI", dependencies: ["SwiftUI", "Photos"], path: "Sources/PhotosUI"),
    // Third-party Pod shims that Signal-iOS's SignalUI imports but that don't
    // exist on Linux. Empty modules to start; grow the exact API surface SignalUI
    // references as the compile reports it. (Apple frameworks it needs -- Photos,
    // MediaPlayer, MetalKit, Vision, ContactsUI, CoreServices, NaturalLanguage,
    // SDWebImage -- come from the signalAppleFrameworkShims loop above.)
    .target(name: "Logging", dependencies: [], path: "Sources/Logging"),
    // MobileCoin's HttpRequester protocol signature uses LibMobileCoin's
    // HTTPMethod/HTTPResponse (mirroring the real SDK's module split).
    .target(name: "MobileCoin", dependencies: ["LibMobileCoin"], path: "Sources/MobileCoin"),
    .target(name: "LibMobileCoin", dependencies: [], path: "Sources/LibMobileCoin"),
    // PureLayout extends QuillUIKit's UIView with constraints built from its
    // anchor factories, and its insets-taking API uses the UIKit shim's
    // UIEdgeInsets -- hence the dependency on the UIKit umbrella (which
    // @_exported-re-exports QuillUIKit).
    .target(name: "PureLayout", dependencies: ["UIKit"], path: "Sources/PureLayout"),
    .target(name: "Lottie", dependencies: ["UIKit"], path: "Sources/Lottie"),
    // BonMot's StringStyle stores UIFont/UIColor/NSTextAlignment -- hence the
    // dependency on the UIKit umbrella (same pattern as PureLayout above).
    .target(name: "BonMot", dependencies: ["UIKit"], path: "Sources/BonMot"),
    .target(name: "Magnet", dependencies: ["AppKit", "QuillKit"], path: "Sources/Magnet"),
    .target(name: "Nuke", dependencies: [], path: "Sources/Nuke"),
    .target(name: "NukeUI", dependencies: ["SwiftUI", "Nuke"], path: "Sources/NukeUI"),
    .target(name: "EmojiText", dependencies: ["SwiftUI", "QuillFoundation"], path: "Sources/EmojiText"),
    .target(name: "Gifu", dependencies: ["SwiftUI"], path: "Sources/Gifu"),
    .target(name: "Charts", dependencies: ["SwiftUI"], path: "Sources/Charts"),
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
    .target(name: "Sparkle", dependencies: ["Combine", "QuillKit"], path: "Sources/Sparkle"),
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
if iceCubesLinuxGraphEnabled {
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
    let qtGraphTargets: [Target] = [
        cSQLiteTarget,
        cCairoTarget,
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
            dependencies: ["CQt6Widgets", "CSQLite"],
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
            dependencies: ["QuillFoundation", "QuillKit", "CoreGraphics", "CoreTransferable"],
            path: "Sources/QuillUIKit"
        ),
        // Inert GTK-free Apple-framework shims the AppKit shadow
        // (appKitShadowDependencies) and the Cocoa umbrella below now
        // re-export. The default/GTK graph gets these from the
        // signalAppleFrameworkShims loop, which this replacement list bypasses.
        .target(name: "CoreGraphics", dependencies: ["QuillKit", "QuillFoundation"], path: "Sources/CoreGraphics"),
        .target(name: "Metal", dependencies: ["QuillFoundation"], path: "Sources/AppleFrameworkShims/Metal"),
        .target(name: "QuartzCore", dependencies: ["QuillFoundation", "Metal"], path: "Sources/AppleFrameworkShims/QuartzCore"),
        .target(name: "CoreVideo", dependencies: ["QuillFoundation", "Metal"], path: "Sources/AppleFrameworkShims/CoreVideo"),
        .target(name: "ImageIO", dependencies: ["QuillFoundation"], path: "Sources/AppleFrameworkShims/ImageIO"),
        .target(name: "CoreText", dependencies: ["QuillFoundation"], path: "Sources/AppleFrameworkShims/CoreText"),
        .target(name: "CoreImage", dependencies: ["QuillFoundation", "CoreVideo"], path: "Sources/AppleFrameworkShims/CoreImage"),
        .target(name: "CoreServices", dependencies: ["QuillFoundation"], path: "Sources/AppleFrameworkShims/CoreServices"),
        .target(
            name: "AppKit",
            dependencies: appKitShadowDependencies,
            path: "Sources/QuillAppKit",
            swiftSettings: [
                .swiftLanguageMode(.v5),
                .unsafeFlags(["-strict-concurrency=minimal"])
            ]
        ),
        // `import Cocoa` umbrella (re-exports AppKit + common AppKit-adjacent
        // Apple modules) so unmodified macOS app source that `import Cocoa`
        // recompiles in the qt graph — needed for the literal WireGuard VC
        // render conformance below.
        // Mirrors the default/GTK-graph Cocoa target.
        .target(name: "Cocoa", dependencies: ["AppKit", "CoreGraphics", "CoreImage", "CoreText", "QuartzCore", "CoreServices"], path: "Sources/CocoaShim"),
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
            dependencies: ["CQt6Widgets", "CCairo"],
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
            dependencies: ["AppKit", "CQuillAppKitQt", "QuillAutoLayout", "CCairo"],
            path: "Sources/QuillAppKitQt",
            swiftSettings: appSwiftSettings
        ),
        // gdk-pixbuf is toolkit-independent (the qt CI deps install it too);
        // AppKit's NSBitmapImageRep encoder (rung 4) needs it on both graphs.
        .systemLibrary(
            name: "CGdkPixbuf",
            path: "Sources/CGdkPixbuf",
            providers: [
                .apt(["libgdk-pixbuf-2.0-dev"])
            ]
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

    if quillUIQtGenericEnabled {
        // IceCubes-on-Qt path (QUILLUI_QT_GENERIC=1): the upstream IceCubes app's
        // ~80-target closure lives in the COMMON Linux shim graph, so keep it and
        // APPEND the qt-native graph instead of resetting. Name collisions
        // (QuillKit, QuillFoundation, …) keep their common-graph definitions —
        // only icecubes-linux-app is supported under the flag; the 9 canonical
        // apps remain the flag-off (reset) build's concern. SwiftOpenUI also
        // stays in allPackageDependencies (no reset), so it is NOT re-added here.
        products += [
            .library(name: "QuillGenericQtNativeRuntime", targets: ["QuillGenericQtNativeRuntime"]),
            .executable(name: "quill-qt-interaction-smoke", targets: ["QuillQtInteractionSmoke"])
        ]
        let existingTargetNames = Set(targets.map(\.name))
        targets += qtGraphTargets.filter { !existingTargetNames.contains($0.name) }
    } else {
        // Canonical Qt build: byte-for-byte the historical reset. Qt builds must
        // not load the GTK/SwiftOpenUI graph — SwiftPM evaluates dependency
        // manifests before target planning, so keeping SwiftOpenUI in the package
        // dependency list is enough to pull in its GTK pkg-config warnings even
        // for a native Qt-only smoke app.
        products = quillCanonicalLinuxAppProducts + [
            .library(name: "QuillGenericQtNativeRuntime", targets: ["QuillGenericQtNativeRuntime"]),
            .executable(name: "quill-qt-interaction-smoke", targets: ["QuillQtInteractionSmoke"])
        ]
        allPackageDependencies = quillDataPackageDependencies
        targets = qtGraphTargets
    }

    // SolderScope's Qt surface. Lives outside the canonical roster because
    // its GTK-side target is gated on the fetched .upstream/solderscope tree
    // (no self-contained core yet), so the product can only exist on the qt
    // graph unconditionally (both the canonical reset and the
    // QUILLUI_QT_GENERIC append path).
    let quillSolderScopeQtSpec = QuillCanonicalLinuxAppSpec(
        product: "quill-solderscope",
        target: "QuillSolderScope",
        qtPath: "Sources/QuillSolderScopeQt",
        qtRuntime: .genericQtNative
    )
    targets.append(quillCanonicalLinuxAppQtTarget(quillSolderScopeQtSpec))
    products.append(quillSolderScopeQtSpec.productDeclaration)

    // --- Generic SwiftUI→Qt backend (BackendQt), opt-in via QUILLUI_QT_GENERIC ---
    //
    // Everything below is gated so the default Qt build is unchanged. When the
    // flag is on we add a CQtBridge C++ wrapper, the BackendQt Swift renderer,
    // and a sibling quill-qt-generic-smoke executable that renders a REAL
    // SwiftUI tree through QtBackend().run(QtSmokeApp.self). The 9 production
    // apps keep their existing per-app C++ shims and are not touched.
    if quillUIQtGenericEnabled {
        targets += [
            .target(
                name: "Combine",
                dependencies: [
                    .product(name: "OpenCombine", package: "OpenCombine"),
                    .product(name: "OpenCombineDispatch", package: "OpenCombine"),
                    .product(name: "OpenCombineFoundation", package: "OpenCombine")
                ],
                path: "Sources/Combine"
            ),
            .target(
                name: "QuillSwiftUICompatibility",
                dependencies: [
                    "QuillFoundation",
                    "QuillDataMacros",
                    .product(name: "SwiftOpenUI", package: "SwiftOpenUI")
                ],
                path: "Sources/QuillSwiftUICompatibility"
            ),
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
                    "Observation",
                    "CQtBridge"
                ],
                path: "Sources/BackendQt",
                swiftSettings: appSwiftSettings + [
                    .define("QUILLUI_QT_GENERIC")
                ]
            ),
            .target(
                name: "SwiftUI",
                dependencies: swiftUIShadowCoreDependencies + swiftUIShadowMountDependencies,
                path: "Sources/SwiftUIShim",
                swiftSettings: [
                    .swiftLanguageMode(.v5),
                    .unsafeFlags(["-strict-concurrency=minimal"]),
                ] + swiftUIShadowMountSwiftSettings
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

    // --- Real WireGuard UI render conformance (purist render path) ---
    // Bring the whole GTK-free WireGuard conformance dep-tree into the qt graph so
    // QuillAppKitQtTests can render the REAL upstream VCs verbatim through
    // QuillAppKit→Qt. QuillWireGuardConformanceUI already compiles ButtonedDetail,
    // UnusableTunnel, the model, and the TunnelsListTableViewController main window,
    // so it SUBSUMES the earlier per-VC conformance targets (which would otherwise
    // overlap-source the same upstream files). Gated on the upstream checkout.
    if wireguardUpstreamPresent {
        // The REAL WireGuard main window: bring the whole GTK-free conformance
        // dep-tree (model + all VCs + the verbatim TunnelsListTableViewController)
        // into the qt graph so it renders via QuillAppKit→Qt. The 8 shims the
        // conformance depends on are absent from the qt literal (the qt graph
        // wholesale-reassigns `targets`), so add them here; wireGuardConformanceTargets
        // (populated GTK-free before the graph branches) holds WireGuardKit/KitC/
        // RingLogger/Minizip/Highlighter/UpstreamConfig + QuillWireGuardConformanceUI.
        // Targets only — NO .library products (the qt product reassignment
        // intentionally drops the os/Network/etc. products; re-adding would expand
        // the warning-gated canonical product build).
        targets += [
            .target(name: "os", dependencies: ["QuillKit"], path: "Sources/osShim"),
            .target(name: "Network", dependencies: [], path: "Sources/NetworkShim"),
            .target(name: "NetworkExtension", dependencies: ["Network"], path: "Sources/NetworkExtensionShim"),
            .target(name: "LocalAuthentication", dependencies: ["QuillKit"], path: "Sources/LocalAuthenticationShim"),
            .target(name: "WireGuardKitGo", dependencies: [], path: "Sources/WireGuardKitGoShim"),
            .target(name: "CoreWLAN", dependencies: [], path: "Sources/CoreWLAN"),
            .target(name: "Security", dependencies: ["QuillKit"], path: "Sources/Security"),
            .target(name: "ServiceManagement", dependencies: ["QuillKit"], path: "Sources/ServiceManagement")
        ]
        targets += wireGuardConformanceTargets
    }
}
#endif

let packageTestTargets: [Target] = {
    #if os(Linux)
    if quillUILinuxBuildBackend == .qt {
        // The qt AppKit test target also renders the LITERAL upstream WireGuard
        // VC (ButtonedDetailViewController) when the upstream checkout is present.
        let akqtTestDeps: [Target.Dependency] = wireGuardConformanceUIEnabled
            ? ["QuillAppKitQt", "AppKit", "QuillWireGuardConformanceUI", "NetworkExtension"]
            : ["QuillAppKitQt", "AppKit"]
        return [
            // Runs inside the stripped Qt graph itself. This keeps
            // `QUILLUI_LINUX_BACKEND=qt swift test` useful without
            // reintroducing the GTK/SwiftOpenUI dependency graph.
            .testTarget(
                name: "QuillAppKitQtTests",
                dependencies: akqtTestDeps,
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
            dependencies: ["QuillEnchantedData", "QuillEnchantedShared"],
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
            dependencies: ["QuillPaintCairo", "QuillPaintCoreGraphics", "QuillPaint"],
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
        // Pins the pure-Swift FMDB/RSDatabase compatibility layer that lets
        // NetNewsWire database modules move off ObjC on Linux without changing
        // their import names.
        .testTarget(
            name: "RSDatabaseCompatibilityTests",
            dependencies: ["RSDatabase", "RSDatabaseObjC"],
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
            dependencies: ["RSWeb", "QuillRSCoreShim"],
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
            name: "QuillArticlesDatabaseTests",
            dependencies: ["QuillArticlesDatabase", "QuillArticles", "QuillRSParser"],
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
        // Pins the vendored upstream NetNewsWire ActivityLog module:
        // lifecycle transitions, owner/kind lookup, id-based completion,
        // stale-running cleanup, notification posting, and completed-log
        // trimming. This is the next reusable FeedFinder/account dependency.
        .testTarget(
            name: "QuillActivityLogTests",
            dependencies: ["ActivityLog"],
            swiftSettings: appSwiftSettings
        ),
        // Pins the vendored FeedFinder HTML feed-detection: HTMLFeedFinder
        // surfaces <head> feed links + body links that look like feeds, and
        // FeedSpecifier scoring/merging picks the best candidate.
        .testTarget(
            name: "QuillFeedFinderTests",
            dependencies: ["QuillFeedFinder", "QuillRSParser"],
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
            swiftSettings: quillSwiftTestingAppleOverlaySwiftSettings
        ),
        // Pins the QuillUI core library's public surface:
        // QuillPlatform.name reports the host, QuillUIVersion is
        // semver-shaped, and QuillApp.run resolves. Keeps QuillUI
        // itself on the test-target scorecard.
        .testTarget(
            name: "QuillUITests",
            // + SwiftUI shadow on Linux only: always imported by these tests,
            // previously reached via the shared-build-dir leak; must be declared
            // now that the shadow carries CGtk4/QuillAppKitGTK (representable
            // GTK mount). On Apple `import SwiftUI` is the real SDK — no target.
            dependencies: ["QuillUI", "QuillUIGtk", "QuillUIQt", "QuillPaintCairo", "QuillInteractionSmokeSupport", "CCairo"] + swiftUIShadowTestDependencies,
            swiftSettings: quillSwiftTestingAppleOverlaySwiftSettings
        )
    ]

    if nnwUpstreamEnabled {
        // Pins the first direct upstream NetNewsWire Shared/ compile slice.
        // This grows toward the full Shared+Mac app target without routing
        // through the local QuillNetNewsWireCore reader replacement.
        tests.append(.testTarget(
            name: "NetNewsWireSharedCoreTests",
            dependencies: ["NNWAccount", "ActivityLog", "AppKit", "Articles", "NetNewsWireContext", "NetNewsWireSharedCore", "RSCore", "RSTree", "UserNotifications"],
            swiftSettings: nnwSwiftSettings
        ))
    }

    #if os(Linux)
    // Exercises the Apple-framework compatibility modules that real
    // generated Enchanted source imports on Linux. This target stays out of
    // the stripped Qt manifest graph so `QUILLUI_LINUX_BACKEND=qt swift
    // test` does not reintroduce SwiftOpenUI/GTK.
    tests.append(.testTarget(
        name: "QuillCompatibilityModuleTests",
        dependencies: quillLinuxCompatibilityModuleTestDependencies,
        swiftSettings: quillLinuxCompatibilityModuleTestSwiftSettings
    ))
    tests.append(.testTarget(
        name: "OllamaKitTests",
        dependencies: ["OllamaKit"],
        swiftSettings: appSwiftSettings
    ))
    tests.append(.testTarget(
        name: "SceneKitTests",
        dependencies: ["SceneKit", "AppKit", "UIKit", "QuillFoundation"],
        swiftSettings: appSwiftSettings
    ))
    tests.append(.testTarget(
        name: "CoreGraphicsTests",
        dependencies: ["CoreGraphics"],
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
if iceCubesLinuxGraphEnabled {
    products.append(.executable(name: "icecubes-linux-app", targets: ["IceCubesLinuxApp"]))

    targets += [
        .target(
            name: "IceCubesShims",
            dependencies: [.product(name: "SwiftOpenUI", package: "SwiftOpenUI"), "QuillFoundation", "QuillSwiftUICompatibility", "SwiftData", "SwiftUI"],
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
                .swiftLanguageMode(.v5),
                .unsafeFlags([
                    "-Xfrontend", "-import-module", "-Xfrontend", "IceCubesShims",
                    "-Xfrontend", "-import-module", "-Xfrontend", "Security"
                ])
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
                .swiftLanguageMode(.v5),
                .unsafeFlags(["-Xfrontend", "-import-module", "-Xfrontend", "IceCubesShims"])
            ]
        ),
        // Real Dimillian/IceCubesApp Env. Compiles once patch_icecubes adds
        // `import FoundationNetworking` (StreamWatcher → URLSessionWebSocketTask)
        // and `import UIKit` (Router → UIImage/UIApplication). The 6 excluded
        // files are Apple-framework system services (CoreHaptics/AudioToolbox/
        // TelemetryDeck/UserNotifications/QuickLook) that are Linux no-ops.
        .target(
            name: "Env",
            dependencies: [
                "Models",
                "NetworkClient",
                "SwiftUI",
                "IceCubesShims",
                "Combine",
                "os",
                "KeychainSwift",
                "UIKit",
                "CryptoKit",
                "QuickLook",
                "Security",
                "UserNotifications",
                "CoreHaptics",
                "AudioToolbox",
                "AVKit",
            ],
            path: ".upstream/icecubes/Packages/Env/Sources/Env",
            exclude: [
                "Telemetry.swift",
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5),
                .unsafeFlags([
                    "-Xfrontend", "-import-module", "-Xfrontend", "IceCubesShims",
                    "-Xfrontend", "-import-module", "-Xfrontend", "Security"
                ])
            ]
        ),
        // Real Dimillian/IceCubesApp DesignSystem. This is the first
        // substantial SwiftUI UI package above Models/NetworkClient/Env and
        // is intentionally compiled against canonical shim module names
        // instead of editing upstream source.
        .target(
            name: "DesignSystem",
            dependencies: [
                "Models",
                "Env",
                "SwiftUI",
                "IceCubesShims",
                "Combine",
                "Observation",
                "UIKit",
                "Nuke",
                "NukeUI",
                "EmojiText",
                "Gifu",
                "Charts",
            ],
            path: ".upstream/icecubes/Packages/DesignSystem/Sources/DesignSystem",
            swiftSettings: [
                .swiftLanguageMode(.v5),
                .unsafeFlags(["-strict-concurrency=minimal"]),
                .unsafeFlags(["-Xfrontend", "-default-isolation", "-Xfrontend", "MainActor"]),
                .unsafeFlags(["-Xfrontend", "-import-module", "-Xfrontend", "IceCubesShims"])
            ]
        ),
        // Real Dimillian/IceCubesApp MediaUI. This package sits above
        // DesignSystem and exercises Apple media/share framework shims while
        // still compiling against upstream source unchanged.
        .target(
            name: "MediaUI",
            dependencies: [
                "Models",
                "DesignSystem",
                "SwiftUI",
                "UIKit",
                "AVFoundation",
                "AVKit",
                "Photos",
                "QuickLook",
                "CoreTransferable",
                "Nuke",
                "NukeUI",
                "Observation",
                "Env",
                "IceCubesShims",
            ],
            path: ".upstream/icecubes/Packages/MediaUI/Sources/MediaUI",
            swiftSettings: [
                .swiftLanguageMode(.v5),
                .unsafeFlags(["-strict-concurrency=minimal"]),
                .unsafeFlags(["-Xfrontend", "-default-isolation", "-Xfrontend", "MainActor"]),
                .unsafeFlags(["-Xfrontend", "-import-module", "-Xfrontend", "IceCubesShims"])
            ]
        ),
        // Real Dimillian/IceCubesApp AppAccount. Kept as a pure package
        // target so StatusKit can compile against the upstream account model
        // and account-selector views without copying source.
        .target(
            name: "AppAccount",
            dependencies: [
                "NetworkClient",
                "Models",
                "Env",
                "DesignSystem",
                "SwiftUI",
                "CryptoKit",
                "IceCubesShims",
            ],
            path: ".upstream/icecubes/Packages/AppAccount/Sources/AppAccount",
            swiftSettings: [
                .swiftLanguageMode(.v5),
                .unsafeFlags(["-strict-concurrency=minimal"]),
                .unsafeFlags(["-Xfrontend", "-default-isolation", "-Xfrontend", "MainActor"]),
                .unsafeFlags(["-Xfrontend", "-import-module", "-Xfrontend", "IceCubesShims"])
            ]
        ),
        // Real Dimillian/IceCubesApp application source as a Linux SwiftPM
        // executable target. The Xcode project uses target membership; SwiftPM
        // models the same shape by including the app and shared intents folders
        // while excluding the widget-only ListEntity intent.
        .executableTarget(
            name: "IceCubesLinuxApp",
            dependencies: [
                "AVFoundation",
                "Account",
                "AppAccount",
                "AppIntents",
                "AuthenticationServices",
                "Combine",
                "Conversations",
                "CoreGraphics",
                "DesignSystem",
                "Env",
                "Explore",
                "IceCubesShims",
                "ImageIO",
                "KeychainSwift",
                "LinkPresentation",
                "Lists",
                "MediaUI",
                "Models",
                "NetworkClient",
                "Notifications",
                "Nuke",
                "NukeUI",
                "Observation",
                "RevenueCat",
                "SafariServices",
                "SFSafeSymbols",
                "StatusKit",
                "SwiftData",
                "SwiftUI",
                "Timeline",
                "UniformTypeIdentifiers",
                "UserNotifications",
                "UIKit",
                "WebKit",
                "WishKit",
            ],
            path: ".upstream/icecubes",
            exclude: [
                "IceCubesApp/App/IceCubesApp-release.entitlements",
                "IceCubesApp/App/IceCubesApp.entitlements",
                "IceCubesAppIntents/ListEntity.swift",
                // Siri/AppIntents image-downsample intent uses ImageIO's CF
                // toll-free bridging (CFString/CFURL/CFDictionary), which
                // corelibs Foundation does not provide; and AppShortcuts is
                // its only referrer (an OS-discovered AppShortcutsProvider, not
                // referenced in code). Both are Siri-only and Linux-irrelevant —
                // excluded like ListEntity.swift above. The rest of the app +
                // AppIntents compile. Re-include once the ImageIO CF surface
                // lands in the CoreGraphics/ImageIO shadow.
                "IceCubesAppIntents/InlinePostImageIntent.swift",
                "IceCubesAppIntents/AppShortcuts.swift",
            ],
            sources: [
                "IceCubesApp/App",
                "IceCubesAppIntents",
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5),
                .unsafeFlags(["-strict-concurrency=minimal"]),
                .unsafeFlags(["-Xfrontend", "-default-isolation", "-Xfrontend", "MainActor"]),
                .unsafeFlags(["-Xfrontend", "-import-module", "-Xfrontend", "IceCubesShims"])
            ]
        ),
        // Real Dimillian/IceCubesApp StatusKit. This is the first high-traffic
        // package with timeline rows, status detail, and the composer. The
        // dependency list names Apple/framework shims explicitly and auto-
        // imports IceCubesShims for scoped app-storage and data fallbacks.
        .target(
            name: "StatusKit",
            dependencies: [
                "AppAccount",
                "Models",
                "MediaUI",
                "NetworkClient",
                "Env",
                "DesignSystem",
                "SwiftUI",
                "UIKit",
                "AVFoundation",
                "AVKit",
                "PhotosUI",
                "SwiftData",
                "StoreKit",
                "NaturalLanguage",
                "FoundationModels",
                "ImageIO",
                "LRUCache",
                "Nuke",
                "NukeUI",
                "EmojiText",
                "Observation",
                "Combine",
                "CoreTransferable",
                "IceCubesShims",
            ],
            path: ".upstream/icecubes/Packages/StatusKit/Sources/StatusKit",
            swiftSettings: [
                .swiftLanguageMode(.v5),
                .unsafeFlags(["-strict-concurrency=minimal"]),
                .unsafeFlags([
                    "-Xfrontend", "-solver-expression-time-threshold=120000",
                    "-Xfrontend", "-solver-scope-threshold=120000"
                ]),
                .unsafeFlags(["-Xfrontend", "-default-isolation", "-Xfrontend", "MainActor"]),
                .unsafeFlags(["-Xfrontend", "-import-module", "-Xfrontend", "IceCubesShims"]),
                .unsafeFlags(["-Xfrontend", "-import-module", "-Xfrontend", "ImageIO"]),
                .unsafeFlags(["-Xfrontend", "-import-module", "-Xfrontend", "CoreTransferable"])
            ]
        ),
        // Real Dimillian/IceCubesApp Account. This is the first package above
        // StatusKit that composes full profile/account screens, account lists,
        // filters, edit profile, metrics, and follow controls.
        .target(
            name: "IceCubesAccount",
            dependencies: [
                "AppAccount",
                "Models",
                "StatusKit",
                "NetworkClient",
                "Env",
                "DesignSystem",
                "SwiftUI",
                "UIKit",
                "PhotosUI",
                "Charts",
                "Nuke",
                "NukeUI",
                "EmojiText",
                "ButtonKit",
                "WrappingHStack",
                "Observation",
                "Combine",
                "IceCubesShims",
            ],
            path: ".upstream/icecubes/Packages/Account/Sources/Account",
            swiftSettings: [
                .swiftLanguageMode(.v5),
                .unsafeFlags(["-strict-concurrency=minimal"]),
                .unsafeFlags([
                    "-Xfrontend", "-solver-expression-time-threshold=120000",
                    "-Xfrontend", "-solver-scope-threshold=120000"
                ]),
                .unsafeFlags(["-Xfrontend", "-default-isolation", "-Xfrontend", "MainActor"]),
                .unsafeFlags(["-Xfrontend", "-import-module", "-Xfrontend", "IceCubesShims"])
            ]
        ),
        .target(
            name: "Account",
            dependencies: ["IceCubesAccount"],
            path: "Sources/IceCubesAccountModuleAlias"
        ),
        .target(
            name: "Timeline",
            dependencies: [
                "Models",
                "NetworkClient",
                "Env",
                "StatusKit",
                "DesignSystem",
                "SwiftUI",
                "SwiftData",
                "Charts",
                "Observation",
                "Bodega",
                "SwiftUIIntrospect",
                "IceCubesShims",
            ],
            path: ".upstream/icecubes/Packages/Timeline/Sources/Timeline",
            swiftSettings: [
                .swiftLanguageMode(.v5),
                .unsafeFlags(["-strict-concurrency=minimal"]),
                .unsafeFlags([
                    "-Xfrontend", "-solver-expression-time-threshold=120000",
                    "-Xfrontend", "-solver-scope-threshold=120000"
                ]),
                .unsafeFlags(["-Xfrontend", "-default-isolation", "-Xfrontend", "MainActor"]),
                .unsafeFlags(["-Xfrontend", "-import-module", "-Xfrontend", "IceCubesShims"])
            ]
        ),
        .target(
            name: "Explore",
            dependencies: [
                "Account",
                "Models",
                "NetworkClient",
                "Env",
                "StatusKit",
                "DesignSystem",
                "SwiftUI",
                "EmojiText",
                "IceCubesShims",
            ],
            path: ".upstream/icecubes/Packages/Explore/Sources/Explore",
            swiftSettings: [
                .swiftLanguageMode(.v5),
                .unsafeFlags(["-strict-concurrency=minimal"]),
                .unsafeFlags([
                    "-Xfrontend", "-solver-expression-time-threshold=120000",
                    "-Xfrontend", "-solver-scope-threshold=120000"
                ]),
                .unsafeFlags(["-Xfrontend", "-default-isolation", "-Xfrontend", "MainActor"]),
                .unsafeFlags(["-Xfrontend", "-import-module", "-Xfrontend", "IceCubesShims"])
            ]
        ),
        .target(
            name: "Notifications",
            dependencies: [
                "Models",
                "NetworkClient",
                "Env",
                "StatusKit",
                "DesignSystem",
                "SwiftUI",
                "EmojiText",
                "Observation",
                "IceCubesShims",
            ],
            path: ".upstream/icecubes/Packages/Notifications/Sources/Notifications",
            swiftSettings: [
                .swiftLanguageMode(.v5),
                .unsafeFlags(["-strict-concurrency=minimal"]),
                .unsafeFlags([
                    "-Xfrontend", "-solver-expression-time-threshold=120000",
                    "-Xfrontend", "-solver-scope-threshold=120000"
                ]),
                .unsafeFlags(["-Xfrontend", "-default-isolation", "-Xfrontend", "MainActor"]),
                .unsafeFlags(["-Xfrontend", "-import-module", "-Xfrontend", "IceCubesShims"])
            ]
        ),
        .target(
            name: "Lists",
            dependencies: [
                "Account",
                "Models",
                "NetworkClient",
                "Env",
                "DesignSystem",
                "SwiftUI",
                "EmojiText",
                "Observation",
                "Combine",
                "IceCubesShims",
            ],
            path: ".upstream/icecubes/Packages/Lists/Sources/Lists",
            swiftSettings: [
                .swiftLanguageMode(.v5),
                .unsafeFlags(["-strict-concurrency=minimal"]),
                .unsafeFlags([
                    "-Xfrontend", "-solver-expression-time-threshold=120000",
                    "-Xfrontend", "-solver-scope-threshold=120000"
                ]),
                .unsafeFlags(["-Xfrontend", "-default-isolation", "-Xfrontend", "MainActor"]),
                .unsafeFlags(["-Xfrontend", "-import-module", "-Xfrontend", "IceCubesShims"])
            ]
        ),
        .target(
            name: "Conversations",
            dependencies: [
                "Models",
                "NetworkClient",
                "Env",
                "DesignSystem",
                "StatusKit",
                "SwiftUI",
                "NukeUI",
                "IceCubesShims",
            ],
            path: ".upstream/icecubes/Packages/Conversations/Sources/Conversations",
            swiftSettings: [
                .swiftLanguageMode(.v5),
                .unsafeFlags(["-strict-concurrency=minimal"]),
                .unsafeFlags([
                    "-Xfrontend", "-solver-expression-time-threshold=120000",
                    "-Xfrontend", "-solver-scope-threshold=120000"
                ]),
                .unsafeFlags(["-Xfrontend", "-default-isolation", "-Xfrontend", "MainActor"]),
                .unsafeFlags(["-Xfrontend", "-import-module", "-Xfrontend", "IceCubesShims"])
            ]
        ),
    ]
}
#endif

// QuartzCore shim tests — the functional CALayer model, transform math, and
// async animation/transaction/display-link timing engine. Linux-only because
// the target under test is (on Apple platforms the real QuartzCore exists).
#if os(Linux)
targets += [
    .testTarget(
        name: "QuartzCoreTests",
        dependencies: ["QuartzCore"],
        path: "Tests/QuartzCoreTests"
    ),
]
#endif

// Some opt-in append paths re-introduce a target already present from a
// non-reset graph: QUILLUI_QT_GENERIC re-adds Combine/QuillSwiftUICompatibility/
// SwiftUI + the SwiftOpenUI closure, and the WireGuard-conformance block re-adds
// os/Network/Security/WireGuard* shims that the qt *reset* path drops but the
// *append* path keeps. SwiftPM rejects duplicate target names outright
// ("duplicate target named …"), which wedged the generic-Qt smoke step. Collapse
// to the FIRST occurrence — the common-graph definition, per the documented
// qt-generic collision policy. A clean build has no duplicates, so this is a
// no-op there; it only removes the collisions an opt-in re-add introduces.
do {
    var seenTargetNames = Set<String>()
    targets = targets.filter { seenTargetNames.insert($0.name).inserted }
}

let package = Package(
    name: "QuillUI",
    defaultLocalization: "en",
    platforms: [.macOS(.v14), .iOS(.v14)],
    products: products,
    dependencies: allPackageDependencies,
    targets: targets + packageTestTargets
)
