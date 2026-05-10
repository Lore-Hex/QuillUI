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
        guard let sourceTarget = target as? SourceModuleTarget else { return [] }

        // Find the config file in the target's source directory.
        let targetDir = sourceTarget.directory.string
        let configPath = targetDir + "/MainExtractInputs.txt"
        guard FileManager.default.fileExists(atPath: configPath) else { return [] }

        let configText: String
        do {
            configText = try String(contentsOfFile: configPath, encoding: .utf8)
        } catch {
            return []
        }

        // Resolve each non-blank, non-comment line to a package-root-
        // relative path.
        let packageRoot = context.package.directory.string
        let inputPaths: [String] = configText
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            .map { rel in
                rel.hasPrefix("/") ? rel : "\(packageRoot)/\(rel)"
            }

        guard !inputPaths.isEmpty else { return [] }

        let tool = try context.tool(named: "QuillMainExtractTool")
        let workDir = context.pluginWorkDirectory.string

        return inputPaths.map { input in
            let basename = (input as NSString).lastPathComponent
            let stem = (basename as NSString).deletingPathExtension
            let output = "\(workDir)/\(stem).MainStripped.swift"

            return .buildCommand(
                displayName: "Extract @main side declarations from \(basename)",
                executable: tool.path,
                arguments: ["--output", output, input],
                inputFiles: [Path(input)],
                outputFiles: [Path(output)]
            )
        }
    }
}
