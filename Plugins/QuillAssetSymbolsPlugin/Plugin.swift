// QuillAssetSymbolsPlugin
// =======================
// SwiftPM build-tool plugin. For every `.xcassets` directory in a target's
// source tree, runs QuillAssetSymbolsTool to emit a Swift file with
// Color/ShapeStyle/UIColor/NSColor extensions for each color asset.
//
// To opt a target into Asset Catalog Symbol Generation, add this plugin
// to the target's `plugins:` array in Package.swift:
//
//   .target(name: "Foo",
//           ...,
//           plugins: [.plugin(name: "QuillAssetSymbolsPlugin")])
//
// The generated file is added to the target's compile sources
// automatically; consumers can refer to `Color.bgCustom` etc. without
// any additional import.

import PackagePlugin
import Foundation

@main
struct QuillAssetSymbolsPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        guard let sourceDirectoryURL = sourceDirectoryURL(for: target) else { return [] }

        let assetCatalogURLs = collectAssetCatalogs(under: sourceDirectoryURL)
        guard !assetCatalogURLs.isEmpty else { return [] }

        let tool = try context.tool(named: "QuillAssetSymbolsTool")
        let outputURL = context.pluginWorkDirectoryURL
            .appendingPathComponent("GeneratedAssetSymbols.swift")

        var arguments = ["--output", outputURL.path]
        arguments.append(contentsOf: assetCatalogURLs.map(\.path))

        return [
            .buildCommand(
                displayName: "Generate asset symbols for \(target.name)",
                executable: tool.url,
                arguments: arguments,
                inputFiles: assetCatalogURLs,
                outputFiles: [outputURL]
            )
        ]
    }

    private func collectAssetCatalogs(under rootURL: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        var catalogs: [URL] = []
        for case let candidate as URL in enumerator where candidate.pathExtension == "xcassets" {
            catalogs.append(candidate)
            enumerator.skipDescendants()
        }
        return catalogs.sorted { $0.path < $1.path }
    }

    private func sourceDirectoryURL(for target: Target) -> URL? {
        if let swiftTarget = target as? SwiftSourceModuleTarget {
            return swiftTarget.directoryURL
        }
        if let clangTarget = target as? ClangSourceModuleTarget {
            return clangTarget.directoryURL
        }
        return nil
    }
}
