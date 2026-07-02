import Foundation
import SwiftParser
import SwiftSyntax
import SwiftSyntaxBuilder

/// Lowers SwiftUI-only Swift syntax into Linux-compatible Swift.
///
/// Mirrors most of the regex transformations in
/// `scripts/lower-swiftui-source-for-linux.sh`. Currently covers:
///
///   * `@main` attribute removal from any declaration
///   * Objective-C-only attribute removal (`@objc`, `@IBAction`, etc.)
///   * `#selector(x)` → `Selector("x")` for Linux builds without ObjC interop
///   * `@Observable` class lowering to `QuillObservableObject` inheritance
///     with `@QuillPublished` wrapping for eligible stored properties
///   * `Sendable` removal from inheritance lists whenever `View` is also
///     present (so `struct Foo: View, Sendable` → `struct Foo: View`)
///   * `#Preview { … }` top-level declaration deletion (any `#Preview` macro
///     expansion at file scope is removed entirely)
///   * `os(macOS)` widening to `(os(macOS) || os(Linux))` inside `#if`
///     condition expression trees, with carve-outs for negated forms (`!os(macOS)`)
///     and already-widened forms (`os(macOS) || os(Linux)`)
///
/// Out of scope for this implementation (still handled by the shell script):
///   * `#Preview` blocks wrapped in `#if … #endif` whose `#endif` is the
///     end-of-file marker. Top-level `#Preview` is deleted but the `#if`
///     wrapper is not collapsed.
public struct SwiftUILowering {
    /// Opt-in lowering passes that are *not* safe for every app and must be
    /// enabled per profile. Off by default so apps that keep real Swift
    /// concurrency (Signal / Telegram) are never affected.
    public struct Options: Sendable, Equatable {
        /// When `true`, run ``ActorIsolationLowering`` after the always-on
        /// SwiftUI passes: `actor` -> `final class`, `nonisolated` removal, and
        /// `await` stripping on intra-type calls. Only headless single-threaded
        /// profiles (e.g. Enchanted / Quill Chat on the generic GTK backend)
        /// should turn this on.
        public var stripActorIsolation: Bool

        public init(stripActorIsolation: Bool = false) {
            self.stripActorIsolation = stripActorIsolation
        }

        /// The conservative, app-agnostic default: only the always-on passes.
        public static let `default` = Options()
    }

    public let options: Options

    public init(options: Options = .default) {
        self.options = options
    }

    /// Lowers a single Swift source string in memory.
    public func lower(_ source: String) -> String {
        let sourceWithoutPreviews = Self.removeTopLevelPreviewMacroBlocks(source)
        let tree = Parser.parse(source: sourceWithoutPreviews)
        let rewriter = SwiftUIRewriter()
        let rewritten = rewriter.rewrite(tree)
        let foundational = FoundationLowering().lower(rewritten.description)
        let normalizedImports = Self.normalizeLinuxShimSubmoduleImports(foundational)
        let withoutOrphanedAttributes = Self.removeTrailingOrphanedAvailabilityAttributes(normalizedImports)
        let qualifiedFoundationNetworkingTypes = Self.qualifyFoundationNetworkingConstructorCalls(withoutOrphanedAttributes)
        let exposedFoundationNetworkingAsync = Self.exposeFoundationNetworkingAsyncURLSessionRequirements(qualifiedFoundationNetworkingTypes)
        let loweredPOSIXBufferSizes = Self.lowerPOSIXBufferSizes(exposedFoundationNetworkingAsync)
        let loweredAxisEdgeSwitches = Self.lowerAxisEdgeSwitchExhaustiveness(loweredPOSIXBufferSizes)
        let normalizedFontManagerCalls = Self.normalizeNSFontManagerPropertyCalls(loweredAxisEdgeSwitches)
        let annotatedFontFamilies = Self.annotateNSFontManagerFontFamilies(normalizedFontManagerCalls)
        let disambiguatedFontFamilyFilters = Self.disambiguateNSFontManagerFontFamilyFilters(annotatedFontFamilies)
        let loweredProjectedCollectionChecks = Self.lowerProjectedCollectionChecks(disambiguatedFontFamilyFilters)
        let loweredAttributedStringColors = Self.lowerAttributedStringForegroundColorAssignments(loweredProjectedCollectionChecks)
        let annotatedDecoderContinuations = Self.annotateJSONDecoderDataContinuations(loweredAttributedStringColors)
        let loweredPublisherPipelines = CombinePublisherPipelineComplexityLowering().lower(annotatedDecoderContinuations)
        let bodyLowered = SwiftUIBodyComplexityLowering().lower(loweredPublisherPipelines)
        if options.stripActorIsolation {
            return ActorIsolationLowering().lower(bodyLowered)
        }
        return bodyLowered
    }

