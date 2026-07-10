#if os(Linux)
import Foundation
import QuillFoundation
import Testing

@Suite("QuillFoundation FileHandle and NSUserUnixTask Linux shims")
struct FileHandleUnixTaskLinuxTests {
    @Test("FileHandle.bytes.lines decodes pipe output")
    func fileHandleBytesLinesDecodePipeOutput() async throws {
        let pipe = Pipe()
        let collector = Task<[String], Error> {
            var lines: [String] = []
            for try await line in pipe.fileHandleForReading.bytes.lines {
                lines.append(line)
            }
            return lines
        }

        try pipe.fileHandleForWriting.write(contentsOf: Data("alpha\nbeta\n".utf8))
        pipe.fileHandleForWriting.closeFile()

        let lines = try await collector.value
        #expect(lines == ["alpha", "beta"])
    }

    @Test("NSUserUnixTask executes a local process with redirected output")
    func nsUserUnixTaskExecutesProcessWithRedirectedOutput() async throws {
        let stdout = Pipe()
        let task = try NSUserUnixTask(url: URL(fileURLWithPath: "/bin/sh"))
        task.standardOutput = stdout.fileHandleForWriting

        try await task.execute(withArguments: ["-c", "printf 'quill\\n'"])
        stdout.fileHandleForWriting.closeFile()

        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        #expect(String(decoding: output, as: UTF8.self) == "quill\n")
    }
}
#endif
