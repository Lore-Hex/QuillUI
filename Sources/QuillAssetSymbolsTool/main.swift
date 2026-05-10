// QuillAssetSymbolsTool
// =====================
// Reads one or more `.xcassets` catalogs and emits a Swift file that
// declares Color/UIColor/NSColor/ShapeStyle extensions for every
// `<name>.colorset` it finds. This replaces Xcode 15+ Asset Catalog
// Symbol Generation for SwiftPM builds.
//
// Invocation (as a SwiftPM build-tool plugin):
//   QuillAssetSymbolsTool \
//     --output /derived/path/AssetSymbols.swift \
//     /input/Path/Assets.xcassets [/input/Path2/Assets.xcassets …]
//
// The generated file:
//   - Declares each color asset as `Color.<name>`
//   - Mirrors as `ShapeStyle == Color` static so `.background(.foo)` works
//   - On macOS also emits `NSColor.<name>`; on iOS emits `UIColor.<name>`
//     so `Color(.foo)` resolves through the platform color initializer.
//   - Pulls components verbatim from each colorset's Contents.json.
//   - Preserves dark-appearance variants where present.

import Foundation

// MARK: - Models

struct ColorAsset {
    let name: String
    let lightComponents: ColorComponents?
    let darkComponents: ColorComponents?
}

struct ColorComponents {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    static func parse(_ dict: [String: Any]) -> ColorComponents? {
        guard let comps = dict["components"] as? [String: Any] else { return nil }

        let alpha = doubleValue(comps["alpha"]) ?? 1.0
        if let white = doubleValue(comps["white"]) {
            return ColorComponents(red: white, green: white, blue: white, alpha: alpha)
        }
        guard let r = doubleValue(comps["red"]),
              let g = doubleValue(comps["green"]),
              let b = doubleValue(comps["blue"]) else {
            return nil
        }
        return ColorComponents(red: r, green: g, blue: b, alpha: alpha)
    }

    private static func doubleValue(_ raw: Any?) -> Double? {
        if let d = raw as? Double { return d }
        if let i = raw as? Int { return Double(i) }
        guard let s = raw as? String else { return nil }
        if s.hasPrefix("0x") || s.hasPrefix("0X") {
            let hex = String(s.dropFirst(2))
            if let value = Int(hex, radix: 16) {
                return Double(value) / 255.0
            }
        }
        return Double(s)
    }
}

// MARK: - Helpers

func sanitize(_ name: String) -> String {
    // Xcode 15+ Asset Catalog Symbol Generation rules:
    //   - Lowercase the first letter ("Amber" → "amber")
    //   - Camel-case dotted/spaced names ("line.3.horizontal" →
    //     "line3Horizontal", "Hello World" → "helloWorld")
    //   - Strip non-identifier chars
    let separators: Set<Character> = [".", " ", "-", "/"]
    var out = ""
    var capitalizeNext = false
    var first = true
    for ch in name {
        if separators.contains(ch) {
            capitalizeNext = true
            continue
        }
        if first {
            if ch.isLetter {
                out.append(Character(ch.lowercased()))
            } else if ch == "_" {
                out.append(ch)
            } else {
                out.append("_")
                if ch.isNumber { out.append(ch) }
            }
            first = false
            capitalizeNext = false
            continue
        }
        if capitalizeNext, ch.isLetter {
            out.append(Character(ch.uppercased()))
            capitalizeNext = false
        } else if ch.isLetter || ch.isNumber || ch == "_" {
            out.append(ch)
            capitalizeNext = false
        } else {
            out.append("_")
            capitalizeNext = false
        }
    }
    return out
}

func colorLiteral(_ c: ColorComponents) -> String {
    let r = String(format: "%.4f", c.red)
    let g = String(format: "%.4f", c.green)
    let b = String(format: "%.4f", c.blue)
    let a = String(format: "%.4f", c.alpha)
    return "Color(.sRGB, red: \(r), green: \(g), blue: \(b), opacity: \(a))"
}

