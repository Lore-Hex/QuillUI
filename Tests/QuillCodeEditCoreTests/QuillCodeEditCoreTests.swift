import Foundation
import Testing
@testable import QuillCodeEditCore

@Suite("QuillCodeEditCore fixture model")
struct QuillCodeEditCoreTests {

    // MARK: - ProjectFile.extension

    @Test("ProjectFile.extension returns the segment after the last dot")
    func extensionAfterLastDot() {
        #expect(ProjectFile(name: "main.swift", contents: "").extension == "swift")
        #expect(ProjectFile(name: "README.md", contents: "").extension == "md")
        #expect(ProjectFile(name: "Package.json", contents: "").extension == "json")
    }

    @Test("ProjectFile.extension returns the empty string when there's no dot")
    func extensionEmptyWhenNoDot() {
        #expect(ProjectFile(name: "Makefile", contents: "").extension == "")
        #expect(ProjectFile(name: "LICENSE", contents: "").extension == "")
    }

    @Test("ProjectFile.extension uses the LAST dot for multi-dotted names")
    func extensionUsesLastDot() {
        #expect(ProjectFile(name: "archive.tar.gz", contents: "").extension == "gz")
        #expect(ProjectFile(name: "foo.bar.baz", contents: "").extension == "baz")
    }

    @Test("ProjectFile.extension treats a leading dot as the only dot — dotfiles")
    func extensionLeadingDot() {
        // `.swiftformat` is in the fixture project and is treated
        // as a config-like file by the sidebar icon selector.
        #expect(ProjectFile(name: ".swiftformat", contents: "").extension == "swiftformat")
        #expect(ProjectFile(name: ".gitignore", contents: "").extension == "gitignore")
    }

    @Test("ProjectFile.extension is empty for a name that ends in a dot")
    func extensionTrailingDot() {
        // `lastIndex(of:)` finds the trailing dot; the slice
        // after it is empty.
        #expect(ProjectFile(name: "foo.", contents: "").extension == "")
    }

    // MARK: - ProjectFile.id

    @Test("ProjectFile generates a fresh UUID by default")
    func projectFileGeneratesUniqueIDs() {
        let a = ProjectFile(name: "a.swift", contents: "")
        let b = ProjectFile(name: "a.swift", contents: "")
        #expect(a.id != b.id)
    }

    // MARK: - QuillSample fixture project

    @Test("Fixture project carries the four files listed in app-targets.md")
    func fixtureProjectShape() {
        let project = QuillCodeEditFixtures.project
        #expect(project.name == "QuillSample")
        let names = project.files.map(\.name).sorted()
        #expect(names == [".swiftformat", "Package.swift", "README.md", "main.swift"])
    }

    @Test("Fixture file extensions map to the icons the sidebar uses")
    func fixtureFileExtensions() {
        let exts = Dictionary(uniqueKeysWithValues:
            QuillCodeEditFixtures.project.files.map { ($0.name, $0.extension) }
        )
        #expect(exts["main.swift"] == "swift")
        #expect(exts["README.md"] == "md")
        #expect(exts["Package.swift"] == "swift")
        #expect(exts[".swiftformat"] == "swiftformat")
    }

    @Test("Sidebar file icons use SF symbols instead of emoji text glyphs")
    func sidebarFileIconsUseMappedSystemSymbols() {
        #expect(ProjectFile(name: "main.swift", contents: "").sidebarSystemImageName == "curlybraces")
        #expect(ProjectFile(name: "README.md", contents: "").sidebarSystemImageName == "doc.text")
        #expect(ProjectFile(name: "Package.json", contents: "").sidebarSystemImageName == "curlybraces")
        #expect(ProjectFile(name: ".swiftformat", contents: "").sidebarSystemImageName == "gearshape")
        #expect(ProjectFile(name: "config.yaml", contents: "").sidebarSystemImageName == "gearshape")
        #expect(ProjectFile(name: "LICENSE", contents: "").sidebarSystemImageName == "doc.text")

        for file in QuillCodeEditFixtures.project.files {
            let iconName = file.sidebarSystemImageName
            let isASCIIOnly = iconName.unicodeScalars.allSatisfy { $0.isASCII }
            #expect(isASCIIOnly, "\(file.name) uses non-ASCII icon text: \(iconName)")
        }
    }

    @Test("Every fixture file ships non-empty contents — no placeholders")
    func fixtureFilesHaveContents() {
        for file in QuillCodeEditFixtures.project.files {
            #expect(!file.contents.isEmpty, "\(file.name) has empty contents")
        }
    }

    @Test("Fixture file IDs are all unique within the project")
    func fixtureFileIDsUnique() {
        let project = QuillCodeEditFixtures.project
        let ids = project.files.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("Initial file selection reads the shared backend env key")
    func initialFileSelectionReadsEnvironment() {
        let files = QuillCodeEditFixtures.project.files

        #expect(QuillCodeEditInitialSelection.selectedFileIndexEnvironmentKey == "QUILLUI_CODEEDIT_SELECTED_FILE_INDEX_ON_START")
        #expect(
            QuillCodeEditInitialSelection.selectedFileID(
                in: files,
                environment: ["QUILLUI_CODEEDIT_SELECTED_FILE_INDEX_ON_START": "1"]
            ) == files[1].id
        )
        #expect(
            QuillCodeEditInitialSelection.selectedFileID(
                in: files,
                environment: ["QUILLUI_CODEEDIT_SELECTED_FILE_INDEX_ON_START": "-1"]
            ) == files.first?.id
        )
    }
}
