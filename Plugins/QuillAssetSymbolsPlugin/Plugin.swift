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
        guard let sourceTarget = target as? SourceModuleTarget else { return [] }

        // SwiftPM 5.6–6.0 expose `Path` (string-based); newer
        // toolchains expose URL-based APIs. The string-based form
        // works on all supported toolchains, so keep it until the
        // package can move to swift-tools-version 6.1.
        let rootPath = sourceTarget.directory.string
        let assetCatalogPaths = collectAssetCatalogs(under: rootPath)
        guard !assetCatalogPaths.isEmpty else { return [] }

        let tool = try context.tool(named: "QuillAssetSymbolsTool")
        let workDir = context.pluginWorkDirectory.string
        let outputPath = workDir + "/GeneratedAssetSymbols.swift"

        var arguments = ["--output", outputPath]
        arguments.append(contentsOf: assetCatalogPaths)

        return [
            .buildCommand(
                displayName: "Generate asset symbols for \(target.name)",
                executable: tool.path,
                arguments: arguments,
                inputFiles: assetCatalogPaths.map { Path($0) },
                outputFiles: [Path(outputPath)]
            )
        ]
    }

    private func collectAssetCatalogs(under rootPath: String) -> [String] {
        let url = URL(fileURLWithPath: rootPath)
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        var catalogs: [String] = []
        for case let candidate as URL in enumerator where candidate.pathExtension == "xcassets" {
            catalogs.append(candidate.path)
            enumerator.skipDescendants()
        }
        return catalogs.sorted()
    }
}
