// Vendored from upstream Ranchero-Software/NetNewsWire
// Modules/RSCore/Sources/RSCore/Data+RSCore.swift verbatim —
// the `isProbablyHTML` byte-scan used by FeedFinder + RSWeb to
// route between feed parsers and HTML metadata extraction. Pure
// Foundation, identical output bytes to upstream so feed-format
// dispatch behaves the same regardless of which side
// (vendored shim or upstream RSCore) is in the build.

import Foundation

public extension Data {

    /// Constants for `isProbablyHTML`.
    private enum RSSearch {
        static let lessThan = "<".utf8.first!
        static let greaterThan = ">".utf8.first!

        /// Tags in UTF-8/ASCII format.
        enum UTF8 {
            static let lowercaseHTML = Data("html".utf8)
            static let lowercaseBody = Data("body".utf8)
            static let uppercaseHTML = Data("HTML".utf8)
            static let uppercaseBody = Data("BODY".utf8)
            static let lowercaseHead = Data("head".utf8)
            static let uppercaseHead = Data("HEAD".utf8)
            static let lowercaseDoctype = Data("<!doctype".utf8)
            static let uppercaseDoctype = Data("<!DOCTYPE".utf8)
            static let lowercaseDiv = Data("div".utf8)
            static let uppercaseDiv = Data("DIV".utf8)
            static let lowercaseP = Data("p".utf8)
            static let uppercaseP = Data("P".utf8)
            static let lowercaseSpan = Data("span".utf8)
            static let uppercaseSpan = Data("SPAN".utf8)
        }

        /// Tags in UTF-16 format.
        enum UTF16 {
            static let lowercaseHTML = "html".data(using: .utf16LittleEndian)!
            static let lowercaseBody = "body".data(using: .utf16LittleEndian)!
            static let uppercaseHTML = "HTML".data(using: .utf16LittleEndian)!
            static let uppercaseBody = "BODY".data(using: .utf16LittleEndian)!
            static let lowercaseHead = "head".data(using: .utf16LittleEndian)!
            static let uppercaseHead = "HEAD".data(using: .utf16LittleEndian)!
            static let lowercaseDoctype = "<!doctype".data(using: .utf16LittleEndian)!
            static let uppercaseDoctype = "<!DOCTYPE".data(using: .utf16LittleEndian)!
            static let lowercaseDiv = "div".data(using: .utf16LittleEndian)!
            static let uppercaseDiv = "DIV".data(using: .utf16LittleEndian)!
            static let lowercaseP = "p".data(using: .utf16LittleEndian)!
            static let uppercaseP = "P".data(using: .utf16LittleEndian)!
            static let lowercaseSpan = "span".data(using: .utf16LittleEndian)!
            static let uppercaseSpan = "SPAN".data(using: .utf16LittleEndian)!
        }
    }

    /// Returns `true` if the data looks like it could be HTML.
    /// Verbatim port of upstream RSCore's heuristic — matches
    /// DOCTYPE declarations, html/head/body tags, and common
    /// structural elements, in both UTF-8 and UTF-16LE byte
    /// patterns.
    var isProbablyHTML: Bool {
        if !self.contains(RSSearch.lessThan) || !self.contains(RSSearch.greaterThan) {
            return false
        }
        // DOCTYPE declaration (strong indicator)
        if self.range(of: RSSearch.UTF8.lowercaseDoctype) != nil || self.range(of: RSSearch.UTF8.uppercaseDoctype) != nil {
            return true
        }
        if self.range(of: RSSearch.UTF16.lowercaseDoctype) != nil || self.range(of: RSSearch.UTF16.uppercaseDoctype) != nil {
            return true
        }
        // html tag
        if self.range(of: RSSearch.UTF8.lowercaseHTML) != nil || self.range(of: RSSearch.UTF8.uppercaseHTML) != nil {
            return true
        }
        if self.range(of: RSSearch.UTF16.lowercaseHTML) != nil || self.range(of: RSSearch.UTF16.uppercaseHTML) != nil {
            return true
        }
        // head tag
        if self.range(of: RSSearch.UTF8.lowercaseHead) != nil || self.range(of: RSSearch.UTF8.uppercaseHead) != nil {
            return true
        }
        if self.range(of: RSSearch.UTF16.lowercaseHead) != nil || self.range(of: RSSearch.UTF16.uppercaseHead) != nil {
            return true
        }
        // body tag
        if self.range(of: RSSearch.UTF8.lowercaseBody) != nil || self.range(of: RSSearch.UTF8.uppercaseBody) != nil {
            return true
        }
        if self.range(of: RSSearch.UTF16.lowercaseBody) != nil || self.range(of: RSSearch.UTF16.uppercaseBody) != nil {
            return true
        }
        // Common HTML structural elements (weaker but still useful).
        let hasCommonHTMLElements: () -> Bool = {
            // div
            if self.range(of: RSSearch.UTF8.lowercaseDiv) != nil || self.range(of: RSSearch.UTF8.uppercaseDiv) != nil ||
               self.range(of: RSSearch.UTF16.lowercaseDiv) != nil || self.range(of: RSSearch.UTF16.uppercaseDiv) != nil {
                return true
            }
            // p
            if self.range(of: RSSearch.UTF8.lowercaseP) != nil || self.range(of: RSSearch.UTF8.uppercaseP) != nil ||
               self.range(of: RSSearch.UTF16.lowercaseP) != nil || self.range(of: RSSearch.UTF16.uppercaseP) != nil {
                return true
            }
            // span
            if self.range(of: RSSearch.UTF8.lowercaseSpan) != nil || self.range(of: RSSearch.UTF8.uppercaseSpan) != nil ||
               self.range(of: RSSearch.UTF16.lowercaseSpan) != nil || self.range(of: RSSearch.UTF16.uppercaseSpan) != nil {
                return true
            }
            return false
        }
        return hasCommonHTMLElements()
    }
}
