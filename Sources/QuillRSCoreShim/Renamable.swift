//
//  Renamable.swift
//  RSCore
//
//  Created by Brent Simmons on 11/22/18.
//  Copyright © 2018 Ranchero Software, LLC. All rights reserved.
//
//  Quill bring-up: vendored verbatim from NetNewsWire's RSCore module into the
//  live RSCore clone (QuillRSCoreShim, module-aliased to `RSCore`). Foundation-
//  only. This is the rename protocol the Account model types (Feed / Folder)
//  conform to, vendored ahead of the model classes that import `RSCore`.
//

import Foundation

/// For anything that can be renamed by the user.
@MainActor public protocol Renamable {

	/// Renames an object.
	/// - Parameters:
	///   - to: The new name for the object.
	///   - completion: A block called when the renaming completes or fails.
	///   - result: The result of the renaming.
	func rename(to: String, completion: @escaping (_ result: Result<Void, Error>) -> Void)
}