func bodyExpression(for asset: ColorAsset) -> String {
    switch (asset.lightComponents, asset.darkComponents) {
    case (let light?, let dark?):
        return "_quillDynamic(light: \(colorLiteral(light)), dark: \(colorLiteral(dark)))"
    case (let light?, nil):
        return colorLiteral(light)
    case (nil, let dark?):
        return colorLiteral(dark)
    case (nil, nil):
        return "Color.primary"
    }
}

func loadColorAsset(at colorsetURL: URL) -> ColorAsset? {
    let name = colorsetURL.deletingPathExtension().lastPathComponent
    let contents = colorsetURL.appendingPathComponent("Contents.json")
    guard let data = try? Data(contentsOf: contents),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let colors = json["colors"] as? [[String: Any]] else {
        return nil
    }

    var lightComponents: ColorComponents?
    var darkComponents: ColorComponents?

    for entry in colors {
        guard let color = entry["color"] as? [String: Any] else { continue }
        let appearances = entry["appearances"] as? [[String: Any]]
        let isDark = appearances?.contains(where: { ($0["value"] as? String) == "dark" }) ?? false
        let parsed = ColorComponents.parse(color)
        if isDark {
            darkComponents = parsed
        } else {
            lightComponents = parsed
        }
    }

    return ColorAsset(name: name, lightComponents: lightComponents, darkComponents: darkComponents)
}

func scan(_ assetsPath: String) -> [ColorAsset] {
    let url = URL(fileURLWithPath: assetsPath)
    guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) else {
        return []
    }
    var assets: [ColorAsset] = []
    for case let candidate as URL in enumerator where candidate.pathExtension == "colorset" {
        if let asset = loadColorAsset(at: candidate) {
            assets.append(asset)
        }
    }
    return assets.sorted { $0.name < $1.name }
}

/// Scan for image assets (.imageset / .symbolset) — Xcode 15+
/// generates `ImageResource.<name>` for each.
func scanImageAssets(_ assetsPath: String) -> [String] {
    let url = URL(fileURLWithPath: assetsPath)
    guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) else {
        return []
    }
    var names: [String] = []
    for case let candidate as URL in enumerator
    where candidate.pathExtension == "imageset" || candidate.pathExtension == "symbolset" {
        names.append(candidate.deletingPathExtension().lastPathComponent)
    }
    return names.sorted()
}

// MARK: - Argument parsing

let args = CommandLine.arguments
guard args.count >= 4 else {
    FileHandle.standardError.write(Data("usage: QuillAssetSymbolsTool --output <path.swift> <xcassets …>\n".utf8))
    exit(2)
}

var outputPath: String?
var assetsPaths: [String] = []
do {
    var i = 1
    while i < args.count {
        let arg = args[i]
        if arg == "--output" {
            guard i + 1 < args.count else {
                FileHandle.standardError.write(Data("missing value for --output\n".utf8))
                exit(2)
            }
            outputPath = args[i + 1]
            i += 2
        } else {
            assetsPaths.append(arg)
            i += 1
        }
    }
}
guard let outputPath else {
    FileHandle.standardError.write(Data("--output is required\n".utf8))
    exit(2)
}

// MARK: - Driver

var allAssets: [ColorAsset] = []
var allImageNames: [String] = []
for path in assetsPaths {
    allAssets.append(contentsOf: scan(path))
    allImageNames.append(contentsOf: scanImageAssets(path))
}

// Dedupe by name.
var seen: Set<String> = []
var assets: [ColorAsset] = []
for asset in allAssets where !seen.contains(asset.name) {
    seen.insert(asset.name)
    assets.append(asset)
}
var seenImages: Set<String> = []
var imageNames: [String] = []
for n in allImageNames where !seenImages.contains(n) {
    seenImages.insert(n)
    imageNames.append(n)
}

