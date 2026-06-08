//
//  Data+RSCore.swift
//  NetNewsWire — vendored subset into QuillRSCoreShim
//
//  Copyright © Ranchero Software, LLC. All rights reserved.
//
//  Quill bring-up: the Foundation-only `Data.isProbablyHTML` heuristic (+ its
//  private `RSSearch` byte-pattern table) from upstream RSCore's
//  Data+RSCore.swift. Real NetNewsWire FeedFinder.find() uses it to decide
//  whether a fetched response is an HTML page worth scanning for feed links.
//  Upstream RSCore doesn't build on Linux (AppKit/UIKit/os + RSCoreObjC), so
//  this shim mirrors only the reached surface. The image/hex/other Data helpers
//  in the upstream file are not vendored (not yet reached).
//
//  Refresh: re-copy from
//  .upstream/netnewswire/Modules/RSCore/Sources/RSCore/Data+RSCore.swift
//

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
	///
	/// Advantage is taken of the fact that most common encodings are ASCII-compatible, aside from UTF-16,
	/// which for ASCII codepoints is essentially ASCII characters with nulls in between.
	///
	/// An uncommon exception is any EBCDIC-derived encoding.
	///
	/// This method uses detection algorithm that doesn't require both html and body tags.
	/// It looks for DOCTYPE declarations, html tags, and common HTML structural elements.
	var isProbablyHTML: Bool {
		if !self.contains(RSSearch.lessThan) || !self.contains(RSSearch.greaterThan) {
			return false
		}

		// Check for DOCTYPE declaration (strong indicator)
		if self.range(of: RSSearch.UTF8.lowercaseDoctype) != nil || self.range(of: RSSearch.UTF8.uppercaseDoctype) != nil {
			return true
		}

		if self.range(of: RSSearch.UTF16.lowercaseDoctype) != nil || self.range(of: RSSearch.UTF16.uppercaseDoctype) != nil {
			return true
		}

		// Check for html tag (strong indicator)
		if self.range(of: RSSearch.UTF8.lowercaseHTML) != nil || self.range(of: RSSearch.UTF8.uppercaseHTML) != nil {
			return true
		}

		if self.range(of: RSSearch.UTF16.lowercaseHTML) != nil || self.range(of: RSSearch.UTF16.uppercaseHTML) != nil {
			return true
		}

		// Check for head tag (strong indicator)
		if self.range(of: RSSearch.UTF8.lowercaseHead) != nil || self.range(of: RSSearch.UTF8.uppercaseHead) != nil {
			return true
		}

		if self.range(of: RSSearch.UTF16.lowercaseHead) != nil || self.range(of: RSSearch.UTF16.uppercaseHead) != nil {
			return true
		}

		// Check for body tag (good indicator)
		if self.range(of: RSSearch.UTF8.lowercaseBody) != nil || self.range(of: RSSearch.UTF8.uppercaseBody) != nil {
			return true
		}

		if self.range(of: RSSearch.UTF16.lowercaseBody) != nil || self.range(of: RSSearch.UTF16.uppercaseBody) != nil {
			return true
		}

		// Check for common HTML structural elements (weaker but still useful indicators)
		let hasCommonHTMLElements = {
			// Check for div tags
			if self.range(of: RSSearch.UTF8.lowercaseDiv) != nil || self.range(of: RSSearch.UTF8.uppercaseDiv) != nil ||
			   self.range(of: RSSearch.UTF16.lowercaseDiv) != nil || self.range(of: RSSearch.UTF16.uppercaseDiv) != nil {
				return true
			}

			// Check for p tags
			if self.range(of: RSSearch.UTF8.lowercaseP) != nil || self.range(of: RSSearch.UTF8.uppercaseP) != nil ||
			   self.range(of: RSSearch.UTF16.lowercaseP) != nil || self.range(of: RSSearch.UTF16.uppercaseP) != nil {
				return true
			}

			// Check for span tags
			if self.range(of: RSSearch.UTF8.lowercaseSpan) != nil || self.range(of: RSSearch.UTF8.uppercaseSpan) != nil ||
			   self.range(of: RSSearch.UTF16.lowercaseSpan) != nil || self.range(of: RSSearch.UTF16.uppercaseSpan) != nil {
				return true
			}

			return false
		}()

		return hasCommonHTMLElements
	}
}
