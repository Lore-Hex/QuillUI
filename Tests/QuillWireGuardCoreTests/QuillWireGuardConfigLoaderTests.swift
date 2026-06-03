import Foundation
import Testing
@testable import QuillWireGuardCore

@Suite("QuillWireGuard config loader")
struct QuillWireGuardConfigLoaderTests {

    private func makeTempDir() throws -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("wg-loader-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    private func write(_ contents: String, _ name: String, in dir: String) throws {
        try contents.write(toFile: "\(dir)/\(name)", atomically: true, encoding: .utf8)
    }

    @Test("a missing directory yields an empty result")
    func missingDirectory() {
        let result = QuillWireGuardConfigLoader.load(directory: "/no/such/dir-\(UUID().uuidString)")
        #expect(result.tunnels.isEmpty)
        #expect(result.failures.isEmpty)
    }

    @Test("loads .conf files named after the interface, in order, ignoring non-conf")
    func loadsConfigs() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let valid = QuillWireGuardFixtures.tunnels[0].wgQuickConfig()
        try write(valid, "home.conf", in: dir)
        try write(valid, "work.conf", in: dir)
        try write("not a config", "notes.txt", in: dir)  // non-.conf ignored

        let result = QuillWireGuardConfigLoader.load(directory: dir)

        #expect(result.failures.isEmpty)
        #expect(result.tunnels.map(\.name) == ["home", "work"])
        #expect(result.tunnels.allSatisfy { !$0.interface.privateKey.isEmpty })
    }

    @Test("a malformed config becomes a failure; valid ones still load")
    func malformedCollected() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        try write(QuillWireGuardFixtures.tunnels[0].wgQuickConfig(), "good.conf", in: dir)
        try write("# no interface section here\n", "bad.conf", in: dir)

        let result = QuillWireGuardConfigLoader.load(directory: dir)

        #expect(result.tunnels.map(\.name) == ["good"])
        #expect(result.failures.count == 1)
        #expect(result.failures.first?.path.hasSuffix("bad.conf") == true)
    }
}
