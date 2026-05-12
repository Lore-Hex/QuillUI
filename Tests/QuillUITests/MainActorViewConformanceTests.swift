import Foundation
import Testing

@Suite("MainActor View conformance")
struct MainActorViewConformanceTests {
    @Test("isolates View conformances on main-actor view types")
    func isolatesViewConformancesOnMainActorViewTypes() throws {
        let root = try packageRoot()
        let sources = root.appendingPathComponent("Sources")
        let fileManager = FileManager.default
        let enumerator = fileManager.enumerator(
            at: sources,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        var violations: [String] = []

        while let file = enumerator?.nextObject() as? URL {
            let values = try file.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true, file.pathExtension == "swift" else {
                continue
            }

            let source = try String(contentsOf: file, encoding: .utf8)
            violations.append(contentsOf: findMainActorViewConformanceViolations(in: source, file: file, root: root))
        }

        #expect(violations.isEmpty, Comment(rawValue: violations.joined(separator: "\n")))
    }

    private func findMainActorViewConformanceViolations(in source: String, file: URL, root: URL) -> [String] {
        var violations: [String] = []
        var pendingMainActorLine: Int?

        for (index, rawLine) in source.components(separatedBy: .newlines).enumerated() {
            let lineNumber = index + 1
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.isEmpty || line.hasPrefix("//") {
                continue
            }

            let lineHasMainActor = line.hasPrefix("@MainActor")
            if lineHasMainActor {
                pendingMainActorLine = lineNumber
            }

            guard line.contains("struct "), let mainActorLine = pendingMainActorLine else {
                if !lineHasMainActor {
                    pendingMainActorLine = nil
                }
                continue
            }

            defer { pendingMainActorLine = nil }

            guard line.contains(":"),
                  line.contains("View"),
                  !line.contains(": @MainActor View") else {
                continue
            }

            let relativePath = file.path.replacingOccurrences(of: root.path + "/", with: "")
            violations.append("\(relativePath):\(mainActorLine): \(line)")
        }

        return violations
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
            domain: "MainActorViewConformanceTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Unable to locate package root from \(#filePath)"]
        )
    }
}
