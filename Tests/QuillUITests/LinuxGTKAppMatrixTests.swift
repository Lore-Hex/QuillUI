import Foundation
import Testing

@Suite("Linux GTK app matrix")
struct LinuxGTKAppMatrixTests {
    @Test("covers each user-facing app product once")
    func coversEachUserFacingAppProductOnce() throws {
        let root = try packageRoot()
        let matrixScript = root.appendingPathComponent("scripts/linux-gtk-app-products.sh")

        let result = try runScript(matrixScript)
        #expect(result.status == 0, Comment(rawValue: result.output))

        let products = result.output
            .split(whereSeparator: \.isNewline)
            .map(String.init)
        let expected = [
            "quill-enchanted",
            "quill-enchanted-upstream-slice",
            "quill-icecubes",
            "quill-netnewswire",
            "quill-codeedit",
            "quill-signal",
            "quill-telegram",
            "quill-iina",
            "quill-wireguard"
        ]

        #expect(products == expected)
        #expect(Set(products).count == products.count)

        let manifest = try String(contentsOf: root.appendingPathComponent("Package.swift"), encoding: .utf8)
        for product in products {
            #expect(manifest.contains(".executable(name: \"\(product)\""))
        }

        let workflow = try String(
            contentsOf: root.appendingPathComponent(".github/workflows/linux-ci.yml"),
            encoding: .utf8
        )
        #expect(workflow.contains("scripts/linux-gtk-app-products.sh"))
        #expect(!workflow.contains("QuillSignal GTK visual smoke"))
        #expect(!workflow.contains("for product in quill-signal quill-telegram"))
    }

    private func runScript(_ script: URL) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path]

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
            domain: "LinuxGTKAppMatrixTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Unable to locate package root from \(#filePath)"]
        )
    }
}
