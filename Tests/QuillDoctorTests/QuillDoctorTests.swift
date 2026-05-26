import Foundation
import Testing
@testable import QuillDoctor

@Suite("quill-doctor coverage scan")
struct QuillDoctorTests {
    @Test("imports cross-referenced against coverage doc produce covered/missing statuses")
    func coveredAndMissingStatuses() throws {
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory
            .appendingPathComponent("QuillDoctorTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: scratch) }

        let project = scratch.appendingPathComponent("Project", isDirectory: true)
        let sources = project.appendingPathComponent("Sources", isDirectory: true)
        try fm.createDirectory(at: sources, withIntermediateDirectories: true)

        try """
        import SwiftUI
        import Combine
        import SomeMadeUpFramework

        struct Foo {}
        """.write(to: sources.appendingPathComponent("App.swift"), atomically: true, encoding: .utf8)

        try """
        import Foundation
        import AnotherMissingThing

        struct Bar {}
        """.write(to: sources.appendingPathComponent("Bar.swift"), atomically: true, encoding: .utf8)

        let coverageDoc = scratch.appendingPathComponent("coverage.md")
        try """
        # Coverage

        ## SwiftUI
        Some rows here.

        ## Combine
        More rows.

        ## Foundation
        ...

        ## PhotosUI and Photos
        ...

        ## Re-export-only Apple shims
        Meta section, not a module.
        """.write(to: coverageDoc, atomically: true, encoding: .utf8)

        let report = try QuillDoctor().scan(
            projectRoot: project,
            coverageDocPath: coverageDoc
        )

        let coveredModules = report.modules.filter { $0.status == .covered }.map(\.module)
        let missingModules = report.modules.filter { $0.status == .missing }.map(\.module)

        #expect(Set(coveredModules) == Set(["SwiftUI", "Combine", "Foundation"]))
        #expect(Set(missingModules) == Set(["SomeMadeUpFramework", "AnotherMissingThing"]))
        #expect(report.hasMissing)
        #expect(report.coveredCount == 3)
        #expect(report.missingCount == 2)
    }

    @Test("PhotosUI and Photos heading registers both submodules as covered")
    func combinedHeadingHandled() throws {
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory
            .appendingPathComponent("QuillDoctorTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: scratch) }

        let project = scratch.appendingPathComponent("Project", isDirectory: true)
        try fm.createDirectory(at: project, withIntermediateDirectories: true)
        try """
        import PhotosUI
        import Photos
        """.write(to: project.appendingPathComponent("F.swift"), atomically: true, encoding: .utf8)

        let coverageDoc = scratch.appendingPathComponent("coverage.md")
        try """
        ## PhotosUI and Photos
        Combined section.
        """.write(to: coverageDoc, atomically: true, encoding: .utf8)

        let report = try QuillDoctor().scan(projectRoot: project, coverageDocPath: coverageDoc)
        let coveredModules = Set(report.modules.filter { $0.status == .covered }.map(\.module))
        #expect(coveredModules == Set(["PhotosUI", "Photos"]))
        #expect(!report.hasMissing)
    }

    @Test("formattedReport prints MISSING block with usage locations")
    func formattedReportShape() throws {
        let report = QuillDoctorReport(modules: [
            .init(module: "MissingFramework", status: .missing, usedInFiles: ["A.swift", "B.swift"]),
            .init(module: "SwiftUI", status: .covered, usedInFiles: ["C.swift"])
        ])
        let formatted = report.formattedReport()
        #expect(formatted.contains("MISSING (1)"))
        #expect(formatted.contains("MissingFramework"))
        #expect(formatted.contains("A.swift, B.swift"))
        #expect(formatted.contains("COVERED (1)"))
        #expect(formatted.contains("SwiftUI"))
        #expect(formatted.contains("Summary: 1 covered, 1 missing"))
    }

    @Test("ticketMarkdown emits one acceptance-criteria checklist per missing module")
    func ticketMarkdownShape() throws {
        let report = QuillDoctorReport(modules: [
            .init(module: "FrameworkA", status: .missing, usedInFiles: ["A.swift"]),
            .init(module: "FrameworkB", status: .missing, usedInFiles: ["B.swift"]),
            .init(module: "SwiftUI", status: .covered, usedInFiles: ["C.swift"])
        ])
        let tickets = report.ticketMarkdown()
        #expect(tickets.contains("# QuillUI coverage tickets"))
        #expect(tickets.contains("## Add coverage for `FrameworkA`"))
        #expect(tickets.contains("## Add coverage for `FrameworkB`"))
        #expect(!tickets.contains("## Add coverage for `SwiftUI`"))
        #expect(tickets.contains("**Acceptance criteria:**"))
        #expect(tickets.contains("- [ ] `## FrameworkA`"))
    }

    @Test("ticketMarkdown returns a no-tickets placeholder when nothing is missing")
    func ticketMarkdownNoMissing() throws {
        let report = QuillDoctorReport(modules: [
            .init(module: "SwiftUI", status: .covered, usedInFiles: ["C.swift"])
        ])
        let tickets = report.ticketMarkdown()
        #expect(tickets.contains("No tickets to generate"))
    }
}
