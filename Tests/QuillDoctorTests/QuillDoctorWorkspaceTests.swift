import Foundation
import Testing
@testable import QuillDoctor

@Suite("quill-doctor workspace scan", .serialized)
struct QuillDoctorWorkspaceTests {
    @Test("scanWorkspace finds multiple packages and reports them separately")
    func multiPackageWorkspace() throws {
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory
            .appendingPathComponent("QuillDoctorWorkspaceTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: scratch) }

        let workspace = scratch.appendingPathComponent("Workspace", isDirectory: true)
        
        // Package A
        let pkgA = workspace.appendingPathComponent("PackageA", isDirectory: true)
        try fm.createDirectory(at: pkgA.appendingPathComponent("Sources"), withIntermediateDirectories: true)
        try "import SwiftUI".write(to: pkgA.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        try "import SwiftUI".write(to: pkgA.appendingPathComponent("Sources/A.swift"), atomically: true, encoding: .utf8)

        // Package B
        let pkgB = workspace.appendingPathComponent("PackageB", isDirectory: true)
        try fm.createDirectory(at: pkgB.appendingPathComponent("Sources"), withIntermediateDirectories: true)
        try "import Combine".write(to: pkgB.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        try "import MissingModule".write(to: pkgB.appendingPathComponent("Sources/B.swift"), atomically: true, encoding: .utf8)

        // Non-package dir
        let other = workspace.appendingPathComponent("Other", isDirectory: true)
        try fm.createDirectory(at: other, withIntermediateDirectories: true)
        try "import Something".write(to: other.appendingPathComponent("Random.swift"), atomically: true, encoding: .utf8)

        let coverageDoc = scratch.appendingPathComponent("coverage.md")
        try """
        ## SwiftUI
        ## Combine
        """.write(to: coverageDoc, atomically: true, encoding: .utf8)

        let report = try QuillDoctor().scanWorkspace(
            workspaceRoot: workspace,
            coverageDocPath: coverageDoc
        )

        #expect(report.packages.count == 2)
        #expect(report.packages.map(\.packageName).sorted() == ["PackageA", "PackageB"])
        
        let reportA = report.packages.first { $0.packageName == "PackageA" }?.report
        #expect(reportA?.missingCount == 0)
        #expect(reportA?.coveredCount == 1)

        let reportB = report.packages.first { $0.packageName == "PackageB" }?.report
        #expect(reportB?.missingCount == 1)
        #expect(reportB?.coveredCount == 1)
        
        #expect(report.hasMissing)
        
        let formatted = report.formattedReport()
        #expect(formatted.contains("## PackageA"))
        #expect(formatted.contains("## PackageB"))
        #expect(formatted.contains("MissingModule"))
        #expect(!formatted.contains("Random.swift")) // Should only scan inside packages
    }

    @Test("scanWorkspace skips ignored directories")
    func skipsIgnoredDirs() throws {
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory
            .appendingPathComponent("QuillDoctorWorkspaceTests-Ignored-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: scratch) }

        let workspace = scratch.appendingPathComponent("Workspace", isDirectory: true)
        
        let pkg = workspace.appendingPathComponent("RealPackage", isDirectory: true)
        try fm.createDirectory(at: pkg.appendingPathComponent("Sources"), withIntermediateDirectories: true)
        try "".write(to: pkg.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        try "import SwiftUI".write(to: pkg.appendingPathComponent("Sources/A.swift"), atomically: true, encoding: .utf8)

        for ignored in [".build", "node_modules", "Pods"] {
            let ignoredDir = workspace.appendingPathComponent(ignored, isDirectory: true)
            try fm.createDirectory(at: ignoredDir, withIntermediateDirectories: true)
            try "".write(to: ignoredDir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        }

        let coverageDoc = scratch.appendingPathComponent("coverage.md")
        try "## SwiftUI".write(to: coverageDoc, atomically: true, encoding: .utf8)

        let report = try QuillDoctor().scanWorkspace(
            workspaceRoot: workspace,
            coverageDocPath: coverageDoc
        )

        #expect(report.packages.count == 1)
        #expect(report.packages[0].packageName == "RealPackage")
    }

    @Test("scanWorkspace returns empty when no packages found")
    func emptyWorkspace() throws {
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory
            .appendingPathComponent("QuillDoctorWorkspaceTests-Empty-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: scratch) }

        let workspace = scratch.appendingPathComponent("Workspace", isDirectory: true)
        try fm.createDirectory(at: workspace, withIntermediateDirectories: true)
        try "import SwiftUI".write(to: workspace.appendingPathComponent("A.swift"), atomically: true, encoding: .utf8)

        let coverageDoc = scratch.appendingPathComponent("coverage.md")
        try "## SwiftUI".write(to: coverageDoc, atomically: true, encoding: .utf8)

        let report = try QuillDoctor().scanWorkspace(
            workspaceRoot: workspace,
            coverageDocPath: coverageDoc
        )

        #expect(report.packages.isEmpty)
    }
}
