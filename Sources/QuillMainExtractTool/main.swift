// QuillMainExtractTool
// ====================
// Reads a Swift source file with an `@main`-attributed type and emits a
// copy with that type's full declaration removed. All other top-level
// declarations — extensions, helper types, free constants — are
// preserved verbatim. Default-internal `extension` declarations are
// promoted to `public` so cross-module visibility matches the
// single-module visibility upstream's source assumes.
//
// Implementation note: hand-rolled brace matching rather than
// SwiftSyntax to keep the tool's transitive deps minimal (SwiftSyntax
// pulls in compiler internals and tangles with sqlite-data's macro
// host). For the narrow grammar `@main` files use, brace counting is
// sufficient and stable.
//
// Invocation (from QuillMainExtractPlugin):
//   QuillMainExtractTool --output <out>.swift <input>.swift

import Foundation

func usage() -> Never {
    FileHandle.standardError.write(Data(
        "usage: QuillMainExtractTool --output <out>.swift <input>.swift\n".utf8
    ))
    exit(2)
}

var outputPath: String?
var inputPath: String?
var i = 1
while i < CommandLine.arguments.count {
    let arg = CommandLine.arguments[i]
    if arg == "--output", i + 1 < CommandLine.arguments.count {
        outputPath = CommandLine.arguments[i + 1]
        i += 2
    } else {
        inputPath = arg
        i += 1
    }
}
guard let outputPath, let inputPath else { usage() }

let sourceText: String
do {
    sourceText = try String(contentsOfFile: inputPath, encoding: .utf8)
} catch {
    FileHandle.standardError.write(Data("failed to read \(inputPath): \(error)\n".utf8))
    exit(1)
}

// MARK: - Strip `@main`-attributed type
//
// Find the `@main` token, walk past attributes/modifiers to the first
// `struct|class|actor` keyword, then to its opening `{`, then scan
// brace-by-brace until the matching `}`. Replace that whole span with
// a comment. Naively handles `{` / `}` in string literals, comments,
// and characters — for `@main` files (which are usually a thin App
// shell) this is conservative enough.

func stripMain(_ text: String) -> String {
    var out = text
    while let mainRange = out.range(of: #"(^|\n)([ \t]*)@main\b"#, options: .regularExpression) {
        // Advance past the `@main` token.
        var cursor = mainRange.upperBound
        // Skip whitespace / newlines and any other attributes /
        // access-control modifiers until we hit `struct|class|actor`.
        let typeKeywords: Set<String> = ["struct", "class", "actor"]
        var declStart = cursor
        var foundKeyword = false
        while cursor < out.endIndex {
            // Eat one identifier-or-attribute-like token at a time.
            // Skip whitespace.
            while cursor < out.endIndex, out[cursor].isWhitespace {
                cursor = out.index(after: cursor)
            }
            // Read a word (sequence of identifier chars).
            let wordStart = cursor
            while cursor < out.endIndex,
                  out[cursor].isLetter || out[cursor].isNumber || out[cursor] == "_" {
                cursor = out.index(after: cursor)
            }
            let word = String(out[wordStart..<cursor])
            if typeKeywords.contains(word) {
                declStart = wordStart
                foundKeyword = true
                break
            }
            if word.isEmpty {
                // Could be `@`-prefixed attribute; just advance one char.
                if cursor < out.endIndex {
                    cursor = out.index(after: cursor)
                } else { break }
            }
        }
        guard foundKeyword else {
            // Couldn't find the type keyword; bail on this match.
            // Just remove the @main token to avoid an infinite loop.
            out.replaceSubrange(mainRange, with: "")
            continue
        }
        // From declStart, find the first `{`, then match braces.
        guard let braceOpen = out.range(of: "{", range: declStart..<out.endIndex) else {
            out.replaceSubrange(mainRange, with: "")
            continue
        }
        var depth = 1
        var idx = out.index(after: braceOpen.lowerBound)
        while idx < out.endIndex && depth > 0 {
            let ch = out[idx]
            if ch == "{" { depth += 1 }
            else if ch == "}" { depth -= 1 }
            idx = out.index(after: idx)
        }
        // Span: from the leading whitespace before `@main` to the closing
        // `}`. Include the optional trailing newline so we don't leave a
        // dangling blank line.
        var spanStart = mainRange.lowerBound
        // Preserve a leading newline if present (mainRange started just
        // before `@main` on a line, optionally including a `\n`).
        if mainRange.lowerBound != out.startIndex,
           out[mainRange.lowerBound] == "\n" {
            spanStart = out.index(after: mainRange.lowerBound)
        }
        var spanEnd = idx
        if spanEnd < out.endIndex, out[spanEnd] == "\n" {
            spanEnd = out.index(after: spanEnd)
        }
        let replacement = "// @main type stripped by QuillMainExtractTool\n"
        out.replaceSubrange(spanStart..<spanEnd, with: replacement)
    }
    return out
}

// MARK: - Promote default-internal `extension` to `public extension`

func promoteExtensions(_ text: String) -> String {
    // Match line-leading `extension <Type>` not preceded by an explicit
    // access modifier on the same logical declaration. The pattern is
    // anchored at line start (with optional indent) so we don't promote
    // nested `extension` keywords inside string literals.
    let pattern = #"(?m)^([ \t]*)extension\b"#
    let replacement = "$1public extension"
    guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
        return text
    }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    return regex.stringByReplacingMatches(
        in: text, options: [], range: range, withTemplate: replacement
    )
}

let stripped = promoteExtensions(stripMain(sourceText))

let header = """
// Generated by QuillMainExtractTool from \(inputPath).
// Do not edit. The original file's `@main`-attributed type has been
// removed; default-internal extensions are promoted to public so
// cross-module visibility matches upstream's single-module assumption.


"""

let result = header + stripped

let outputURL = URL(fileURLWithPath: outputPath)
try? FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
do {
    try result.write(to: outputURL, atomically: true, encoding: .utf8)
} catch {
    FileHandle.standardError.write(Data("failed to write \(outputPath): \(error)\n".utf8))
    exit(1)
}
