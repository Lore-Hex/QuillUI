import Foundation

/// The production `QuillWireGuardCommandRunner`: executes a command via
/// `Foundation.Process` (through `/usr/bin/env` so `wg` / `wg-quick` / `systemctl`
/// resolve from PATH) and returns its stdout. Throws `QuillWireGuardRuntimeError
/// .commandFailed` on a non-zero exit, surfacing stderr.
///
/// Activating a real tunnel needs root + the wireguard kernel module, so end-to-end
/// activation is exercised on a privileged Debian/Armbian host — but the runner's
/// own stdout-capture / failure-handling is verified in CI by running harmless
/// commands (`echo`, `false`).
public struct QuillWireGuardProcessRunner: QuillWireGuardCommandRunner {
    public init() {}

    public func run(_ command: QuillWireGuardCommand) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command.executable] + command.arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdinPipe = command.standardInput != nil ? Pipe() : nil
        if let stdinPipe {
            process.standardInput = stdinPipe
        }

        try process.run()

        // Feed stdin (e.g. `wg pubkey`) then close it to signal EOF so the command
        // finishes reading. Small payloads only (a key), so writing before draining
        // stdout can't deadlock.
        if let stdinPipe, let input = command.standardInput {
            stdinPipe.fileHandleForWriting.write(Data(input.utf8))
            try? stdinPipe.fileHandleForWriting.close()
        }

        // Drain stdout to EOF before waiting so a large `wg show dump` can't deadlock
        // on a full pipe buffer.
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let stderr = String(
                data: stderrPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
            throw QuillWireGuardRuntimeError.commandFailed(
                command: command.executable,
                status: process.terminationStatus,
                stderr: stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        return String(data: stdoutData, encoding: .utf8) ?? ""
    }
}
