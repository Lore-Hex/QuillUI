import CoreTransferable
import Foundation
import SwiftOpenUI
import UniformTypeIdentifiers

#if os(Linux)
public enum QuillFileImporter {
    private static let environmentKey = "QUILLUI_FILE_IMPORTER_SELECTION"
    private static let testSelection = TestSelection()

    public static func setTestSelection(_ url: URL?) {
        setTestSelections(url.map { [$0] } ?? [])
    }

    public static func setTestSelections(_ urls: [URL]) {
        testSelection.set(urls)
    }

    public static func selectURL(allowedContentTypes: [UTType]) -> Result<URL, Error> {
        selectURLs(allowedContentTypes: allowedContentTypes, allowsMultipleSelection: false)
            .flatMap { urls in
                guard let url = urls.first else {
                    return .failure(QuillCompatibilityError.fileSelectionUnavailable)
                }
                return .success(url)
            }
    }

    public static func selectURLs(
        allowedContentTypes: [UTType],
        allowsMultipleSelection: Bool
    ) -> Result<[URL], Error> {
        if !testSelection.urls.isEmpty {
            return validate(testSelection.urls, allowedContentTypes: allowedContentTypes, allowsMultipleSelection: allowsMultipleSelection)
        }

        if let environmentValue = ProcessInfo.processInfo.environment[environmentKey],
           !environmentValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let urls = environmentValue
                .split(whereSeparator: \.isNewline)
                .map { URL(fileURLWithPath: String($0)) }
            return validate(urls, allowedContentTypes: allowedContentTypes, allowsMultipleSelection: allowsMultipleSelection)
        }

        for command in fileSelectionCommands(allowsMultipleSelection: allowsMultipleSelection) {
            if let urls = run(command: command) {
                return validate(urls, allowedContentTypes: allowedContentTypes, allowsMultipleSelection: allowsMultipleSelection)
            }
        }

        return .failure(QuillCompatibilityError.fileSelectionUnavailable)
    }

    private final class TestSelection: @unchecked Sendable {
        private let lock = NSLock()
        private var selectedURLs: [URL] = []

        var urls: [URL] {
            lock.withLock { selectedURLs }
        }

        func set(_ urls: [URL]) {
            lock.withLock {
                selectedURLs = urls
            }
        }
    }

    private static func fileSelectionCommands(allowsMultipleSelection: Bool) -> [[String]] {
        if allowsMultipleSelection {
            return [
                ["zenity", "--file-selection", "--multiple", "--separator=\n"],
                ["kdialog", "--getopenfilename", ".", "", "--multiple", "--separate-output"],
                ["yad", "--file-selection", "--multiple", "--separator=\n"]
            ]
        }
        return [
            ["zenity", "--file-selection"],
            ["kdialog", "--getopenfilename"],
            ["yad", "--file-selection"]
        ]
    }

    private static func validate(
        _ urls: [URL],
        allowedContentTypes: [UTType],
        allowsMultipleSelection: Bool
    ) -> Result<[URL], Error> {
        guard !urls.isEmpty else {
            return .failure(QuillCompatibilityError.fileSelectionUnavailable)
        }

        let selected = allowsMultipleSelection ? urls : Array(urls.prefix(1))
        for url in selected {
            guard allowedContentTypes.isEmpty || allowedContentTypes.contains(where: { $0.quillAccepts(url: url) }) else {
                return .failure(QuillCompatibilityError.unsupportedFileSelection(url, allowedContentTypes))
            }
        }
        return .success(selected)
    }

    private static func run(command: [String]) -> [URL]? {
        guard let executable = command.first,
              let executableURL = executableURL(named: executable) else {
            return nil
        }

        let process = Process()
        let pipe = Pipe()
        process.executableURL = executableURL
        process.arguments = Array(command.dropFirst())
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let paths = output
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.isEmpty }
        guard !paths.isEmpty else { return nil }
        return paths.map(URL.init(fileURLWithPath:))
    }

    private static func executableURL(named name: String) -> URL? {
        let paths = (ProcessInfo.processInfo.environment["PATH"] ?? "/usr/local/bin:/usr/bin:/bin")
            .split(separator: ":")
            .map(String.init)
        for path in paths {
            let candidate = URL(fileURLWithPath: path).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }
}

public extension View {
    func fileImporter(
        isPresented: Binding<Bool>,
        allowedContentTypes: [UTType],
        onCompletion: @escaping (Result<URL, Error>) -> Void
    ) -> InitialOnChangeView<Self, Bool> {
        onChange(of: isPresented.wrappedValue, initial: true) { presented in
            guard presented else { return }
            isPresented.wrappedValue = false
            onCompletion(QuillFileImporter.selectURL(allowedContentTypes: allowedContentTypes))
        }
    }

    func fileImporter(
        isPresented: Binding<Bool>,
        allowedContentTypes: [UTType],
        allowsMultipleSelection: Bool = false,
        onCompletion: @escaping (Result<[URL], Error>) -> Void
    ) -> InitialOnChangeView<Self, Bool> {
        onChange(of: isPresented.wrappedValue, initial: true) { presented in
            guard presented else { return }
            isPresented.wrappedValue = false
            onCompletion(
                QuillFileImporter.selectURLs(
                    allowedContentTypes: allowedContentTypes,
                    allowsMultipleSelection: allowsMultipleSelection
                )
            )
        }
    }
}

private extension UTType {
    func quillAccepts(url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension)?.conforms(to: self) == true
    }
}
#endif
