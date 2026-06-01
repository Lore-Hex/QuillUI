import Foundation
import QuillFoundation
import QuillUI

/// Quill CodeEdit fixtures-only IDE shell.
///
/// Upstream `CodeEditApp/CodeEdit` is a SwiftUI/AppKit macOS
/// IDE built on `CodeEditSourceEditor` (NSTextView-backed),
/// Sparkle, and a stack of CodeEditApp SPM packages.
/// `CodeEditSymbols` ships a SwiftLintPlugin prebuild command
/// that SwiftPM 6 rejects, so the vendored `CodeEditUpstream`
/// target stays opt-in.
///
/// This shell reproduces the IDE shape without the upstream
/// dependencies: a file-tree sidebar of project files, a tab
/// bar of currently-open files, and a plain `Text` viewer for
/// the selected file's contents. Files are seeded from a fixed
/// in-memory project so the layout compiles + renders without
/// needing real filesystem reads.
@MainActor
public struct QuillCodeEditContentView: View {
    @State private var openTabs: [ProjectFile.ID]
    @State private var activeID: ProjectFile.ID?
    @State private var project: Project

    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        let project = QuillCodeEditFixtures.project
        let selectedID = QuillCodeEditInitialSelection.selectedFileID(
            in: project.files,
            environment: environment
        )
        _project = State(initialValue: project)
        _openTabs = State(initialValue: selectedID.map { [$0] } ?? [])
        _activeID = State(initialValue: selectedID)
    }

    nonisolated public var body: some View {
        QuillMainActorView.assumeIsolated {
            HStack(spacing: 0) {
                fileTree
                    .frame(width: 240)
                    .frame(maxHeight: .infinity, alignment: .topLeading)
                Divider()
                editorPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(QuillDesktopChromeStyle.detailBackground)
        }
    }

    private var fileTree: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(project.name).font(.headline).padding(14)

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(project.files) { file in
                        fileTreeRow(file)
                            .onTapGesture {
                                open(file)
                            }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 18)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(QuillDesktopChromeStyle.sidebarBackground)
    }

    private func fileTreeRow(_ file: ProjectFile) -> some View {
        HStack(spacing: 6) {
            Image(systemName: QuillSystemSymbol.compatibleName(file.sidebarSystemImageName))
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundColor(.secondary)
                .frame(width: 14, height: 14, alignment: .center)
            Text(file.name).font(.caption)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(height: 74, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(activeID == file.id ? QuillDesktopChromeStyle.selectedRowBackground : Color.clear)
        .cornerRadius(QuillDesktopChromeStyle.selectedRowCornerRadius)
        .contentShape(Rectangle())
    }

    private var editorPane: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()
            content
        }
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(openTabs, id: \.self) { id in
                if let file = project.files.first(where: { $0.id == id }) {
                    Button {
                        activeID = file.id
                    } label: {
                        HStack(spacing: 4) {
                            Text(file.name).font(.caption)
                            Button("×") { close(file) }
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            activeID == file.id
                                ? QuillDesktopChromeStyle.selectedRowBackground
                                : Color.clear
                        )
                        .cornerRadius(QuillDesktopChromeStyle.selectedRowCornerRadius)
                    }
                }
            }
            Spacer()
        }
        .background(Color.gray.opacity(0.06))
    }

    private var content: some View {
        Group {
            if let id = activeID, activeFile != nil {
                TextEditor(text: contentsBinding(for: id))
                    .font(.system(size: 13, design: .monospaced))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(14)
                    .background(QuillDesktopChromeStyle.detailBackground)
            } else {
                VStack(spacing: 8) {
                    Text("Quill CodeEdit").font(.title2)
                    Text("Pick a file from the sidebar to open it in a tab.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(QuillDesktopChromeStyle.detailBackground)
            }
        }
    }

    /// Binding into `project.files[idx].contents` so the
    /// TextEditor's edits flow back to the project model
    /// instead of being lost on the next view rebuild. Returns
    /// an empty-string binding for unknown ids (the call site
    /// only reaches this when `activeFile != nil` anyway).
    private func contentsBinding(for fileID: ProjectFile.ID) -> Binding<String> {
        Binding(
            get: { project.files.first(where: { $0.id == fileID })?.contents ?? "" },
            set: { newValue in
                if let idx = project.files.firstIndex(where: { $0.id == fileID }) {
                    project.files[idx].contents = newValue
                }
            }
        )
    }

    private func open(_ file: ProjectFile) {
        if !openTabs.contains(file.id) {
            openTabs.append(file.id)
        }
        activeID = file.id
    }

    private func close(_ file: ProjectFile) {
        openTabs.removeAll(where: { $0 == file.id })
        if activeID == file.id {
            activeID = openTabs.last
        }
    }

    private var activeFile: ProjectFile? {
        guard let id = activeID else { return nil }
        return project.files.first(where: { $0.id == id })
    }
}

// MARK: - Fixture model

public struct ProjectFile: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var contents: String

    public var `extension`: String {
        guard let dot = name.lastIndex(of: ".") else { return "" }
        return String(name[name.index(after: dot)...])
    }

    var sidebarSystemImageName: String {
        switch self.extension.lowercased() {
        case "swift", "json":
            return "curlybraces"
        case "md", "markdown":
            return "doc.text"
        case "swiftformat", "yaml", "yml":
            return "gearshape"
        default:
            return "doc.text"
        }
    }

    public init(id: UUID = UUID(), name: String, contents: String) {
        self.id = id
        self.name = name
        self.contents = contents
    }
}

public struct Project: Sendable {
    public var name: String
    public var files: [ProjectFile]
}

public enum QuillCodeEditInitialSelection {
    public static let selectedFileIndexEnvironmentKey = "QUILLUI_CODEEDIT_SELECTED_FILE_INDEX_ON_START"

    public static func selectedFileID(
        in files: [ProjectFile],
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> ProjectFile.ID? {
        QuillInitialSelection.selectedID(
            in: files,
            environmentKeys: [selectedFileIndexEnvironmentKey],
            environment: environment
        )
    }
}

public enum QuillCodeEditFixtures {
    public static let project: Project = Project(
        name: "QuillSample",
        files: [
            ProjectFile(name: "README.md", contents: """
            # QuillSample

            A small example project shown inside Quill CodeEdit's
            fixtures-only IDE shell. The file tree on the left
            lists every member of this project; clicking a row
            opens it in a tab.
            """),
            ProjectFile(name: "main.swift", contents: """
            import Foundation

            print("Hello from QuillSample")
            """),
            ProjectFile(name: "Package.swift", contents: """
            // swift-tools-version: 6.0
            import PackageDescription

            let package = Package(
                name: "QuillSample",
                targets: [
                    .executableTarget(name: "QuillSample"),
                ]
            )
            """),
            ProjectFile(name: ".swiftformat", contents: """
            --indent 4
            --maxwidth 100
            """),
        ]
    )
}