// MARK: - Code generation

var lines: [String] = []
lines.append("// Generated by QuillAssetSymbolsTool. Do not edit.")
lines.append("//")
lines.append("// Source asset catalogs:")
for path in assetsPaths {
    lines.append("//   - \(path)")
}
lines.append("//")
lines.append("// One Color/UIColor/NSColor/ShapeStyle extension per .colorset.")
lines.append("")
lines.append("import SwiftUI")
lines.append("#if canImport(AppKit)")
lines.append("import AppKit")
lines.append("#elseif canImport(UIKit)")
lines.append("import UIKit")
lines.append("#endif")
lines.append("")

// Color statics
lines.append("public extension Color {")
for asset in assets {
    let id = sanitize(asset.name)
    let body = bodyExpression(for: asset)
    lines.append("    static let \(id): Color = \(body)")
}
lines.append("}")
lines.append("")

// ShapeStyle bridges
lines.append("public extension ShapeStyle where Self == Color {")
for asset in assets {
    let id = sanitize(asset.name)
    lines.append("    static var \(id): Color { .\(id) }")
}
lines.append("}")
lines.append("")

// NSColor / UIColor static helpers
lines.append("#if canImport(AppKit) && !targetEnvironment(macCatalyst)")
lines.append("public extension NSColor {")
for asset in assets {
    let id = sanitize(asset.name)
    lines.append("    static var \(id): NSColor { NSColor(Color.\(id)) }")
}
lines.append("}")
lines.append("#elseif canImport(UIKit)")
lines.append("public extension UIColor {")
for asset in assets {
    let id = sanitize(asset.name)
    lines.append("    static var \(id): UIColor { UIColor(Color.\(id)) }")
}
lines.append("}")
lines.append("#endif")
lines.append("")

// ImageResource extensions (Xcode 15+ Asset Catalog Symbol Generation
// emits one `ImageResource.<name>` per imageset/symbolset). Gated to
// availability since `ImageResource` itself only exists on the SDKs
// that ship with Xcode 15+.
if !imageNames.isEmpty {
    lines.append("#if canImport(SwiftUI)")
    lines.append("@available(macOS 14.0, iOS 17.0, tvOS 17.0, watchOS 10.0, visionOS 1.0, *)")
    lines.append("public extension ImageResource {")
    for name in imageNames {
        let id = sanitize(name)
        // The ImageResource init takes (name:bundle:) — bundle is whatever
        // resource bundle SPM synthesizes for our target.
        lines.append("    static var \(id): ImageResource { ImageResource(name: \"\(name)\", bundle: .main) }")
    }
    lines.append("}")
    lines.append("#endif")
    lines.append("")
}

// Dynamic helper
lines.append("@inline(__always)")
lines.append("private func _quillDynamic(light: Color, dark: Color) -> Color {")
lines.append("#if canImport(AppKit) && !targetEnvironment(macCatalyst)")
lines.append("    return Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in")
lines.append("        let isDark = appearance.bestMatch(from: [.darkAqua, .vibrantDark, .accessibilityHighContrastDarkAqua, .accessibilityHighContrastVibrantDark]) != nil")
lines.append("        return NSColor(isDark ? dark : light)")
lines.append("    }))")
lines.append("#elseif canImport(UIKit)")
lines.append("    return Color(uiColor: UIColor { traits in")
lines.append("        traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)")
lines.append("    })")
lines.append("#else")
lines.append("    return light")
lines.append("#endif")
lines.append("}")

let swift = lines.joined(separator: "\n") + "\n"

// MARK: - Write

let outputURL = URL(fileURLWithPath: outputPath)
try? FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
do {
    try swift.write(to: outputURL, atomically: true, encoding: .utf8)
} catch {
    FileHandle.standardError.write(Data("failed to write \(outputPath): \(error)\n".utf8))
    exit(1)
}
