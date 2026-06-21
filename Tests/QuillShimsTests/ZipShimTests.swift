import Foundation
import Testing
import Zip

@Suite("Zip shim")
struct ZipShimTests {

    @Test("unzipFile reports command failures through the Zip API shape")
    func unzipFileInvalidArchiveFailure() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("quill-zip-shim-\(UUID().uuidString)", isDirectory: true)
        let archive = directory.appendingPathComponent("invalid.zip")
        let destination = directory.appendingPathComponent("out", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not a zip".utf8).write(to: archive)
        defer { try? FileManager.default.removeItem(at: directory) }

        var progressValues: [Double] = []
        do {
            try Zip.unzipFile(
                archive,
                destination: destination,
                overwrite: true,
                password: nil,
                progress: { progressValues.append($0) },
                fileOutputHandler: nil
            )
            Issue.record("Expected invalid zip archive to fail")
        } catch Zip.ZipError.extractionFailed {
            #expect(progressValues == [0])
        } catch Zip.ZipError.commandNotFound {
            return
        }
    }
}
