import Foundation

public enum Zip {
    public enum ZipError: Error, Equatable {
        case commandNotFound
        case extractionFailed(Int32, String)
    }

    public typealias Progress = (Double) -> Void
    public typealias FileOutputHandler = (URL) -> Void

    public static func unzipFile(
        _ zipFilePath: URL,
        destination: URL,
        overwrite: Bool,
        password: String?,
        progress: Progress?,
        fileOutputHandler: FileOutputHandler?
    ) throws {
        let executable = ["/usr/bin/unzip", "/bin/unzip"].first {
            FileManager.default.isExecutableFile(atPath: $0)
        }
        guard let executable else {
            throw ZipError.commandNotFound
        }

        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        progress?(0)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        var arguments = ["-q", overwrite ? "-o" : "-n"]
        if let password {
            arguments += ["-P", password]
        }
        arguments += [zipFilePath.path, "-d", destination.path]
        process.arguments = arguments

        let output = Pipe()
        process.standardOutput = output
        process.standardError = output

        try process.run()
        process.waitUntilExit()

        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        let outputString = String(decoding: outputData, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw ZipError.extractionFailed(process.terminationStatus, outputString)
        }

        if let fileOutputHandler,
           let enumerator = FileManager.default.enumerator(at: destination, includingPropertiesForKeys: nil) {
            for case let url as URL in enumerator {
                fileOutputHandler(url)
            }
        }

        progress?(1)
    }
}
