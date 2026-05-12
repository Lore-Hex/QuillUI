// QuillMainExtractPlugin
// ======================
// SwiftPM build-tool plugin. For every line of `MainExtractInputs.txt`
// in the target's source dir, runs QuillMainExtractTool to produce a
// `@main`-stripped copy of that upstream file. The generated copies
// are added to the target's compile sources, so any side declarations
// next to the upstream `@main` (extensions, helper types, constants)
// land in our build automatically — no hand-mirrored support shim
// required.
//
// MainExtractInputs.txt format: one path per line, package-root-
// relative. Blank lines and `#`-prefixed comments are ignored.
//
// To opt a target in, add to its declaration:
//   .target(
//     name: "Foo",
//     ...
//     plugins: [.plugin(name: "QuillMainExtractPlugin")]
//   )
// and drop a `MainExtractInputs.txt` next to the target's source files.

import PackagePlugin
import Foundation

@main
struct QuillMainExtractPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        guard let sourceDirectoryURL = sourceDirectoryURL(for: target) else { return [] }

        // Find the config file in the target's source directory.
        let configURL = sourceDirectoryURL
            .appendingPathComponent("MainExtractInputs.txt")
        guard FileManager.default.fileExists(atPath: configURL.path) else { return [] }

        let configText: String
        do {
            configText = try String(contentsOf: configURL, encoding: .utf8)
        } catch {
            return []
        }

        // Resolve each non-blank, non-comment line to a package-root-
        // relative path.
        let packageRoot = context.package.directoryURL
        let inputURLs: [URL] = configText
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            .map { rel in
                rel.hasPrefix("/")
                    ? URL(fileURLWithPath: rel)
                    : packageRoot.appendingPathComponent(rel)
            }

        guard !inputURLs.isEmpty else { return [] }

        let tool = try context.tool(named: "QuillMainExtractTool")
        let workDir = context.pluginWorkDirectoryURL

        return inputURLs.map { inputURL in
            let basename = inputURL.lastPathComponent
            let stem = (basename as NSString).deletingPathExtension
            let outputURL = workDir.appendingPathComponent("\(stem).MainStripped.swift")

            return .buildCommand(
                displayName: "Extract @main side declarations from \(basename)",
                executable: tool.url,
                arguments: ["--output", outputURL.path, inputURL.path],
                inputFiles: [inputURL],
                outputFiles: [outputURL]
            )
        }
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
