import Foundation
import Testing

@Suite("Vendored source ignores")
struct VendoredSourceIgnoreTests {
    @Test("Git ignore hides slim-vendored tree-sitter checkout bulk")
    func gitIgnoreHidesSlimVendoredTreeSitterCheckoutBulk() throws {
        let root = try packageRoot()
        let paths = [
            "third_party/tree-sitter/.cargo",
            "third_party/tree-sitter/.dockerignore",
            "third_party/tree-sitter/.editorconfig",
            "third_party/tree-sitter/.gitattributes",
            "third_party/tree-sitter/.gitignore",
            "third_party/tree-sitter/CONTRIBUTING.md",
            "third_party/tree-sitter/Cargo.lock",
            "third_party/tree-sitter/Cargo.toml",
            "third_party/tree-sitter/Dockerfile",
            "third_party/tree-sitter/FUNDING.json",
            "third_party/tree-sitter/build.zig",
            "third_party/tree-sitter/build.zig.zon",
            "third_party/tree-sitter/cli",
            "third_party/tree-sitter/highlight",
            "third_party/tree-sitter/lib/binding_rust",
            "third_party/tree-sitter/lib/binding_web",
            "third_party/tree-sitter/lib/language",
            "third_party/tree-sitter/rustfmt.toml",
            "third_party/tree-sitter/tags",
            "third_party/tree-sitter/xtask"
        ]

        let result = try run(
            URL(fileURLWithPath: "/usr/bin/env"),
            arguments: ["git", "-C", root.path, "check-ignore", "-v"] + paths
        )

        #expect(result.status == 0, Comment(rawValue: result.output))
        for path in paths {
            #expect(result.output.contains(path), Comment(rawValue: "Missing ignore match for \(path)\n\(result.output)"))
        }
    }

    private func packageRoot() throws -> URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 {
            url.deleteLastPathComponent()
        }
        return url
    }

    private func run(
        _ executable: URL,
        arguments: [String]
    ) throws -> (status: Int32, output: String) {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}
