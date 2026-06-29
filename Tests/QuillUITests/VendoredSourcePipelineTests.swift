import Foundation
import Testing

@Suite("Vendored source pipeline")
struct VendoredSourcePipelineTests {
    @Test("Release packager preserves app source identity for vendored builds")
    func releasePackagerPreservesAppSourceIdentity() throws {
        let root = try packageRoot()
        let source = try String(
            contentsOf: root.appendingPathComponent("scripts/package-swiftui-linux-app.sh"),
            encoding: .utf8
        )

        #expect(source.contains("SOURCE_APP=\"${QUILLUI_APP_SOURCE_APP:-}\""))
        #expect(source.contains("--source-app NAME"))
        #expect(source.contains("--source-subdir PATH"))
        #expect(source.contains("--source-dir and --source-app are mutually exclusive"))
        #expect(source.contains("BUILD_SOURCE_ARGS=(--source-app \"$SOURCE_APP\")"))
        #expect(source.contains("BUILD_SOURCE_ARGS+=(--source-subdir \"$SOURCE_SUBDIR\")"))
        #expect(source.contains("BUILD_SOURCE_ARGS=(--source-dir \"$SOURCE_DIR\")"))
        #expect(source.contains("\"${BUILD_SOURCE_ARGS[@]}\""))
    }

    @Test("Enchanted wrapper defaults to vendored source app builds")
    func enchantedWrapperDefaultsToVendoredSourceAppBuilds() throws {
        let root = try packageRoot()
        let source = try String(
            contentsOf: root.appendingPathComponent("scripts/build-enchanted-linux.sh"),
            encoding: .utf8
        )

        #expect(source.contains("SOURCE_ARGS=(--source-app enchanted --source-subdir Enchanted)"))
        #expect(source.contains("SOURCE_ARGS=(--source-dir \"$APP_DIR\")"))
        #expect(source.contains("\"${SOURCE_ARGS[@]}\""))
    }

    @Test("Enchanted parity release packaging uses source app identity")
    func enchantedParityReleasePackagingUsesSourceAppIdentity() throws {
        let root = try packageRoot()
        let source = try String(
            contentsOf: root.appendingPathComponent(".github/workflows/enchanted-parity.yml"),
            encoding: .utf8
        )

        #expect(source.contains("scripts/package-swiftui-linux-app.sh"))
        #expect(source.contains("--source-app enchanted"))
        #expect(source.contains("--source-subdir Enchanted"))
        #expect(!source.contains("ENCHANTED_APP_DIR=\"$(quillui_resolve_enchanted_source_dir \"$PWD\")\""))
    }

    private func packageRoot() throws -> URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 {
            url.deleteLastPathComponent()
        }
        return url
    }
}