    /// Lowers every `.swift` file under `sourceDir` *in place*. Files whose
    /// lowered content equals the input are not rewritten, so file mtimes
    /// don't churn when a pass is a no-op. Returns the number of `.swift`
    /// files visited (whether or not they were rewritten).
    @discardableResult
    public func lowerInPlace(
        sourceDir: URL,
        fileManager: FileManager = .default
    ) throws -> Int {
        let normalizedSource = sourceDir.resolvingSymlinksInPath()

        guard let enumerator = fileManager.enumerator(
            at: normalizedSource,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var count = 0
        for case let fileURL as URL in enumerator {
            let resolved = fileURL.resolvingSymlinksInPath()
            let resourceValues = try resolved.resourceValues(forKeys: [.isRegularFileKey])
            guard resourceValues.isRegularFile == true else { continue }
            guard resolved.pathExtension == "swift" else { continue }

            let original = try String(contentsOf: resolved, encoding: .utf8)
            let lowered = lower(original)
            if lowered != original {
                try lowered.write(to: resolved, atomically: true, encoding: .utf8)
            }
            count += 1
        }
        return count
    }

    private static func removeTrailingOrphanedAvailabilityAttributes(_ source: String) -> String {
        var lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        while let lastNonEmptyIndex = lines.indices.reversed().first(where: {
            !lines[$0].trimmingCharacters(in: .whitespaces).isEmpty
        }) {
            let trimmed = lines[lastNonEmptyIndex].trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("@available("), trimmed.hasSuffix(")") else { break }
            lines.removeSubrange(lastNonEmptyIndex..<lines.endIndex)
        }
        return lines.joined(separator: "\n")
    }

    private static func removeTopLevelPreviewMacroBlocks(_ source: String) -> String {
        guard source.contains("#Preview") else { return source }

        func lineStart(before index: String.Index, in text: String) -> String.Index {
            text[..<index].lastIndex(of: "\n").map { text.index(after: $0) } ?? text.startIndex
        }

        func previousLineRange(before index: String.Index, in text: String) -> Range<String.Index>? {
            guard index > text.startIndex else { return nil }
            let previousEnd = text.index(before: index)
            let previousStart = text[..<previousEnd].lastIndex(of: "\n").map {
                text.index(after: $0)
            } ?? text.startIndex
            return previousStart..<previousEnd
        }

        var lowered = source
        var searchStart = lowered.startIndex
        while let previewRange = lowered.range(of: "#Preview", range: searchStart..<lowered.endIndex) {
            let previewLineStart = lineStart(before: previewRange.lowerBound, in: lowered)
            let linePrefix = lowered[previewLineStart..<previewRange.lowerBound]
                .trimmingCharacters(in: .whitespaces)
            guard linePrefix.isEmpty else {
                searchStart = previewRange.upperBound
                continue
            }

            guard let openBrace = lowered[previewRange.upperBound..<lowered.endIndex].firstIndex(of: "{"),
                  let closeBrace = matchingClosingBrace(in: lowered, open: openBrace)
            else {
                searchStart = previewRange.upperBound
                continue
            }

            var removalStart = previewLineStart
            while let previousLine = previousLineRange(before: removalStart, in: lowered) {
                let trimmed = lowered[previousLine].trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("@available(") else { break }
                removalStart = previousLine.lowerBound
            }

            let removalEnd = lowered.index(after: closeBrace)
            let extendedRemovalEnd: String.Index
            if removalEnd < lowered.endIndex, lowered[removalEnd] == "\n" {
                extendedRemovalEnd = lowered.index(after: removalEnd)
            } else {
                extendedRemovalEnd = removalEnd
            }
            lowered.removeSubrange(removalStart..<extendedRemovalEnd)
            searchStart = removalStart
        }
        return lowered
    }

    private static func normalizeLinuxShimSubmoduleImports(_ source: String) -> String {
        let modules = [
            "AppKit",
            "Foundation",
            "IOKit",
            "os",
            "PDFKit",
            "UIKit",
        ].joined(separator: "|")
        let pattern = #"(?m)^([ \t]*(?:(?:@preconcurrency|@_exported|@_implementationOnly)[ \t]+)*)import[ \t]+(?:(?:class|struct|enum|protocol|func|var)[ \t]+)?(\#(modules))\.[A-Za-z_][A-Za-z0-9_.]*\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return source }
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        return regex.stringByReplacingMatches(
            in: source,
            range: range,
            withTemplate: "$1import $2"
        )
    }

    private static func qualifyFoundationNetworkingConstructorCalls(_ source: String) -> String {
        guard source.contains("URLRequest(") else { return source }
        let pattern = #"(^|[^A-Za-z0-9_\.])URLRequest\s*\("#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return source }
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        let qualified = regex.stringByReplacingMatches(
            in: source,
            range: range,
            withTemplate: "$1FoundationNetworking.URLRequest("
        )
        guard qualified != source, !qualified.contains("import FoundationNetworking") else {
            return qualified
        }
        return insertingImport("FoundationNetworking", into: qualified)
    }

    private static func exposeFoundationNetworkingAsyncURLSessionRequirements(_ source: String) -> String {
        guard source.contains("#if !canImport(FoundationNetworking)"),
              source.contains("URLSessionTaskDelegate"),
              source.contains("func data(")
                || source.contains("func upload(")
        else {
            return source
        }

        return source.replacingOccurrences(
            of: "#if !canImport(FoundationNetworking)",
            with: "#if true"
        )
    }

    private static func lowerPOSIXBufferSizes(_ source: String) -> String {
        guard source.contains("sysconf(_SC_GETPW_R_SIZE_MAX)") else { return source }
        var lowered = source.replacingOccurrences(
            of: "let bufsize = sysconf(_SC_GETPW_R_SIZE_MAX)",
            with: "let bufsize = Int(sysconf(Int32(_SC_GETPW_R_SIZE_MAX)))"
        )
        lowered = lowered.replacingOccurrences(
            of: "var bufsize = sysconf(_SC_GETPW_R_SIZE_MAX)",
            with: "var bufsize = Int(sysconf(Int32(_SC_GETPW_R_SIZE_MAX)))"
        )
        return lowered
    }

    private static func lowerAxisEdgeSwitchExhaustiveness(_ source: String) -> String {
        guard source.contains("switch (axis, direction)") || source.contains("switch swiftUI") else {
            return source
        }

        let tupleLowered = addDefaultCase(
            toSwitchesNamed: "switch (axis, direction)",
            in: source,
            statement: "break"
        )
        return addDefaultCase(
            toSwitchesNamed: "switch swiftUI",
            in: tupleLowered,
            requiredCaseMarkers: ["case .vertical", "case .horizontal"],
            statement: "self = .horizontal"
        )
    }

    private static func addDefaultCase(
        toSwitchesNamed switchNeedle: String,
        in source: String,
        requiredCaseMarkers: [String] = [],
        statement: String
    ) -> String {
        var lowered = source
        var searchStart = lowered.startIndex
        while let switchRange = lowered.range(of: switchNeedle, range: searchStart..<lowered.endIndex),
              let openBrace = lowered[switchRange.upperBound..<lowered.endIndex].firstIndex(of: "{"),
              let closeBrace = matchingClosingBrace(in: lowered, open: openBrace)
        {
            let switchBody = lowered[openBrace..<closeBrace]
            if switchBody.contains("default:")
                || requiredCaseMarkers.contains(where: { !switchBody.contains($0) }) {
                searchStart = lowered.index(after: closeBrace)
                continue
            }

            let lineStart = lowered[..<switchRange.lowerBound].lastIndex(of: "\n").map {
                lowered.index(after: $0)
            } ?? lowered.startIndex
            let switchIndent = lowered[lineStart..<switchRange.lowerBound]
            let caseIndent = "\(switchIndent)    "
            let statementIndent = "\(caseIndent)    "
            let insertion = "\n\(caseIndent)default:\n\(statementIndent)\(statement)\n"
            lowered.insert(contentsOf: insertion, at: closeBrace)
            searchStart = lowered.index(closeBrace, offsetBy: insertion.count, limitedBy: lowered.endIndex)
                ?? lowered.endIndex
        }
        return lowered
    }

    private static func normalizeNSFontManagerPropertyCalls(_ source: String) -> String {
        guard source.contains(".availableFontFamilies()") else { return source }
        return source.replacingOccurrences(
            of: ".availableFontFamilies()",
            with: ".availableFontFamilies"
        )
    }

    private static func annotateNSFontManagerFontFamilies(_ source: String) -> String {
        guard source.contains("NSFontManager.shared.availableFontFamilies") else { return source }
        let pattern = #"(?m)^([ \t]*)let[ \t]+([A-Za-z_][A-Za-z0-9_]*)[ \t]*=[ \t]*NSFontManager\.shared\.availableFontFamilies\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return source }
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        return regex.stringByReplacingMatches(
            in: source,
            range: range,
            withTemplate: "$1let $2: [String] = NSFontManager.shared.availableFontFamilies"
        )
    }

    private static func disambiguateNSFontManagerFontFamilyFilters(_ source: String) -> String {
        guard source.contains(": [String] = NSFontManager.shared.availableFontFamilies"),
              source.contains(".filter {") else {
            return source
        }
        let pattern = #"(?m)^([ \t]*)return[ \t]+([A-Za-z_][A-Za-z0-9_]*)\.filter[ \t]*\{"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return source }
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        return regex.stringByReplacingMatches(
            in: source,
            range: range,
            withTemplate: "$1return quillClosureFilter($2) {"
        )
    }

    private static func lowerProjectedCollectionChecks(_ source: String) -> String {
        guard source.contains("$.isEmpty") || source.contains("$") && source.contains(".isEmpty") else {
            return source
        }
        let pattern = #"\$([A-Za-z_][A-Za-z0-9_]*)\.isEmpty\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return source }
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        return regex.stringByReplacingMatches(
            in: source,
            range: range,
            withTemplate: "$1.isEmpty"
        )
    }

    private static func lowerAttributedStringForegroundColorAssignments(_ source: String) -> String {
        guard source.contains("].foregroundColor") else { return source }
        let pattern = #"(?m)^([ \t]*)([A-Za-z_][A-Za-z0-9_]*)\[([^\]\n]+)\]\.foregroundColor[ \t]*=[ \t]*(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return source }
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        return regex.stringByReplacingMatches(
            in: source,
            range: range,
            withTemplate: "$1quillSetAttributedStringForegroundColor(&$2, range: $3, color: $4)"
        )
    }

    private static func annotateJSONDecoderDataContinuations(_ source: String) -> String {
        guard source.contains("withContinuation"),
              source.contains("JSONDecoder().decode"),
              source.contains("from:") else {
            return source
        }
        let pattern = #"(?m)^([ \t]*)let[ \t]+([A-Za-z_][A-Za-z0-9_]*)[ \t]*=[ \t]*try[ \t]+await[ \t]+[^\n]*\.withContinuation\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return source }
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        let matches = regex.matches(in: source, range: range)
        guard !matches.isEmpty else { return source }

        var replacements: [(Range<String.Index>, String)] = []
        for match in matches {
            guard let matchRange = Range(match.range, in: source),
                  let variable = capture(2, from: match, in: source),
                  isUsedAsJSONDecoderData(variable, in: source) else {
                continue
            }
            let matchedLine = String(source[matchRange])
            guard !matchedLine.contains("let \(variable): Data") else { continue }
            let annotatedLine = matchedLine.replacingOccurrences(
                of: "let \(variable) =",
                with: "let \(variable): Data ="
            )
            replacements.append((matchRange, annotatedLine))
        }

        guard !replacements.isEmpty else { return source }
        var lowered = source
        for (range, replacement) in replacements.reversed() {
            lowered.replaceSubrange(range, with: replacement)
        }
        return lowered
    }

    private static func isUsedAsJSONDecoderData(_ variable: String, in source: String) -> Bool {
        let pattern = #"JSONDecoder\(\)\.decode\([^\n]*from:[ \t]*\#(NSRegularExpression.escapedPattern(for: variable))\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        return regex.firstMatch(in: source, range: range) != nil
    }

    private static func capture(_ index: Int, from match: NSTextCheckingResult, in source: String) -> String? {
        let nsRange = match.range(at: index)
        guard nsRange.location != NSNotFound,
              let range = Range(nsRange, in: source) else {
            return nil
        }
        return String(source[range])
    }

    private static func matchingClosingBrace(in source: String, open: String.Index) -> String.Index? {
        var depth = 0
        var index = open
        while index < source.endIndex {
            switch source[index] {
            case "{":
                depth += 1
            case "}":
                depth -= 1
                if depth == 0 {
                    return index
                }
            default:
                break
            }
            index = source.index(after: index)
        }
        return nil
    }

    private static func insertingImport(_ moduleName: String, into source: String) -> String {
        var lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if let insertionIndex = lines.indices.last(where: { index in
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            return trimmed.hasPrefix("import ")
                || trimmed.hasPrefix("@preconcurrency import ")
                || trimmed.hasPrefix("@_exported import ")
                || trimmed.hasPrefix("@_implementationOnly import ")
        }) {
            lines.insert("import \(moduleName)", at: lines.index(after: insertionIndex))
            return lines.joined(separator: "\n")
        }
        return "import \(moduleName)\n\(source)"
    }
}

// MARK: - Combine publisher complexity lowering

/// Breaks complex optional published-object publisher chains into named local
/// publishers. Several large SwiftUI/AppKit apps use this shape to observe a
/// selected object, then merge child publishers from its current collection.
/// Swift's Linux solver can time out on the single expression even though the
/// same source compiles under Apple's toolchain.
private struct CombinePublisherPipelineComplexityLowering {
    private static let optionalPublishedMergePattern = #"""
(?m)^([ \t]*)([A-Za-z_][A-Za-z0-9_\.]*\?\.\$[A-Za-z_][A-Za-z0-9_]*)[ \t]*\n([ \t]*)\.flatMap\(\{\s*([A-Za-z_][A-Za-z0-9_]*)\s+in\s*\n[ \t]*\4\.\$([A-Za-z_][A-Za-z0-9_]*)\s*\n[ \t]*\}\)[ \t]*\n[ \t]*\.compactMap\(\{\s*([A-Za-z_][A-Za-z0-9_]*)\s+in\s*\n[ \t]*Publishers\.MergeMany\(\6\.elements\.compactMap\(\{\s*([^\n]+?)\s*\}\)\)\s*\n[ \t]*\}\)[ \t]*\n[ \t]*\.switchToLatest\(\)[ \t]*\n[ \t]*\.compactMap\(\{\s*([A-Za-z_][A-Za-z0-9_]*)\s+in\s*\n[ \t]*([^\n]+?)\s*\n[ \t]*\}\)[ \t]*\n[ \t]*\.flatMap\(\{\s*\$0\s*\}\)[ \t]*\n[ \t]*\.sink\s*\{
"""#

    private static let storePattern = #"[ \t\r\n]*\.store\(in:[ \t]*&([A-Za-z_][A-Za-z0-9_]*)\)"#

    func lower(_ source: String) -> String {
        guard source.contains("Publishers.MergeMany"),
              source.contains(".switchToLatest()"),
              let chainRegex = try? NSRegularExpression(pattern: Self.optionalPublishedMergePattern),
              let storeRegex = try? NSRegularExpression(pattern: Self.storePattern)
        else {
            return source
        }

        let sourceRange = NSRange(source.startIndex..<source.endIndex, in: source)
        let matches = chainRegex.matches(in: source, range: sourceRange)
        guard !matches.isEmpty else { return source }

        var replacements: [(range: Range<String.Index>, text: String)] = []

        for (index, match) in matches.enumerated() {
            guard let matchRange = Range(match.range, in: source),
                  let sinkOpenBrace = source.index(matchRange.upperBound, offsetBy: -1, limitedBy: source.startIndex),
                  let sinkCloseBrace = Self.matchingClosingBrace(in: source, open: sinkOpenBrace),
                  let store = Self.trailingStoreMatch(
                    after: source.index(after: sinkCloseBrace),
                    in: source,
                    regex: storeRegex
                  ),
                  let replacement = Self.replacement(
                    id: index,
                    match: match,
                    sinkOpenBrace: sinkOpenBrace,
                    sinkCloseBrace: sinkCloseBrace,
                    storeMatch: store.match,
                    source: source
                  )
            else {
                continue
            }

            replacements.append((
                matchRange.lowerBound..<store.range.upperBound,
                replacement
            ))
        }

        guard !replacements.isEmpty else { return source }
        var lowered = source
        for replacement in replacements.reversed() {
            lowered.replaceSubrange(replacement.range, with: replacement.text)
        }
        return lowered
    }

    private static func replacement(
        id: Int,
        match: NSTextCheckingResult,
        sinkOpenBrace: String.Index,
        sinkCloseBrace: String.Index,
        storeMatch: NSTextCheckingResult,
        source: String
    ) -> String? {
        guard let indent = capture(1, from: match, in: source),
              let sourcePublisher = capture(2, from: match, in: source),
              let chainIndent = capture(3, from: match, in: source),
              let objectName = capture(4, from: match, in: source),
              let childPublishedName = capture(5, from: match, in: source),
              let collectionName = capture(6, from: match, in: source),
              let childPublisherExpression = capture(7, from: match, in: source),
              let documentName = capture(8, from: match, in: source),
              let downstreamPublisherExpression = capture(9, from: match, in: source),
              let cancellablesName = capture(1, from: storeMatch, in: source)
        else {
            return nil
        }

        let pipelineName = "_quillCombinePipeline\(id)"
        let sinkContent = String(source[source.index(after: sinkOpenBrace)..<sinkCloseBrace])

        return """
        \(indent)if let \(pipelineName)Source = \(sourcePublisher) {
        \(indent)    let \(pipelineName)Children = \(pipelineName)Source
        \(chainIndent).flatMap { \(objectName) in
        \(chainIndent)    \(objectName).$\(childPublishedName)
        \(chainIndent)}
        \(indent)    let \(pipelineName)Documents = \(pipelineName)Children
        \(chainIndent).compactMap { \(collectionName) in
        \(chainIndent)    Publishers.MergeMany(\(collectionName).elements.compactMap { \(childPublisherExpression) })
        \(chainIndent)}
        \(chainIndent).switchToLatest()
        \(indent)    let \(pipelineName)Values = \(pipelineName)Documents
        \(chainIndent).compactMap { \(documentName) in
        \(chainIndent)    \(downstreamPublisherExpression)
        \(chainIndent)}
        \(chainIndent).flatMap { $0 }
        \(indent)    \(pipelineName)Values
        \(chainIndent).sink {\(sinkContent)}
        \(chainIndent).store(in: &\(cancellablesName))
        \(indent)}
        """
    }

    private static func capture(_ index: Int, from match: NSTextCheckingResult, in source: String) -> String? {
        let nsRange = match.range(at: index)
        guard nsRange.location != NSNotFound,
              let range = Range(nsRange, in: source)
        else {
            return nil
        }
        return String(source[range])
    }

    private static func trailingStoreMatch(
        after index: String.Index,
        in source: String,
        regex: NSRegularExpression
    ) -> (match: NSTextCheckingResult, range: Range<String.Index>)? {
        let range = NSRange(index..<source.endIndex, in: source)
        guard let match = regex.firstMatch(in: source, range: range),
              match.range.location == range.location,
              let swiftRange = Range(match.range, in: source)
        else {
            return nil
        }
        return (match, swiftRange)
    }

    private static func matchingClosingBrace(in source: String, open: String.Index) -> String.Index? {
        var depth = 0
        var cursor = open
        var state = LexState()

        while cursor < source.endIndex {
            let character = source[cursor]
            if state.isCode {
                if character == "{" {
                    depth += 1
                } else if character == "}" {
                    depth -= 1
                    if depth == 0 { return cursor }
                }
            }
            state.consume(character, in: source, at: cursor)
            cursor = source.index(after: cursor)
        }
        return nil
    }

    private struct LexState {
        var isInLineComment = false
        var isInBlockComment = false
        var isInString = false
        var isEscaped = false

        var isCode: Bool {
            !isInLineComment && !isInBlockComment && !isInString
        }

        mutating func consume(_ character: Character, in source: String, at index: String.Index) {
            if isInLineComment {
                if character == "\n" { isInLineComment = false }
                return
            }
            if isInBlockComment {
                if character == "/", previousCharacter(in: source, at: index) == "*" {
                    isInBlockComment = false
                }
                return
            }
            if isInString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    isInString = false
                }
                return
            }
            if character == "/", nextCharacter(in: source, at: index) == "/" {
                isInLineComment = true
            } else if character == "/", nextCharacter(in: source, at: index) == "*" {
                isInBlockComment = true
            } else if character == "\"" {
                isInString = true
            }
        }

        private func previousCharacter(in source: String, at index: String.Index) -> Character? {
            guard index > source.startIndex else { return nil }
            return source[source.index(before: index)]
        }

        private func nextCharacter(in source: String, at index: String.Index) -> Character? {
            let next = source.index(after: index)
            guard next < source.endIndex else { return nil }
            return source[next]
        }
    }
}

// MARK: - SwiftUI body complexity lowering

/// Splits very large SwiftUI `body` builders into private `@ViewBuilder`
/// properties. This is a compile-time compatibility pass for real apps whose
/// macOS SwiftUI bodies type-check under Apple's toolchain but time out under
/// the Linux compatibility graph.
private struct SwiftUIBodyComplexityLowering {
    private static let marker = "_quillSplitBody"
    private static let loweredViewThatFitsMarker = "ViewThatFits(children:"
    private static let bodyPattern = #"(?m)\bvar\s+(?:body|content)\s*:\s*some\s+View\s*\{"#
    private static let generatedHelperPattern = #"(?m)^[ \t]*@ViewBuilder\s*\n[ \t]*private func _quillSplitBody[A-Za-z0-9_]*\([^)]*\)\s*->\s*some\s+View\s*\{"#
    private static let stackNames: Set<String> = [
        "Group",
        "HStack",
        "LazyHGrid",
        "LazyHStack",
        "LazyVGrid",
        "LazyVStack",
        "ScrollView",
        "VStack",
        "ZStack",
    ]

    func lower(_ source: String) -> String {
        var lowered = Self.lowerSimpleViewThatFits(source)
        guard let bodyRegex = try? NSRegularExpression(pattern: Self.bodyPattern) else {
            return lowered
        }

        var searchLocation = 0
        var bodyID = 0

        if !lowered.contains(Self.marker) {
            while searchLocation < lowered.utf16.count {
                let searchRange = NSRange(location: searchLocation, length: lowered.utf16.count - searchLocation)
                guard let match = bodyRegex.firstMatch(in: lowered, range: searchRange),
                      let matchRange = Range(match.range, in: lowered) else {
                    break
                }

                let openBrace = lowered.index(before: matchRange.upperBound)
                guard let closeBrace = Self.matchingDelimiter(
                    in: lowered,
                    open: openBrace,
                    opening: "{",
                    closing: "}"
                ) else {
                    break
                }

                let bodyInnerStart = lowered.index(after: openBrace)
                let bodyInner = String(lowered[bodyInnerStart..<closeBrace])
                let memberIndent = Self.lineIndent(in: lowered, at: matchRange.lowerBound)

                if let split = Self.splitBody(bodyInner, bodyID: bodyID, memberIndent: memberIndent) {
                    let bodyIndent = memberIndent + "    "
                    var replacement = "{\n\(bodyIndent)\(split.rewrittenBody.trimmingCharacters(in: .whitespacesAndNewlines))\n\(memberIndent)}"
                    if !split.helpers.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        replacement += "\n\n\(split.helpers)"
                    }
                    let replacementStartUTF16 = lowered.utf16.distance(from: lowered.utf16.startIndex, to: openBrace.samePosition(in: lowered.utf16) ?? lowered.utf16.endIndex)
                    lowered.replaceSubrange(openBrace...closeBrace, with: replacement)
                    bodyID += 1
                    searchLocation = replacementStartUTF16 + replacement.utf16.count
                } else {
                    let nextIndex = lowered.index(after: closeBrace)
                    searchLocation = lowered.utf16.distance(from: lowered.utf16.startIndex, to: nextIndex.samePosition(in: lowered.utf16) ?? lowered.utf16.endIndex)
                }
            }
        }

        return Self.splitGeneratedViewBuilderHelpers(lowered, nextBodyID: &bodyID)
    }

    private static func splitGeneratedViewBuilderHelpers(_ source: String, nextBodyID: inout Int) -> String {
        guard source.contains(marker),
              let helperRegex = try? NSRegularExpression(pattern: generatedHelperPattern) else {
            return source
        }

        var lowered = source
        var searchLocation = 0
        while searchLocation < lowered.utf16.count {
            let searchRange = NSRange(location: searchLocation, length: lowered.utf16.count - searchLocation)
            guard let match = helperRegex.firstMatch(in: lowered, range: searchRange),
                  let matchRange = Range(match.range, in: lowered) else {
                break
            }
            let openBrace = lowered.index(before: matchRange.upperBound)
            guard let closeBrace = matchingDelimiter(in: lowered, open: openBrace, opening: "{", closing: "}") else {
                break
            }
            let bodyInnerStart = lowered.index(after: openBrace)
            let bodyInner = String(lowered[bodyInnerStart..<closeBrace])
            let memberIndent = lineIndent(in: lowered, at: matchRange.lowerBound)
            let availableParameters = helperParameters(in: String(lowered[matchRange]))
            guard let split = splitBody(
                bodyInner,
                bodyID: nextBodyID,
                memberIndent: memberIndent,
                availableParameters: availableParameters
            ) else {
                let nextIndex = lowered.index(after: closeBrace)
                searchLocation = lowered.utf16.distance(from: lowered.utf16.startIndex, to: nextIndex.samePosition(in: lowered.utf16) ?? lowered.utf16.endIndex)
                continue
            }
            let bodyIndent = memberIndent + "    "
            var replacement = "{\n\(bodyIndent)\(split.rewrittenBody.trimmingCharacters(in: .whitespacesAndNewlines))\n\(memberIndent)}"
            if !split.helpers.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                replacement += "\n\n\(split.helpers)"
            }
            let replacementStartUTF16 = lowered.utf16.distance(from: lowered.utf16.startIndex, to: openBrace.samePosition(in: lowered.utf16) ?? lowered.utf16.endIndex)
            lowered.replaceSubrange(openBrace...closeBrace, with: replacement)
            nextBodyID += 1
            searchLocation = replacementStartUTF16
        }
        return lowered
    }

    private static func lowerSimpleViewThatFits(_ source: String) -> String {
        guard source.contains("ViewThatFits"), !source.contains(loweredViewThatFitsMarker) else {
            return source
        }

        var lowered = source
        var cursor = lowered.startIndex
        while let nameRange = lowered.range(of: "ViewThatFits", range: cursor..<lowered.endIndex) {
            guard isIdentifierBoundary(in: lowered, before: nameRange.lowerBound),
                  isIdentifierBoundary(in: lowered, after: nameRange.upperBound) else {
                cursor = nameRange.upperBound
                continue
            }

            var afterName = nameRange.upperBound
            while afterName < lowered.endIndex, lowered[afterName].isWhitespace {
                afterName = lowered.index(after: afterName)
            }
            guard afterName < lowered.endIndex, lowered[afterName] == "{" else {
                cursor = afterName
                continue
            }
            guard let closeBrace = matchingDelimiter(
                in: lowered,
                open: afterName,
                opening: "{",
                closing: "}"
            ) else {
                cursor = afterName
                continue
            }

            let contentRange = lowered.index(after: afterName)..<closeBrace
            let closureContent = String(lowered[contentRange])
            if containsCompileConditionDirective(closureContent) {
                cursor = lowered.index(after: closeBrace)
                continue
            }

            let items = topLevelItems(in: closureContent)
            guard items.count >= 2, items.allSatisfy({ isExtractableBuilderItem($0.text) }) else {
                cursor = lowered.index(after: closeBrace)
                continue
            }

            let callIndent = lineIndent(in: lowered, at: nameRange.lowerBound)
            let replacement = viewThatFitsReplacement(items: items, callIndent: callIndent)
            lowered.replaceSubrange(nameRange.lowerBound...closeBrace, with: replacement)
            cursor = lowered.index(nameRange.lowerBound, offsetBy: replacement.count, limitedBy: lowered.endIndex) ?? lowered.endIndex
        }
        return lowered
    }

    private static func viewThatFitsReplacement(items: [ItemRange], callIndent: String) -> String {
        let itemIndent = callIndent + "    "
        let expressionIndent = itemIndent + "    "
        let renderedItems = items.map { item in
            let normalized = stripBuilderExpressionIndent(item.text.trimmingCharacters(in: .whitespacesAndNewlines))
            let expression = normalized
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { "\(expressionIndent)\($0)" }
                .joined(separator: "\n")
            return "\(itemIndent)AnyView(\n\(expression)\n\(itemIndent))"
        }
        return "ViewThatFits(children: [\n\(renderedItems.joined(separator: ",\n"))\n\(callIndent)])"
    }

    private struct SplitBody {
        var rewrittenBody: String
        var helpers: String
    }

    private struct ItemRange {
        var range: Range<String.Index>
        var text: String
        var leadingIndent: String
    }

    private struct ModifierRange {
        var range: Range<String.Index>
        var name: String
        var lineIndent: String
    }

    private struct FunctionParameter {
        var name: String
        var type: String
    }

    private static func splitBody(
        _ body: String,
        bodyID: Int,
        memberIndent: String,
        availableParameters: [FunctionParameter] = []
    ) -> SplitBody? {
        if let split = splitAnchoredViewThatFitsBody(body, bodyID: bodyID, memberIndent: memberIndent) {
            return split
        }
        if let split = splitSingleIfBody(body, bodyID: bodyID, memberIndent: memberIndent) {
            return split
        }
        if let split = splitGeometryReaderRootBody(body, bodyID: bodyID, memberIndent: memberIndent) {
            return split
        }
        if let split = splitRootTrackableScrollViewBody(
            body,
            bodyID: bodyID,
            memberIndent: memberIndent,
            availableParameters: availableParameters
        ) {
            return split
        }
        if let split = splitRootScrollViewReaderBody(
            body,
            bodyID: bodyID,
            memberIndent: memberIndent,
            availableParameters: availableParameters
        ) {
            return split
        }
        if let split = splitRootStackModifierChainBody(body, memberIndent: memberIndent) {
            return split
        }

        guard !body.contains(marker) else { return nil }
        guard body.count >= 1_000 else { return nil }
        guard let call = firstStackCall(in: body),
              let closureRange = call.trailingClosureRange else {
            return nil
        }

        let closureContent = String(body[closureRange])
        guard !containsCompileConditionDirective(closureContent) else { return nil }
        let originalTrailingWhitespace = trailingWhitespaceSuffix(of: closureContent)
        let items = topLevelItems(in: closureContent)
        guard items.count >= 2, items.allSatisfy({ isExtractableBuilderItem($0.text) }) else {
            return nil
        }

        var rewrittenClosure = closureContent
        var helpers: [String] = []
        for (index, item) in items.enumerated().reversed() {
            let helperName = "\(marker)\(bodyID)Part\(index)"
            let replacement = "\(item.leadingIndent)\(helperName)"
            rewrittenClosure.replaceSubrange(item.range, with: replacement)
        }

        for (index, item) in items.enumerated() {
            let helperName = "\(marker)\(bodyID)Part\(index)"
            helpers.append(helper(name: helperName, item: item.text, memberIndent: memberIndent))
        }

        if !originalTrailingWhitespace.isEmpty,
           !rewrittenClosure.hasSuffix(originalTrailingWhitespace) {
            rewrittenClosure += originalTrailingWhitespace
        }

        var rewrittenBody = body
        rewrittenBody.replaceSubrange(closureRange, with: rewrittenClosure)
        return SplitBody(rewrittenBody: rewrittenBody, helpers: helpers.joined(separator: "\n\n"))
    }

    private struct SingleIfBranch {
        var condition: String
        var content: String
    }

    private struct ExpressionExtraction {
        var prelude: String
        var expression: String
    }

    private static func splitSingleIfBody(
        _ body: String,
        bodyID: Int,
        memberIndent: String
    ) -> SplitBody? {
        guard body.count >= 1_000,
              let branch = singleIfBranch(in: body),
              !containsCompileConditionDirective(branch.content) else {
            return nil
        }

        var partIndex = 0
        let statementIndent = memberIndent + "    "
        let extracted = extractLongBuilderItemsIntoLocalFunctions(
            from: branch.content,
            bodyID: bodyID,
            partIndex: &partIndex,
            statementIndent: statementIndent
        )
        let expressionStatements = anyViewStatements(
            for: extracted.expression,
            statementIndent: statementIndent,
            finalExpression: "return view",
            startAt: .firstSafeModifier
        )
        guard expressionStatements != nil || !extracted.prelude.isEmpty else {
            return nil
        }

        var statements = [
            """
            guard \(branch.condition) else {
            \(statementIndent)    return AnyView(EmptyView())
            \(statementIndent)}
            """
        ]
        if !extracted.prelude.isEmpty {
            statements.append(extracted.prelude)
        }
        statements.append(expressionStatements ?? anyViewStatementsWrappingWholeExpression(
            extracted.expression,
            statementIndent: statementIndent,
            finalExpression: "return view"
        ))

        return SplitBody(
            rewrittenBody: statements.joined(separator: "\n"),
            helpers: ""
        )
    }

    private static func singleIfBranch(in body: String) -> SingleIfBranch? {
        guard let ifStart = firstNonWhitespaceIndex(in: body, from: body.startIndex),
              body[ifStart...].hasPrefix("if"),
              isIdentifierBoundary(in: body, after: body.index(ifStart, offsetBy: 2)) else {
            return nil
        }

        var cursor = body.index(ifStart, offsetBy: 2)
        while cursor < body.endIndex, body[cursor].isWhitespace {
            cursor = body.index(after: cursor)
        }
        let conditionStart = cursor
        var state = LexState()
        var openBrace: String.Index?
        while cursor < body.endIndex {
            let character = body[cursor]
            if character == "{", state.isTopLevel {
                openBrace = cursor
                break
            }
            state.consume(character, in: body, at: cursor)
            cursor = body.index(after: cursor)
        }
        guard let openBrace,
              let closeBrace = matchingDelimiter(in: body, open: openBrace, opening: "{", closing: "}") else {
            return nil
        }

        let suffix = body[body.index(after: closeBrace)...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard suffix.isEmpty else { return nil }

        let condition = body[conditionStart..<openBrace].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !condition.isEmpty else { return nil }
        return SingleIfBranch(
            condition: condition,
            content: String(body[body.index(after: openBrace)..<closeBrace])
        )
    }

    private enum AnyViewChainStart {
        case firstSafeModifier
        case firstObserverModifier
    }

    private static func extractLongBuilderItemsIntoLocalFunctions(
        from expression: String,
        bodyID: Int,
        partIndex: inout Int,
        statementIndent: String
    ) -> ExpressionExtraction {
        var rewrittenExpression = stripCommonIndent(expression.trimmingCharacters(in: .whitespacesAndNewlines))
        guard let call = firstStackCall(in: rewrittenExpression),
              let closureRange = call.trailingClosureRange else {
            return ExpressionExtraction(prelude: "", expression: rewrittenExpression)
        }

        let closureContent = String(rewrittenExpression[closureRange])
        guard !containsCompileConditionDirective(closureContent) else {
            return ExpressionExtraction(prelude: "", expression: rewrittenExpression)
        }

        let items = topLevelItems(in: closureContent)
        var localFunctions: [String] = []
        var rewrittenClosure = closureContent

        for item in items.reversed() {
            guard shouldExtractBuilderItemIntoAnyViewFunction(item.text) else { continue }
            let functionName = "\(marker)\(bodyID)Part\(partIndex)"
            partIndex += 1
            let replacement = "\(item.leadingIndent)\(functionName)()"
            rewrittenClosure.replaceSubrange(item.range, with: replacement)
            localFunctions.append(localAnyViewFunction(
                name: functionName,
                expression: item.text,
                statementIndent: statementIndent
            ))
        }

        guard !localFunctions.isEmpty else {
            return ExpressionExtraction(prelude: "", expression: rewrittenExpression)
        }

        rewrittenExpression.replaceSubrange(closureRange, with: rewrittenClosure)
        return ExpressionExtraction(
            prelude: localFunctions.reversed().joined(separator: "\n"),
            expression: rewrittenExpression
        )
    }

    private static func shouldExtractBuilderItemIntoAnyViewFunction(_ item: String) -> Bool {
        guard item.count >= 500 else { return false }
        let modifiers = topLevelModifiers(in: item)
        guard let firstObserver = modifiers.first(where: { isObserverLikeModifier($0.name) }) else {
            return false
        }
        let deferred = modifiers.filter { $0.range.lowerBound >= firstObserver.range.lowerBound }
        return deferred.count >= 3 && deferred.allSatisfy { isModifierDeferredThroughAnyView($0.name) }
    }

    private static func localAnyViewFunction(
        name: String,
        expression: String,
        statementIndent: String
    ) -> String {
        let bodyIndent = statementIndent + "    "
        let statements = anyViewStatements(
            for: expression,
            statementIndent: bodyIndent,
            finalExpression: "return view",
            startAt: .firstObserverModifier
        ) ?? anyViewStatementsWrappingWholeExpression(
            expression,
            statementIndent: bodyIndent,
            finalExpression: "return view"
        )

        return """
        \(statementIndent)func \(name)() -> AnyView {
        \(statements)
        \(statementIndent)}
        """
    }

    private static func anyViewStatements(
        for expression: String,
        statementIndent: String,
        finalExpression: String,
        startAt: AnyViewChainStart
    ) -> String? {
        let normalizedExpression = stripCommonIndent(expression.trimmingCharacters(in: .whitespacesAndNewlines))
        let modifiers = topLevelModifiers(in: normalizedExpression)
        guard !modifiers.isEmpty else { return nil }

        let firstDeferred: ModifierRange?
        switch startAt {
        case .firstSafeModifier:
            firstDeferred = modifiers.first
        case .firstObserverModifier:
            firstDeferred = modifiers.first { isObserverLikeModifier($0.name) }
        }
        guard let firstDeferred else { return nil }

        let deferredModifiers = modifiers.filter { $0.range.lowerBound >= firstDeferred.range.lowerBound }
        guard !deferredModifiers.isEmpty,
              deferredModifiers.allSatisfy({ isModifierDeferredThroughAnyView($0.name) }) else {
            return nil
        }

        let expressionIndent = statementIndent + "    "
        let baseExpression = String(normalizedExpression[..<firstDeferred.range.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !baseExpression.isEmpty else { return nil }

        var statements = [
            """
            \(statementIndent)var view = AnyView(
            \(indentLines(qualifyKnownMaterialShorthand(in: baseExpression), with: expressionIndent))
            \(statementIndent))
            """
        ]

        for modifier in deferredModifiers {
            let modifierText = String(normalizedExpression[modifier.range])
            let normalizedModifier = qualifyKnownMaterialShorthand(
                in: stripLineIndent(
                    modifierText.trimmingCharacters(in: .whitespacesAndNewlines),
                    indent: modifier.lineIndent
                )
            )
            statements.append(
                """
                \(statementIndent)view = AnyView(view
                \(indentLines(normalizedModifier, with: expressionIndent))
                \(statementIndent))
                """
            )
        }
        statements.append("\(statementIndent)\(finalExpression)")
        return statements.joined(separator: "\n")
    }

    private static func anyViewStatementsWrappingWholeExpression(
        _ expression: String,
        statementIndent: String,
        finalExpression: String
    ) -> String {
        let expressionIndent = statementIndent + "    "
        let normalizedExpression = stripCommonIndent(expression.trimmingCharacters(in: .whitespacesAndNewlines))
        return """
        \(statementIndent)var view = AnyView(
        \(indentLines(qualifyKnownMaterialShorthand(in: normalizedExpression), with: expressionIndent))
        \(statementIndent))
        \(statementIndent)\(finalExpression)
        """
    }

    private static func splitAnchoredViewThatFitsBody(
        _ body: String,
        bodyID: Int,
        memberIndent: String
    ) -> SplitBody? {
        guard body.count >= 1_000,
              let callStart = firstNonWhitespaceIndex(in: body, from: body.startIndex),
              body[callStart...].hasPrefix(loweredViewThatFitsMarker) else {
            return nil
        }
        guard !containsCompileConditionDirective(body) else { return nil }

        let openParen = body.index(callStart, offsetBy: "ViewThatFits".count)
        guard openParen < body.endIndex, body[openParen] == "(",
              let closeParen = matchingDelimiter(
                  in: body,
                  open: openParen,
                  opening: "(",
                  closing: ")"
              ) else {
            return nil
        }

        let helperName = "\(marker)\(bodyID)Part0"
        let itemText = String(body[callStart...closeParen])
        let item = ItemRange(range: callStart..<body.index(after: closeParen), text: itemText, leadingIndent: "")
        var rewrittenBody = body
        rewrittenBody.replaceSubrange(callStart...closeParen, with: helperName)
        rewrittenBody = lowerLongOnChangeModifierChain(rewrittenBody)
        return SplitBody(
            rewrittenBody: rewrittenBody,
            helpers: helper(name: helperName, item: item.text, memberIndent: memberIndent)
        )
    }

    private struct RootClosureCall {
        var callStart: String.Index
        var closureContentRange: Range<String.Index>
    }

    private struct ClosureParameterBody {
        var parameterName: String
        var body: String
    }

    private static func helperParameters(in signature: String) -> [FunctionParameter] {
        guard let openParen = signature.firstIndex(of: "("),
              let closeParen = matchingDelimiter(
                  in: signature,
                  open: openParen,
                  opening: "(",
                  closing: ")"
              ) else {
            return []
        }

        let parameters = String(signature[signature.index(after: openParen)..<closeParen])
        guard let regex = try? NSRegularExpression(
            pattern: #"(?:_\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*:\s*([^,)=]+)"#
        ) else {
            return []
        }

        return regex.matches(in: parameters, range: NSRange(parameters.startIndex..<parameters.endIndex, in: parameters))
            .compactMap { match -> FunctionParameter? in
                guard let nameRange = Range(match.range(at: 1), in: parameters),
                      let typeRange = Range(match.range(at: 2), in: parameters) else {
                    return nil
                }
                let name = String(parameters[nameRange])
                let type = String(parameters[typeRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !type.isEmpty else { return nil }
                return FunctionParameter(name: name, type: type)
            }
    }

    private static func splitGeometryReaderRootBody(
        _ body: String,
        bodyID: Int,
        memberIndent: String
    ) -> SplitBody? {
        guard body.count >= 1_000,
              let call = rootTrailingClosureCall(named: "GeometryReader", in: body) else {
            return nil
        }

        let closureContent = String(body[call.closureContentRange])
        guard let parameterBody = singleParameterClosureBody(in: closureContent) else {
            return nil
        }

        let helperName = "\(marker)\(bodyID)Geometry"
        let callIndent = lineIndent(in: body, at: call.callStart)
        let closureItemIndent = callIndent + "    "
        let replacementClosureContent = """
         \(parameterBody.parameterName) in
        \(closureItemIndent)\(helperName)(\(parameterBody.parameterName))
        \(callIndent)
        """

        var rewrittenBody = body
        rewrittenBody.replaceSubrange(call.closureContentRange, with: replacementClosureContent)
        return SplitBody(
            rewrittenBody: rewrittenBody,
            helpers: functionHelper(
                name: helperName,
                parameterName: parameterBody.parameterName,
                parameterType: "GeometryProxy",
                content: parameterBody.body,
                memberIndent: memberIndent
            )
        )
    }

    private static func splitRootTrackableScrollViewBody(
        _ body: String,
        bodyID: Int,
        memberIndent: String,
        availableParameters: [FunctionParameter]
    ) -> SplitBody? {
        guard body.count >= 1_000,
              body.contains("TrackableScrollView"),
              !body.contains("TrackableContent"),
              let call = rootTrailingClosureCall(named: "TrackableScrollView", in: body) else {
            return nil
        }

        let closureContent = String(body[call.closureContentRange])
        guard !containsCompileConditionDirective(closureContent) else {
            return nil
        }

        let helperName = "\(marker)\(bodyID)TrackableContent"
        let callIndent = lineIndent(in: body, at: call.callStart)
        let closureItemIndent = callIndent + "    "
        let capturedParameters = parametersUsed(in: closureContent, from: availableParameters)
        let helperCall = helperCallExpression(name: helperName, parameters: capturedParameters)
        let replacementClosureContent = """

        \(closureItemIndent)\(helperCall)
        \(callIndent)
        """

        var rewrittenBody = body
        rewrittenBody.replaceSubrange(call.closureContentRange, with: replacementClosureContent)

        let helpers: String
        if !capturedParameters.isEmpty {
            helpers = functionHelper(
                name: helperName,
                parameters: capturedParameters,
                content: closureContent,
                memberIndent: memberIndent
            )
        } else {
            helpers = noParameterFunctionHelper(
                name: helperName,
                content: closureContent,
                memberIndent: memberIndent
            )
        }
        return SplitBody(rewrittenBody: rewrittenBody, helpers: helpers)
    }

    private static func splitRootScrollViewReaderBody(
        _ body: String,
        bodyID: Int,
        memberIndent: String,
        availableParameters: [FunctionParameter]
    ) -> SplitBody? {
        guard body.count >= 1_000,
              body.contains("ScrollViewReader"),
              !body.contains("ScrollReaderContent"),
              let call = rootTrailingClosureCall(named: "ScrollViewReader", in: body) else {
            return nil
        }

        let closureContent = String(body[call.closureContentRange])
        guard !containsCompileConditionDirective(closureContent),
              let parameterBody = singleParameterClosureBody(in: closureContent) else {
            return nil
        }

        let scrollParameter = FunctionParameter(name: parameterBody.parameterName, type: "ScrollViewProxy")
        let capturedParameters = [scrollParameter] + parametersUsed(in: parameterBody.body, from: availableParameters)
        let helperName = "\(marker)\(bodyID)ScrollReaderContent"
        let callIndent = lineIndent(in: body, at: call.callStart)
        let closureItemIndent = callIndent + "    "
        let replacementClosureContent = """
         \(parameterBody.parameterName) in
        \(closureItemIndent)\(helperCallExpression(name: helperName, parameters: capturedParameters))
        \(callIndent)
        """

        var rewrittenBody = body
        rewrittenBody.replaceSubrange(call.closureContentRange, with: replacementClosureContent)
        return SplitBody(
            rewrittenBody: rewrittenBody,
            helpers: functionHelper(
                name: helperName,
                parameters: capturedParameters,
                content: parameterBody.body,
                memberIndent: memberIndent
            )
        )
    }

    private static func splitRootStackModifierChainBody(
        _ body: String,
        memberIndent: String
    ) -> SplitBody? {
        guard body.count >= 1_000,
              !body.contains(marker),
              firstStackCall(in: body) != nil,
              let statements = anyViewStatements(
                  for: body,
                  statementIndent: memberIndent + "    ",
                  finalExpression: "return view",
                  startAt: .firstObserverModifier
              ) else {
            return nil
        }
        return SplitBody(rewrittenBody: statements, helpers: "")
    }

    private static func rootTrailingClosureCall(named name: String, in body: String) -> RootClosureCall? {
        guard var cursor = firstNonWhitespaceIndex(in: body, from: body.startIndex),
              body[cursor...].hasPrefix(name) else {
            return nil
        }
        let callStart = cursor
        cursor = body.index(cursor, offsetBy: name.count)
        guard isIdentifierBoundary(in: body, after: cursor) else { return nil }

        while cursor < body.endIndex, body[cursor].isWhitespace {
            cursor = body.index(after: cursor)
        }
        if cursor < body.endIndex, body[cursor] == "(" {
            guard let closeParen = matchingDelimiter(
                in: body,
                open: cursor,
                opening: "(",
                closing: ")"
            ) else {
                return nil
            }
            cursor = body.index(after: closeParen)
            while cursor < body.endIndex, body[cursor].isWhitespace {
                cursor = body.index(after: cursor)
            }
        }

        guard cursor < body.endIndex, body[cursor] == "{",
              let closeBrace = matchingDelimiter(
                  in: body,
                  open: cursor,
                  opening: "{",
                  closing: "}"
              ) else {
            return nil
        }

        return RootClosureCall(
            callStart: callStart,
            closureContentRange: body.index(after: cursor)..<closeBrace
        )
    }

    private static func singleParameterClosureBody(in closureContent: String) -> ClosureParameterBody? {
        guard let firstLineEnd = closureContent.firstIndex(of: "\n") else { return nil }
        let header = closureContent[..<firstLineEnd].trimmingCharacters(in: .whitespacesAndNewlines)
        guard header.hasSuffix(" in") else { return nil }
        let parameter = header.dropLast(3).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !parameter.isEmpty,
              parameter.allSatisfy({ $0.isIdentifierContinuation }),
              let first = parameter.first,
              first.isLetter || first == "_" else {
            return nil
        }

        let bodyStart = closureContent.index(after: firstLineEnd)
        return ClosureParameterBody(
            parameterName: parameter,
            body: String(closureContent[bodyStart...])
        )
    }

    private static func parametersUsed(
        in content: String,
        from parameters: [FunctionParameter]
    ) -> [FunctionParameter] {
        parameters.filter { containsIdentifier($0.name, in: content) }
    }

    private static func helperCallExpression(name: String, parameters: [FunctionParameter]) -> String {
        guard !parameters.isEmpty else { return "\(name)()" }
        return "\(name)(\(parameters.map(\.name).joined(separator: ", ")))"
    }

    private static func lowerLongOnChangeModifierChain(_ body: String) -> String {
        guard body.contains(".onChange("),
              !body.contains("var view = AnyView("),
              !body.contains("return view") else {
            return body
        }
        guard let expressionStart = firstNonWhitespaceIndex(in: body, from: body.startIndex),
              body[expressionStart...].hasPrefix(marker) else {
            return body
        }

        let modifiers = topLevelModifiers(in: body)
        let onChangeModifiers = modifiers.filter { $0.name == "onChange" }
        guard onChangeModifiers.count >= 3,
              let firstOnChange = onChangeModifiers.first else {
            return body
        }

        let deferredModifiers = modifiers.filter { $0.range.lowerBound >= firstOnChange.range.lowerBound }
        guard deferredModifiers.allSatisfy({ isModifierDeferredThroughAnyView($0.name) }) else {
            return body
        }

        let statementIndent = lineIndent(in: body, at: expressionStart)
        let expressionIndent = statementIndent + "    "
        let baseExpression = String(body[expressionStart..<firstOnChange.range.lowerBound])
        let normalizedBase = qualifyKnownMaterialShorthand(
            in: stripLineIndent(
                baseExpression.trimmingCharacters(in: .whitespacesAndNewlines),
                indent: statementIndent
            )
        )

        var statements = [
            """
            \(statementIndent)var view = AnyView(
            \(indentLines(normalizedBase, with: expressionIndent))
            \(statementIndent))
            """
        ]

        for modifier in deferredModifiers {
            let modifierText = String(body[modifier.range])
            let normalizedModifier = qualifyKnownMaterialShorthand(
                in: stripLineIndent(
                    modifierText.trimmingCharacters(in: .whitespacesAndNewlines),
                    indent: modifier.lineIndent
                )
            )
            statements.append(
                """
                \(statementIndent)view = AnyView(view
                \(indentLines(normalizedModifier, with: expressionIndent))
                \(statementIndent))
                """
            )
        }
        statements.append("\(statementIndent)return view")

        let prefix = body[..<expressionStart]
        let suffixStart = deferredModifiers.last?.range.upperBound ?? body.endIndex
        let suffix = body[suffixStart...]
        return String(prefix) + statements.joined(separator: "\n") + String(suffix)
    }

    private static func qualifyKnownMaterialShorthand(in text: String) -> String {
        guard text.contains(".background(.") else { return text }
        let materialNames = [
            "ultraThinMaterial",
            "ultraThickMaterial",
            "regularMaterial",
            "thickMaterial",
            "thinMaterial",
            "ultraThin",
            "ultraThick",
            "bar",
        ].joined(separator: "|")
        let pattern = #"\.background\(\s*\.(\#(materialNames))\s*\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(
            in: text,
            range: range,
            withTemplate: ".background(Material.$1)"
        )
    }

    private static func isModifierDeferredThroughAnyView(_ name: String) -> Bool {
        // `.onChange` closures often dominate the type-checking cost. Letting a
        // few adjacent visual modifiers travel through AnyView is source-safe
        // for the compatibility backend and keeps the lowering generic.
        switch name {
        case "accessibilityElement",
             "accessibilityLabel",
             "background",
             "clipShape",
             "edgesIgnoringSafeArea",
             "frame",
             "gesture",
             "highPriorityGesture",
             "offset",
             "onAppear",
             "onChange",
             "onDrop",
             "onHover",
             "onReceive",
             "overlay",
             "padding",
             "simultaneousGesture",
             "task":
            return true
        default:
            return false
        }
    }

    private static func isObserverLikeModifier(_ name: String) -> Bool {
        switch name {
        case "onAppear", "onChange", "onReceive", "task":
            return true
        default:
            return false
        }
    }

    private static func topLevelModifiers(in body: String) -> [ModifierRange] {
        var starts: [String.Index] = []
        var cursor = body.startIndex
        var state = LexState()

        while cursor < body.endIndex {
            let character = body[cursor]
            state.consume(character, in: body, at: cursor)
            if character == "\n",
               state.isTopLevel,
               let dot = firstTopLevelModifierDot(after: cursor, in: body) {
                starts.append(dot)
            }
            cursor = body.index(after: cursor)
        }

        var modifiers: [ModifierRange] = []
        for (index, start) in starts.enumerated() {
            let end = index + 1 < starts.count ? starts[index + 1] : body.endIndex
            let nameStart = body.index(after: start)
            var nameEnd = nameStart
            while nameEnd < body.endIndex, body[nameEnd].isIdentifierContinuation {
                nameEnd = body.index(after: nameEnd)
            }
            guard nameStart < nameEnd else { continue }
            modifiers.append(ModifierRange(
                range: start..<end,
                name: String(body[nameStart..<nameEnd]),
                lineIndent: lineIndent(in: body, at: start)
            ))
        }
        return modifiers
    }

    private static func firstTopLevelModifierDot(after newline: String.Index, in body: String) -> String.Index? {
        var cursor = body.index(after: newline)
        while cursor < body.endIndex, body[cursor] == " " || body[cursor] == "\t" {
            cursor = body.index(after: cursor)
        }
        guard cursor < body.endIndex, body[cursor] == "." else { return nil }
        return cursor
    }

    private static func stripLineIndent(_ text: String, indent: String) -> String {
        guard !indent.isEmpty else { return text }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        return lines.enumerated().map { index, line in
            guard index > 0, line.hasPrefix(indent) else { return line }
            return String(line.dropFirst(indent.count))
        }.joined(separator: "\n")
    }

    private static func indentLines(_ text: String, with indent: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { "\(indent)\($0)" }
            .joined(separator: "\n")
    }

    private static func containsCompileConditionDirective(_ source: String) -> Bool {
        source.split(separator: "\n", omittingEmptySubsequences: false).contains { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.hasPrefix("#if ")
                || trimmed.hasPrefix("#elseif ")
                || trimmed == "#else"
                || trimmed == "#endif"
        }
    }

    private struct StackCall {
        var trailingClosureRange: Range<String.Index>?
    }

    private static func firstStackCall(in body: String) -> StackCall? {
        var cursor = body.startIndex
        while cursor < body.endIndex, body[cursor].isWhitespace {
            cursor = body.index(after: cursor)
        }

        let nameStart = cursor
        while cursor < body.endIndex, body[cursor].isLetter {
            cursor = body.index(after: cursor)
        }

        guard nameStart < cursor else { return nil }
        let name = String(body[nameStart..<cursor])
        guard stackNames.contains(name) else { return nil }

        while cursor < body.endIndex, body[cursor].isWhitespace {
            cursor = body.index(after: cursor)
        }

        if cursor < body.endIndex, body[cursor] == "(" {
            guard let closeParen = matchingDelimiter(
                in: body,
                open: cursor,
                opening: "(",
                closing: ")"
            ) else {
                return nil
            }
            cursor = body.index(after: closeParen)
            while cursor < body.endIndex, body[cursor].isWhitespace {
                cursor = body.index(after: cursor)
            }
        }

        guard cursor < body.endIndex, body[cursor] == "{" else { return nil }
        guard let closeBrace = matchingDelimiter(
            in: body,
            open: cursor,
            opening: "{",
            closing: "}"
        ) else {
            return nil
        }
        return StackCall(trailingClosureRange: body.index(after: cursor)..<closeBrace)
    }

    private static func topLevelItems(in closureContent: String) -> [ItemRange] {
        var items: [ItemRange] = []
        guard var itemStart = firstNonWhitespaceIndex(in: closureContent, from: closureContent.startIndex) else {
            return []
        }
        var cursor = itemStart
        var state = LexState()

        while cursor < closureContent.endIndex {
            let character = closureContent[cursor]
            state.consume(character, in: closureContent, at: cursor)

            if character == "\n",
               state.isTopLevel,
               let next = firstNonWhitespaceIndex(in: closureContent, from: closureContent.index(after: cursor)),
               shouldStartNewItem(afterNewlineAt: next, in: closureContent) {
                let itemRange = itemStart..<cursor
                appendItem(itemRange, from: closureContent, to: &items)
                itemStart = next
                cursor = next
                continue
            }

            cursor = closureContent.index(after: cursor)
        }

        appendItem(itemStart..<closureContent.endIndex, from: closureContent, to: &items)
        return items
    }

    private static func appendItem(
        _ range: Range<String.Index>,
        from source: String,
        to items: inout [ItemRange]
    ) {
        let text = String(source[range])
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        items.append(ItemRange(range: range, text: text, leadingIndent: leadingIndent(of: text)))
    }

    private static func trailingWhitespaceSuffix(of source: String) -> String {
        guard let lastNonWhitespace = source.indices.reversed().first(where: { !source[$0].isWhitespace }) else {
            return source
        }
        let start = source.index(after: lastNonWhitespace)
        return String(source[start...])
    }

    private static func shouldStartNewItem(afterNewlineAt index: String.Index, in source: String) -> Bool {
        guard index < source.endIndex else { return false }
        if source[index] == "." || source[index] == ")" || source[index] == "]" || source[index] == "}" {
            return false
        }

        let suffix = source[index...]
        for continuationOperator in ["&&", "||", "?", ":", ","] {
            if suffix.hasPrefix(continuationOperator) {
                return false
            }
        }

        for continuation in ["else", "catch", "while"] {
            if suffix.hasPrefix(continuation) {
                let end = source.index(index, offsetBy: continuation.count, limitedBy: source.endIndex) ?? source.endIndex
                if end == source.endIndex || !source[end].isIdentifierContinuation {
                    return false
                }
            }
        }
        return true
    }

    private static func isExtractableBuilderItem(_ item: String) -> Bool {
        let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        for forbidden in ["let ", "var ", "return ", "guard ", "throw ", "defer "] {
            if trimmed.hasPrefix(forbidden) { return false }
        }
        return true
    }

    private static func helper(name: String, item: String, memberIndent: String) -> String {
        let bodyIndent = memberIndent + "    "
        var normalized = stripCommonIndent(item.trimmingCharacters(in: .whitespacesAndNewlines))
        if isCommentOnlyBuilderItem(normalized) {
            normalized = "EmptyView()"
        }
        let indented = normalized
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { "\(bodyIndent)\($0)" }
            .joined(separator: "\n")

        return """
        \(memberIndent)@ViewBuilder
        \(memberIndent)private var \(name): some View {
        \(indented)
        \(memberIndent)}
        """
    }

    private static func functionHelper(
        name: String,
        parameterName: String,
        parameterType: String,
        content: String,
        memberIndent: String
    ) -> String {
        functionHelper(
            name: name,
            parameters: [FunctionParameter(name: parameterName, type: parameterType)],
            content: content,
            memberIndent: memberIndent
        )
    }

    private static func functionHelper(
        name: String,
        parameters: [FunctionParameter],
        content: String,
        memberIndent: String
    ) -> String {
        let bodyIndent = memberIndent + "    "
        var normalized = stripCommonIndent(content.trimmingCharacters(in: .whitespacesAndNewlines))
        if isCommentOnlyBuilderItem(normalized) {
            normalized = "EmptyView()"
        }
        let indented = normalized
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { "\(bodyIndent)\($0)" }
            .joined(separator: "\n")
        let parameterList = parameters
            .map { "_ \($0.name): \($0.type)" }
            .joined(separator: ", ")

        return """
        \(memberIndent)@ViewBuilder
        \(memberIndent)private func \(name)(\(parameterList)) -> some View {
        \(indented)
        \(memberIndent)}
        """
    }

    private static func noParameterFunctionHelper(
        name: String,
        content: String,
        memberIndent: String
    ) -> String {
        let bodyIndent = memberIndent + "    "
        var normalized = stripCommonIndent(content.trimmingCharacters(in: .whitespacesAndNewlines))
        if isCommentOnlyBuilderItem(normalized) {
            normalized = "EmptyView()"
        }
        let indented = normalized
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { "\(bodyIndent)\($0)" }
            .joined(separator: "\n")

        return """
        \(memberIndent)@ViewBuilder
        \(memberIndent)private func \(name)() -> some View {
        \(indented)
        \(memberIndent)}
        """
    }

    private static func isCommentOnlyBuilderItem(_ item: String) -> Bool {
        let lines = item.split(separator: "\n", omittingEmptySubsequences: false)
        return lines.allSatisfy { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty || trimmed.hasPrefix("//")
        }
    }

    private static func stripCommonIndent(_ text: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let nonEmptyIndents = lines.compactMap { line -> Int? in
            guard line.contains(where: { !$0.isWhitespace }) else { return nil }
            return line.prefix { $0 == " " || $0 == "\t" }.count
        }
        guard let common = nonEmptyIndents.min(), common > 0 else { return text }
        return lines
            .map { line in
                guard line.count >= common else { return line }
                let cutoff = line.index(line.startIndex, offsetBy: common)
                return String(line[cutoff...])
            }
            .joined(separator: "\n")
    }

    private static func stripBuilderExpressionIndent(_ text: String) -> String {
        let common = stripCommonIndent(text)
        let lines = common.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.count > 1, lines[0].prefix(while: { $0 == " " || $0 == "\t" }).isEmpty else {
            return common
        }

        let tailIndents = lines.dropFirst().compactMap { line -> Int? in
            guard line.contains(where: { !$0.isWhitespace }) else { return nil }
            return line.prefix { $0 == " " || $0 == "\t" }.count
        }
        guard let tailCommon = tailIndents.min(), tailCommon > 0 else { return common }

        let strippedTail = lines.dropFirst().map { line in
            guard line.count >= tailCommon else { return line }
            let cutoff = line.index(line.startIndex, offsetBy: tailCommon)
            return String(line[cutoff...])
        }
        return ([lines[0]] + strippedTail).joined(separator: "\n")
    }

    private static func firstNonWhitespaceIndex(
        in source: String,
        from start: String.Index
    ) -> String.Index? {
        var index = start
        while index < source.endIndex {
            if !source[index].isWhitespace { return index }
            index = source.index(after: index)
        }
        return nil
    }

    private static func leadingIndent(of text: String) -> String {
        guard let newline = text.lastIndex(of: "\n") else {
            return String(text.prefix { $0 == " " || $0 == "\t" })
        }
        let afterNewline = text.index(after: newline)
        return String(text[afterNewline...].prefix { $0 == " " || $0 == "\t" })
    }

    private static func lineIndent(in source: String, at index: String.Index) -> String {
        let lineStart = source[..<index].lastIndex(of: "\n").map { source.index(after: $0) } ?? source.startIndex
        return String(source[lineStart..<index].prefix { $0 == " " || $0 == "\t" })
    }

    private static func containsIdentifier(_ identifier: String, in source: String) -> Bool {
        guard !identifier.isEmpty else { return false }
        var cursor = source.startIndex
        while let range = source.range(of: identifier, range: cursor..<source.endIndex) {
            if isIdentifierBoundary(in: source, before: range.lowerBound),
               isIdentifierBoundary(in: source, after: range.upperBound) {
                return true
            }
            cursor = range.upperBound
        }
        return false
    }

    private static func isIdentifierBoundary(
        in source: String,
        before index: String.Index
    ) -> Bool {
        guard index > source.startIndex else { return true }
        return !source[source.index(before: index)].isIdentifierContinuation
    }

    private static func isIdentifierBoundary(
        in source: String,
        after index: String.Index
    ) -> Bool {
        guard index < source.endIndex else { return true }
        return !source[index].isIdentifierContinuation
    }

    private static func matchingDelimiter(
        in source: String,
        open: String.Index,
        opening: Character,
        closing: Character
    ) -> String.Index? {
        var state = LexState()
        var depth = 0
        var cursor = open

        while cursor < source.endIndex {
            let character = source[cursor]
            if state.isCode {
                if character == opening {
                    depth += 1
                } else if character == closing {
                    depth -= 1
                    if depth == 0 { return cursor }
                }
            }
            state.consume(character, in: source, at: cursor)
            cursor = source.index(after: cursor)
        }

        return nil
    }

    private struct LexState {
        var parenDepth = 0
        var braceDepth = 0
        var bracketDepth = 0
        var isInLineComment = false
        var isInBlockComment = false
        var isInString = false
        var isEscaped = false

        var isTopLevel: Bool {
            isCode && parenDepth == 0 && braceDepth == 0 && bracketDepth == 0
        }

        var isCode: Bool {
            !isInLineComment && !isInBlockComment && !isInString
        }

        mutating func consume(_ character: Character, in source: String, at index: String.Index) {
            if isInLineComment {
                if character == "\n" { isInLineComment = false }
                return
            }

            if isInBlockComment {
                if character == "/", previousCharacter(in: source, at: index) == "*" {
                    isInBlockComment = false
                }
                return
            }

            if isInString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    isInString = false
                }
                return
            }

            if character == "/", nextCharacter(in: source, at: index) == "/" {
                isInLineComment = true
                return
            }

            if character == "/", nextCharacter(in: source, at: index) == "*" {
                isInBlockComment = true
                return
            }

            if character == "\"" {
                isInString = true
                return
            }

            switch character {
            case "(":
                parenDepth += 1
            case ")":
                parenDepth = max(0, parenDepth - 1)
            case "{":
                braceDepth += 1
            case "}":
                braceDepth = max(0, braceDepth - 1)
            case "[":
                bracketDepth += 1
            case "]":
                bracketDepth = max(0, bracketDepth - 1)
            default:
                break
            }
        }

        private func previousCharacter(in source: String, at index: String.Index) -> Character? {
            guard index > source.startIndex else { return nil }
            return source[source.index(before: index)]
        }

        private func nextCharacter(in source: String, at index: String.Index) -> Character? {
            let next = source.index(after: index)
            guard next < source.endIndex else { return nil }
            return source[next]
        }
    }
}

// MARK: - Rewriter

private final class SwiftUIRewriter: SyntaxRewriter {
    /// Attribute names removed wholesale whether they appear on a declaration
    /// or wrapped around an inline type expression.
    private static let strippedAttributeNames: Set<String> = [
        "main", "Observable",
        "objc", "objcMembers",
        "IBAction", "IBOutlet", "IBInspectable", "IBDesignable",
        "NSManaged", "GKInspectable", "NSApplicationMain",
    ]

    override func visit(_ node: ClassDeclSyntax) -> DeclSyntax {
        // Check the input node before recursion: the AttributeListSyntax
        // override strips @Observable from the recursed class declaration.
        let isObservableClass = node.attributes.contains { Self.isAttribute($0, named: "Observable") }
        let firstAttributeWasStripped = Self.firstAttributeIsStripped(node.attributes)

        var recursed: ClassDeclSyntax
        if let visited = super.visit(node).as(ClassDeclSyntax.self) {
            recursed = visited
        } else {
            recursed = node
        }
        if firstAttributeWasStripped {
            Self.restoreDeclLeadingTrivia(node.leadingTrivia, to: &recursed)
        }

        guard isObservableClass else {
            return DeclSyntax(recursed)
        }

        var updated = recursed
        Self.prependQuillObservableObject(to: &updated)
        Self.wrapEligibleStoredVars(in: &updated)
        return DeclSyntax(updated)
    }

    override func visit(_ node: FunctionDeclSyntax) -> DeclSyntax {
        let firstAttributeWasStripped = Self.firstAttributeIsStripped(node.attributes)
        let shouldPreserveMainActorBuildBlock = Self.shouldPreserveMainActorBuildBlock(node)
        let visited = super.visit(node)
        guard var recursed = visited.as(FunctionDeclSyntax.self) else { return visited }
        if shouldPreserveMainActorBuildBlock {
            recursed = Self.prependingMainActor(to: recursed)
        }
        if firstAttributeWasStripped {
            Self.restoreDeclLeadingTrivia(node.leadingTrivia, to: &recursed)
        }
        return DeclSyntax(recursed)
    }

    override func visit(_ node: VariableDeclSyntax) -> DeclSyntax {
        let firstAttributeWasStripped = Self.firstAttributeIsStripped(node.attributes)
        let visited = super.visit(node)
        guard var recursed = visited.as(VariableDeclSyntax.self) else { return visited }
        if firstAttributeWasStripped {
            Self.restoreDeclLeadingTrivia(node.leadingTrivia, to: &recursed)
        }
        return DeclSyntax(recursed)
    }

    /// Overriding `visit(_ node: AttributeListSyntax)` catches every place
    /// SwiftSyntax models an attribute list — decl-level, type-level, and
    /// accessor-level — without per-decl-type boilerplate.
    override func visit(_ node: AttributeListSyntax) -> AttributeListSyntax {
        let recursed = super.visit(node)
        var elements = recursed.filter { element in
            guard case .attribute(let attr) = element else { return true }
            return !Self.strippedAttributeNames.contains(attr.attributeName.trimmedDescription)
        }
        guard elements.count != recursed.count else { return recursed }
        if let lastIndex = elements.indices.last,
           case .attribute(var attr) = elements[lastIndex],
           attr.trailingTrivia.isEmpty,
           attr.attributeName.trailingTrivia.isEmpty {
            attr = attr.with(\.trailingTrivia, .space)
            elements[lastIndex] = .attribute(attr)
        }
        return elements
    }

    /// Drop `Sendable` from any inheritance list that also names `View`. This
    /// matches the regex `: View, Sendable` → `: View` but works regardless of
    /// `Sendable`'s position in the list, and works for structs, classes,
    /// actors, and enums.
    override func visit(_ node: InheritanceClauseSyntax) -> InheritanceClauseSyntax {
        let recursed = super.visit(node)
        let hasView = recursed.inheritedTypes.contains { $0.type.trimmedDescription == "View" }
        guard hasView else { return recursed }

        let types = recursed.inheritedTypes
        guard let sendableIdx = types.firstIndex(where: { $0.type.trimmedDescription == "Sendable" }) else {
            return recursed
        }

        let removedEntry = types[sendableIdx]
        var newTypes = types
        newTypes.remove(at: sendableIdx)

        // Ensure the new last entry has no trailing comma and that any whitespace
        // that lived on the removed `Sendable` entry's trailing trivia (typically
        // the space before `{`) is carried forward so the brace doesn't fuse.
        if !newTypes.isEmpty {
            let lastIdx = newTypes.index(before: newTypes.endIndex)
            var last = newTypes[lastIdx]
            last.trailingComma = nil

            let removedTrailing = removedEntry.type.trailingTrivia
            if !removedTrailing.isEmpty {
                last.type = last.type.with(\.trailingTrivia, last.type.trailingTrivia + removedTrailing)
            }
            newTypes[lastIdx] = last
        }

        var updated = recursed
        updated.inheritedTypes = newTypes
        return updated
    }

    /// Drop top-level `#Preview` macro expansions. These have no Linux
    /// equivalent and exist only for Xcode preview rendering. The Swift
    /// parser sometimes models the freestanding `#Preview` as a
    /// `MacroExpansionDeclSyntax` and sometimes as a
    /// `MacroExpansionExprSyntax` depending on parse ambiguity — handle both.
    override func visit(_ node: CodeBlockItemListSyntax) -> CodeBlockItemListSyntax {
        let recursed = super.visit(node)
        let filtered = recursed.filter { item in
            if let macroDecl = item.item.as(MacroExpansionDeclSyntax.self),
               macroDecl.macroName.text == "Preview" {
                return false
            }
            if let macroExpr = item.item.as(MacroExpansionExprSyntax.self),
               macroExpr.macroName.text == "Preview" {
                return false
            }
            return true
        }
        if filtered.count == recursed.count { return recursed }
        return filtered
    }

    /// Rewrite `#selector(x)` into QuillFoundation's plain selector token.
    /// Swift on Linux has no Objective-C selector expression support, but the
    /// source only needs a stable opaque value that the shim APIs can accept.
    override func visit(_ node: MacroExpansionExprSyntax) -> ExprSyntax {
        let recursed = super.visit(node)
        guard let macro = recursed.as(MacroExpansionExprSyntax.self),
              macro.macroName.text == "selector" else {
            return recursed
        }
        let key = Self.selectorKey(from: macro.arguments.trimmedDescription)
        let escaped = key
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        var replacement = ExprSyntax("Selector(\"\(raw: escaped)\")")
        replacement.leadingTrivia = node.leadingTrivia
        replacement.trailingTrivia = node.trailingTrivia
        return replacement
    }

    /// Make identifiable collection `ForEach` calls explicit for the Linux
    /// compatibility toolchain. Apple's SwiftUI reliably infers
    /// `ForEach(collection)` when elements are `Identifiable`; the shim stack can
    /// lose that overload in large lowered builders and fall back to the
    /// `Range<Int>` initializer. `id: \.id` is source-equivalent for valid
    /// SwiftUI identifiable collections and keeps range forms untouched.
    override func visit(_ node: FunctionCallExprSyntax) -> ExprSyntax {
        let recursed = super.visit(node)
        guard let call = recursed.as(FunctionCallExprSyntax.self),
              let callee = call.calledExpression.as(DeclReferenceExprSyntax.self),
              callee.baseName.text == "ForEach",
              call.arguments.count == 1,
              let firstArgument = call.arguments.first,
              firstArgument.label == nil,
              call.trailingClosure != nil else {
            return recursed
        }

        let dataExpression = firstArgument.expression.trimmedDescription
        guard Self.shouldLowerIdentifiableForEachDataExpression(dataExpression) else {
            return recursed
        }

        let trailingClosure = call.trailingClosure?.description ?? ""
        let trailingClosureSeparator = trailingClosure.first?.isWhitespace == true ? "" : " "
        let additionalTrailingClosures = call.additionalTrailingClosures.description
        var replacement = ExprSyntax(
            "\(raw: call.calledExpression.trimmedDescription)(\(raw: dataExpression), id: \\.id)\(raw: trailingClosureSeparator)\(raw: trailingClosure)\(raw: additionalTrailingClosures)"
        )
        replacement.leadingTrivia = node.leadingTrivia
        replacement.trailingTrivia = node.trailingTrivia
        return replacement
    }

    /// Widen `os(macOS)` to `(os(macOS) || os(Linux))` inside `#if` condition
    /// expression trees. The rewrite only fires inside compile-config
    /// conditions, never in regular code, so we run a nested rewriter
    /// scoped to `IfConfigClauseSyntax.condition`.
    override func visit(_ node: IfConfigClauseSyntax) -> IfConfigClauseSyntax {
        let recursed = super.visit(node)
        guard let condition = recursed.condition else { return recursed }

        // Two-pass: first scan the condition tree for `os(macOS)` calls that
        // should be skipped (negated form or already-widened form), then rewrite.
        let scanner = OSMacOSSkipScanner(viewMode: .sourceAccurate)
        scanner.walk(condition)
        let widener = OSMacOSWidener(skipIDs: scanner.skipIDs)
        let rewritten = widener.rewrite(Syntax(condition))
        guard let newCondition = rewritten.as(ExprSyntax.self) else { return recursed }
        var updated = recursed
        updated.condition = newCondition
        return updated
    }

    /// Normalize a selector expression into a stable key by dropping any leading
    /// type qualifier (`Type.method(_:)` and `method(_:)` become the same key).
    private static func selectorKey(from arguments: String) -> String {
        let trimmed = arguments.trimmingCharacters(in: .whitespacesAndNewlines)
        let qualifierPath = trimmed.prefix { $0 != "(" }
        guard let lastDot = qualifierPath.range(of: ".", options: .backwards) else {
            return trimmed
        }
        return String(trimmed[trimmed.index(after: lastDot.lowerBound)...])
    }

    private static func shouldLowerIdentifiableForEachDataExpression(_ expression: String) -> Bool {
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if trimmed.contains("..<") || trimmed.contains("...") { return false }
        if trimmed.hasSuffix(".indices") { return false }
        if trimmed.first?.isNumber == true { return false }
        return true
    }

    private static func firstAttributeIsStripped(_ attributes: AttributeListSyntax) -> Bool {
        guard let first = attributes.first else { return false }
        return isStrippedAttribute(first)
    }

    private static func isStrippedAttribute(_ element: AttributeListSyntax.Element) -> Bool {
        guard case .attribute(let attr) = element else { return false }
        return strippedAttributeNames.contains(attr.attributeName.trimmedDescription)
    }

    private static func shouldPreserveMainActorBuildBlock(_ node: FunctionDeclSyntax) -> Bool {
        guard node.name.text == "buildBlock" else { return false }
        guard node.modifiers.contains(where: { $0.name.text == "static" }) else { return false }
        return node.attributes.contains { isAttribute($0, named: "MainActor") }
    }

    private static func prependingMainActor(to functionDecl: FunctionDeclSyntax) -> FunctionDeclSyntax {
        if functionDecl.attributes.contains(where: { isAttribute($0, named: "MainActor") }) {
            return functionDecl
        }

        var updated = functionDecl
        let leadingTrivia = updated.leadingTrivia
        updated = updated.with(\.leadingTrivia, [])
        let mainActorAttribute = AttributeSyntax(
            leadingTrivia: leadingTrivia,
            attributeName: IdentifierTypeSyntax(
                name: .identifier("MainActor", trailingTrivia: .space)
            )
        )
        let attributes = [AttributeListSyntax.Element.attribute(mainActorAttribute)] + Array(updated.attributes)
        updated.attributes = AttributeListSyntax(attributes)
        return updated
    }

    private static func restoreDeclLeadingTrivia(
        _ trivia: Trivia,
        to declaration: inout ClassDeclSyntax
    ) {
        if restoreLeadingTriviaToFirstAttribute(trivia, in: &declaration.attributes) { return }
        if restoreLeadingTriviaToFirstModifier(trivia, in: &declaration.modifiers) { return }
        declaration.classKeyword = declaration.classKeyword.with(\.leadingTrivia, trivia)
    }

    private static func restoreDeclLeadingTrivia(
        _ trivia: Trivia,
        to declaration: inout FunctionDeclSyntax
    ) {
        if restoreLeadingTriviaToFirstAttribute(trivia, in: &declaration.attributes) { return }
        if restoreLeadingTriviaToFirstModifier(trivia, in: &declaration.modifiers) { return }
        declaration.funcKeyword = declaration.funcKeyword.with(\.leadingTrivia, trivia)
    }

    private static func restoreDeclLeadingTrivia(
        _ trivia: Trivia,
        to declaration: inout VariableDeclSyntax
    ) {
        if restoreLeadingTriviaToFirstAttribute(trivia, in: &declaration.attributes) { return }
        if restoreLeadingTriviaToFirstModifier(trivia, in: &declaration.modifiers) { return }
        declaration.bindingSpecifier = declaration.bindingSpecifier.with(\.leadingTrivia, trivia)
    }

    private static func restoreLeadingTriviaToFirstAttribute(
        _ trivia: Trivia,
        in attributes: inout AttributeListSyntax
    ) -> Bool {
        guard let index = attributes.indices.first else { return false }
        guard case .attribute(var attribute) = attributes[index] else { return false }
        attribute.leadingTrivia = trivia
        attributes[index] = .attribute(attribute)
        return true
    }

    private static func restoreLeadingTriviaToFirstModifier(
        _ trivia: Trivia,
        in modifiers: inout DeclModifierListSyntax
    ) -> Bool {
        guard let index = modifiers.indices.first else { return false }
        var modifier = modifiers[index]
        modifier.leadingTrivia = trivia
        modifiers[index] = modifier
        return true
    }

    // MARK: Observable lowering helpers

    private static func prependQuillObservableObject(to classDecl: inout ClassDeclSyntax) {
        if var clause = classDecl.inheritanceClause {
            let alreadyHasObservableObject = clause.inheritedTypes.contains { entry in
                let type = entry.type.trimmedDescription
                return type == "ObservableObject" || type == "QuillObservableObject"
            }
            if alreadyHasObservableObject { return }

            var types = clause.inheritedTypes
            let entry = InheritedTypeSyntax(
                type: TypeSyntax(
                    IdentifierTypeSyntax(
                        name: .identifier("QuillObservableObject")
                    )
                ),
                trailingComma: .commaToken(trailingTrivia: .space)
            )
            types.insert(entry, at: types.startIndex)
            clause.inheritedTypes = types
            classDecl.inheritanceClause = clause
            return
        }

        // No existing inheritance clause — create one. Normalize surrounding
        // trivia so the inserted conformance separates cleanly from both the
        // class name and opening brace.
        let nameTrailing = classDecl.name.trailingTrivia
        classDecl.name = classDecl.name.with(\.trailingTrivia, [])

        var memberBlock = classDecl.memberBlock
        let braceLeading = memberBlock.leftBrace.leadingTrivia
        memberBlock.leftBrace = memberBlock.leftBrace.with(\.leadingTrivia, [])
        classDecl.memberBlock = memberBlock

        let combinedTail = nameTrailing + braceLeading
        let trailingForObservableObject: Trivia = combinedTail.containsNewlineOrSpace
            ? combinedTail
            : .space

        let entry = InheritedTypeSyntax(
            type: TypeSyntax(
                IdentifierTypeSyntax(
                    name: .identifier("QuillObservableObject", trailingTrivia: trailingForObservableObject)
                )
            )
        )

        classDecl.inheritanceClause = InheritanceClauseSyntax(
            colon: .colonToken(trailingTrivia: .space),
            inheritedTypes: InheritedTypeListSyntax([entry])
        )
    }

    private static func wrapEligibleStoredVars(in classDecl: inout ClassDeclSyntax) {
        var members = classDecl.memberBlock.members
        for index in members.indices {
            var member = members[index]
            guard var variable = member.decl.as(VariableDeclSyntax.self),
                  isEligibleStoredObservableVar(variable) else {
                continue
            }

            variable = prependQuillPublished(to: variable)
            member.decl = DeclSyntax(variable)
            members[index] = member
        }

        var memberBlock = classDecl.memberBlock
        memberBlock.members = members
        classDecl.memberBlock = memberBlock
    }

    private static func isEligibleStoredObservableVar(_ variable: VariableDeclSyntax) -> Bool {
        guard variable.bindingSpecifier.text == "var" else { return false }

        let alreadyPublished = variable.attributes.contains {
            isAttribute($0, named: "Published") || isAttribute($0, named: "QuillPublished")
        }
        if alreadyPublished {
            return false
        }

        if variable.modifiers.contains(where: { modifier in
            let name = modifier.name.text
            return name == "static" || name == "class" || name == "private"
        }) {
            return false
        }

        if variable.bindings.contains(where: { $0.accessorBlock != nil }) {
            return false
        }

        return true
    }

    private static func prependQuillPublished(to variable: VariableDeclSyntax) -> VariableDeclSyntax {
        let leadingTrivia = variable.leadingTrivia
        var updated = variable.with(\.leadingTrivia, [])
        let publishedAttribute = AttributeSyntax(
            leadingTrivia: leadingTrivia,
            attributeName: IdentifierTypeSyntax(
                name: .identifier("QuillPublished", trailingTrivia: .space)
            )
        )
        let attributes = [AttributeListSyntax.Element.attribute(publishedAttribute)] + Array(updated.attributes)
        updated.attributes = AttributeListSyntax(attributes)
        return updated
    }

    private static func isAttribute(_ element: AttributeListSyntax.Element, named name: String) -> Bool {
        guard case let .attribute(attribute) = element else { return false }
        return attribute.attributeName.trimmedDescription == name
    }
}

// MARK: - os(macOS) widening (nested rewriter, scoped to #if conditions)

/// Pre-scan pass that records the `os(macOS)` call IDs to leave alone:
/// those that are immediately negated (`!os(macOS)`) or already part of an
/// `os(macOS) || os(Linux)` pair. Doing this in a separate pass means the
/// rewriter doesn't have to rely on parent traversal mid-rewrite, which
/// `SyntaxRewriter` doesn't reliably support.
private final class OSMacOSSkipScanner: SyntaxVisitor {
    var skipIDs: Set<SyntaxIdentifier> = []

    override func visit(_ node: PrefixOperatorExprSyntax) -> SyntaxVisitorContinueKind {
        if node.operator.text == "!",
           let call = node.expression.as(FunctionCallExprSyntax.self),
           OSMacOSWidener.isOSMacOSCall(call) {
            skipIDs.insert(Syntax(call).id)
        }
        return .visitChildren
    }

    override func visit(_ node: InfixOperatorExprSyntax) -> SyntaxVisitorContinueKind {
        if let op = node.operator.as(BinaryOperatorExprSyntax.self),
           op.operator.text == "||",
           let left = node.leftOperand.as(FunctionCallExprSyntax.self),
           OSMacOSWidener.isOSMacOSCall(left),
           let right = node.rightOperand.as(FunctionCallExprSyntax.self),
           OSMacOSWidener.isOSCall(right, argument: "Linux") {
            skipIDs.insert(Syntax(left).id)
        }
        return .visitChildren
    }

    /// Compile-config conditions like `#if os(macOS) || os(Linux)` typically
    /// parse as `SequenceExprSyntax` (an unfolded chain of operands and
    /// operator tokens) rather than `InfixOperatorExprSyntax`. Scan the
    /// sequence for the `os(macOS) || os(Linux)` triple and skip the
    /// left-hand call so the widening pass doesn't re-wrap it.
    override func visit(_ node: SequenceExprSyntax) -> SyntaxVisitorContinueKind {
        let elements = Array(node.elements)
        guard elements.count >= 3 else { return .visitChildren }
        for i in 0...(elements.count - 3) {
            if let left = elements[i].as(FunctionCallExprSyntax.self),
               OSMacOSWidener.isOSMacOSCall(left),
               let op = elements[i + 1].as(BinaryOperatorExprSyntax.self),
               op.operator.text == "||",
               let right = elements[i + 2].as(FunctionCallExprSyntax.self),
               OSMacOSWidener.isOSCall(right, argument: "Linux") {
                skipIDs.insert(Syntax(left).id)
            }
        }
        return .visitChildren
    }
}

private final class OSMacOSWidener: SyntaxRewriter {
    private let skipIDs: Set<SyntaxIdentifier>

    init(skipIDs: Set<SyntaxIdentifier>) {
        self.skipIDs = skipIDs
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> ExprSyntax {
        guard Self.isOSMacOSCall(node) else { return ExprSyntax(super.visit(node)) }
        if skipIDs.contains(Syntax(node).id) {
            return ExprSyntax(node)
        }
        // Widen. Preserve trivia so surrounding spaces and newlines survive.
        let replacement: ExprSyntax = "(os(macOS) || os(Linux))"
        return ExprSyntax(
            replacement
                .with(\.leadingTrivia, node.leadingTrivia)
                .with(\.trailingTrivia, node.trailingTrivia)
        )
    }

    fileprivate static func isOSMacOSCall(_ call: FunctionCallExprSyntax) -> Bool {
        isOSCall(call, argument: "macOS")
    }

    fileprivate static func isOSCall(_ call: FunctionCallExprSyntax, argument expected: String) -> Bool {
        guard let calledName = call.calledExpression.as(DeclReferenceExprSyntax.self),
              calledName.baseName.text == "os" else {
            return false
        }
        guard call.arguments.count == 1, let onlyArgument = call.arguments.first else {
            return false
        }
        if let identifier = onlyArgument.expression.as(DeclReferenceExprSyntax.self),
           identifier.baseName.text == expected {
            return true
        }
        return false
    }
}

private extension Character {
    var isIdentifierContinuation: Bool {
        self == "_" || isLetter || isNumber
    }
}
