//
//  DisplayNameProviderProtocol.swift
//  DataModel
//
//  Created by Brent Simmons on 7/28/16.
//  Copyright © 2016 Ranchero Software, LLC. All rights reserved.
//
//  Quill bring-up: vendored verbatim from NetNewsWire's RSCore module into the
//  live RSCore clone (QuillRSCoreShim, module-aliased to `RSCore`). Foundation-
//  only, so it compiles unchanged on macOS and Linux. This is the display-name
//  protocol the Account model types (SidebarItem / Feed / Folder / Account)
//  conform to, vendored ahead of the model classes that import `RSCore`.
//

import Foundation

extension Notification.Name {
	public static let DisplayNameDidChange = Notification.Name("DisplayNameDidChange")
}

/// A type that provides a name for display to the user.

@MainActor public protocol DisplayNameProvider {
	var nameForDisplay: String { get }
}

public extension DisplayNameProvider {

	func postDisplayNameDidChangeNotification() {
		NotificationCenter.default.post(name: .DisplayNameDidChange, object: self, userInfo: nil)
	}
}
