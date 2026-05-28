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

    @Test("--target scans only the selected SwiftPM target path")
    func targetNameScansOnlySelectedSwiftPMTarget() throws {
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory
            .appendingPathComponent("QuillDoctorTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: scratch) }

        let project = try makeSwiftPackageFixture(in: scratch)
        let coverageDoc = try writeCoverageDoc(in: scratch, coveredModules: ["SwiftUI"])

        let report = try QuillDoctor().scan(
            projectRoot: project,
            coverageDocPath: coverageDoc,
            targetName: "AppTarget"
        )

        let modules = Set(report.modules.map(\.module))
        #expect(modules == Set(["SwiftUI"]))
        #expect(!modules.contains("MissingOtherKit"))
        #expect(!report.hasMissing)

        let swiftUI = try #require(report.modules.first { $0.module == "SwiftUI" })
        #expect(swiftUI.usedInFiles == ["Sources/AppTarget/App.swift"])
    }

    @Test("--target reports available SwiftPM targets when the name is invalid")
    func invalidTargetReportsAvailableTargets() throws {
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory
            .appendingPathComponent("QuillDoctorTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: scratch) }

        let project = try makeSwiftPackageFixture(in: scratch)
        let coverageDoc = try writeCoverageDoc(in: scratch, coveredModules: ["SwiftUI"])

        do {
            _ = try QuillDoctor().scan(
                projectRoot: project,
                coverageDocPath: coverageDoc,
                targetName: "MissingTarget"
            )
            Issue.record("Expected targetNotFound")
        } catch let error as QuillDoctorTargetResolutionError {
            guard case .targetNotFound(let name, let availableTargets) = error else {
                Issue.record("Expected targetNotFound, got \(error)")
                return
            }
            #expect(name == "MissingTarget")
            #expect(availableTargets == ["AppTarget", "OtherTarget"])
            #expect(error.description.contains("Available targets:"))
            #expect(error.description.contains("  - AppTarget"))
            #expect(error.description.contains("  - OtherTarget"))
        } catch {
            Issue.record("Expected QuillDoctorTargetResolutionError, got \(error)")
        }
    }

    @Test("--target errors clearly when the project root is not a SwiftPM package")
    func targetNameRequiresSwiftPMPackage() throws {
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory
            .appendingPathComponent("QuillDoctorTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: scratch) }

        let project = scratch.appendingPathComponent("NotAPackage", isDirectory: true)
        try fm.createDirectory(at: project, withIntermediateDirectories: true)
        try """
        import SwiftUI
        """.write(to: project.appendingPathComponent("App.swift"), atomically: true, encoding: .utf8)
        let coverageDoc = try writeCoverageDoc(in: scratch, coveredModules: ["SwiftUI"])

        do {
            _ = try QuillDoctor().scan(
                projectRoot: project,
                coverageDocPath: coverageDoc,
                targetName: "AppTarget"
            )
            Issue.record("Expected packageManifestMissing")
        } catch let error as QuillDoctorTargetResolutionError {
            guard case .packageManifestMissing(let projectRoot) = error else {
                Issue.record("Expected packageManifestMissing, got \(error)")
                return
            }
            #expect(projectRoot == project.resolvingSymlinksInPath().path)
            #expect(error.description.contains("--target requires PROJECT_ROOT to be a SwiftPM package"))
        } catch {
            Issue.record("Expected QuillDoctorTargetResolutionError, got \(error)")
        }
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
        let tickets = try report.ticketMarkdown()
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
        let tickets = try report.ticketMarkdown()
        #expect(tickets.contains("No tickets to generate"))
    }

    @Test("JSON encoding matches required schema and sorts modules alphabetically")
    func jsonEncoding() throws {
        let report = QuillDoctorReport(modules: [
            .init(module: "B_Module", status: .covered, usedInFiles: ["B.swift"]),
            .init(module: "A_Module", status: .missing, usedInFiles: ["A.swift"])
        ])

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys] // For stable testing
        let data = try encoder.encode(report)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(json["covered_count"] as? Int == 1)
        #expect(json["missing_count"] as? Int == 1)

        let modules = try #require(json["modules"] as? [[String: Any]])
        #expect(modules.count == 2)

        // Verify alphabetical sort (A_Module before B_Module)
        #expect(modules[0]["name"] as? String == "A_Module")
        #expect(modules[0]["status"] as? String == "missing")
        #expect(modules[0]["used_in_files"] as? [String] == ["A.swift"])

        #expect(modules[1]["name"] as? String == "B_Module")
        #expect(modules[1]["status"] as? String == "covered")
        #expect(modules[1]["used_in_files"] as? [String] == ["B.swift"])
    }

    @Test("JSON encoding handles empty report")
    func jsonEncodingEmpty() throws {
        let report = QuillDoctorReport(modules: [])
        let encoder = JSONEncoder()
        let data = try encoder.encode(report)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(json["covered_count"] as? Int == 0)
        #expect(json["missing_count"] as? Int == 0)
        #expect((json["modules"] as? [Any])?.isEmpty == true)
    }

    private func makeSwiftPackageFixture(in scratch: URL) throws -> URL {
        let fm = FileManager.default
        let project = scratch.appendingPathComponent("PackageProject", isDirectory: true)
        try fm.createDirectory(
            at: project.appendingPathComponent("Sources/AppTarget", isDirectory: true),
            withIntermediateDirectories: true
        )
        try fm.createDirectory(
            at: project.appendingPathComponent("Sources/OtherTarget", isDirectory: true),
            withIntermediateDirectories: true
        )

        try """
        // swift-tools-version: 6.0
        import PackageDescription

        let package = Package(
            name: "DoctorFixture",
            products: [],
            targets: [
                .target(name: "AppTarget", path: "Sources/AppTarget"),
                .target(name: "OtherTarget", path: "Sources/OtherTarget")
            ]
        )
        """.write(to: project.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)

        try """
        import SwiftUI

        public struct App {}
        """.write(
            to: project.appendingPathComponent("Sources/AppTarget/App.swift"),
            atomically: true,
            encoding: .utf8
        )

        try """
        import MissingOtherKit

        public struct Other {}
        """.write(
            to: project.appendingPathComponent("Sources/OtherTarget/Other.swift"),
            atomically: true,
            encoding: .utf8
        )

        return project
    }

    private func writeCoverageDoc(in scratch: URL, coveredModules: [String]) throws -> URL {
        let coverageDoc = scratch.appendingPathComponent("coverage.md")
        let headings = coveredModules.map { "## \($0)\nCovered." }.joined(separator: "\n\n")
        try headings.write(to: coverageDoc, atomically: true, encoding: .utf8)
        return coverageDoc
    }
}
