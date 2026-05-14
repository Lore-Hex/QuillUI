import Foundation
import Testing

@Suite("Qt backend manifest")
struct QuillQtBackendManifestTests {
    private struct QtAppSpec: Equatable {
        var product: String
        var target: String
        var qtPath: String
        var qtRuntime: String
    }

    @Test("Qt backend registers a real Qt-mode test target")
    func qtBackendRegistersRealQtModeTestTarget() throws {
        let environmentBackend = ProcessInfo.processInfo.environment["QUILLUI_LINUX_BACKEND"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        #expect(environmentBackend == "qt" || environmentBackend == "qt6")

        let root = try packageRoot()
        let manifest = try String(contentsOf: root.appendingPathComponent("Package.swift"), encoding: .utf8)

        #expect(manifest.contains("if quillUILinuxBuildBackend == .qt {\n        return ["))
        #expect(manifest.contains("name: \"QuillQtBackendManifestTests\""))
        #expect(manifest.contains("products = quillCanonicalLinuxAppProducts + ["))
        #expect(manifest.contains(".executable(name: \"quill-qt-interaction-smoke\", targets: [\"QuillQtInteractionSmoke\"])"))
        #expect(manifest.contains("allPackageDependencies = []"))
        #expect(!manifest.contains("if quillUILinuxBuildBackend == .qt {\n        return []"))
    }

    @Test("Canonical app specs resolve to explicit Qt launchers")
    func canonicalAppSpecsResolveToExplicitQtLaunchers() throws {
        let root = try packageRoot()
        let manifest = try String(contentsOf: root.appendingPathComponent("Package.swift"), encoding: .utf8)
        let script = root.appendingPathComponent("scripts/quillui-backend-products.sh")
        let appProducts = try runScript(script, arguments: ["backend-apps"])
        #expect(appProducts.status == 0, Comment(rawValue: appProducts.output))

        let expectedProducts = lines(appProducts.output)
        let specs = try canonicalAppSpecs(in: manifest)
        #expect(specs.map(\.product) == expectedProducts)

        for spec in specs {
            let mainURL = root.appendingPathComponent(spec.qtPath).appendingPathComponent("main.swift")
            #expect(
                FileManager.default.fileExists(atPath: mainURL.path),
                Comment(rawValue: "\(spec.product) must have a Qt launcher at \(spec.qtPath)/main.swift")
            )

            let launcher = try String(contentsOf: mainURL, encoding: .utf8)
            switch spec.qtRuntime {
            case "genericQtNative":
                #expect(launcher.contains("#if QUILLUI_GENERIC_QT_NATIVE_BACKEND"))
                #expect(launcher.contains("import QuillGenericQtNativeRuntime"))
                #expect(launcher.contains("QuillGenericQtNativeApp.run(QuillGenericQtAppCatalog."))
                #expect(!launcher.contains("executableName:"))
                #expect(!launcher.contains("import QuillUIQt"))
            case "enchantedQtNative":
                #expect(launcher.contains("#if QUILLUI_ENCHANTED_QT_NATIVE_BACKEND"))
                #expect(launcher.contains("import QuillEnchantedQtNativeRuntime"))
                #expect(launcher.contains("QuillEnchantedQtNativeApp.run()"))
                #expect(launcher.contains("#else"))
            case "wireGuardQtNative":
                #expect(launcher.contains("#if QUILLUI_WIREGUARD_QT_NATIVE_BACKEND"))
                #expect(launcher.contains("import QuillWireGuardQtNativeRuntime"))
                #expect(launcher.contains("QuillWireGuardQtNativeApp.run()"))
                #expect(launcher.contains("#else"))
            default:
                Issue.record("Unknown Qt runtime case \(spec.qtRuntime) for \(spec.product)")
            }
        }
    }

    private func canonicalAppSpecs(in manifest: String) throws -> [QtAppSpec] {
        let regex = try NSRegularExpression(
            pattern: #"\.init\(product: "([^"]+)", target: "([^"]+)", qtPath: "([^"]+)", qtRuntime: \.([A-Za-z0-9_]+)\)"#
        )
        let nsRange = NSRange(manifest.startIndex..<manifest.endIndex, in: manifest)
        return regex.matches(in: manifest, range: nsRange).compactMap { match in
            guard
                let productRange = Range(match.range(at: 1), in: manifest),
                let targetRange = Range(match.range(at: 2), in: manifest),
                let qtPathRange = Range(match.range(at: 3), in: manifest),
                let runtimeRange = Range(match.range(at: 4), in: manifest)
            else {
                return nil
            }

            return QtAppSpec(
                product: String(manifest[productRange]),
                target: String(manifest[targetRange]),
                qtPath: String(manifest[qtPathRange]),
                qtRuntime: String(manifest[runtimeRange])
            )
        }
    }

    private func lines(_ output: String) -> [String] {
        output.split(whereSeparator: \.isNewline).map(String.init)
    }

    private func runScript(
        _ script: URL,
        arguments: [String] = []
    ) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = script
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (process.terminationStatus, output)
    }

    private func packageRoot() throws -> URL {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let fileManager = FileManager.default

        while directory.path != "/" {
            if fileManager.fileExists(atPath: directory.appendingPathComponent("Package.swift").path) {
                return directory
            }
            directory.deleteLastPathComponent()
        }

        throw NSError(
            domain: "QuillQtBackendManifestTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Unable to locate package root from \(#filePath)"]
        )
    }
}
