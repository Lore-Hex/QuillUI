//
//  OPMLRepresentable.swift
//  DataModel
//
//  Created by Brent Simmons on 7/1/17.
//  Copyright © 2017 Ranchero Software, LLC. All rights reserved.
//
//  Quill bring-up: vendored verbatim from NetNewsWire's RSCore module into the
//  live RSCore clone (QuillRSCoreShim, module-aliased to `RSCore`). Foundation-
//  only protocol for objects that can render themselves as OPML (used by feeds/
//  folders for export). Compiles unchanged on macOS and Linux.
//

import Foundation

@MainActor public protocol OPMLRepresentable {

	func OPMLString(indentLevel: Int, allowCustomAttributes: Bool) -> String
}

public extension OPMLRepresentable {

	func OPMLString(indentLevel: Int) -> String {
		OPMLString(indentLevel: indentLevel, allowCustomAttributes: false)
	}
}
