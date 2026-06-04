//
//  FileManager+RSCore.swift
//  RSCore
//
//  Created by Nate Weaver on 2020-01-02.
//  Copyright © 2020 Ranchero Software, LLC. All rights reserved.
//
//  Quill bring-up: vendored verbatim from NetNewsWire's RSCore module into the
//  live RSCore clone (QuillRSCoreShim, module-aliased to `RSCore`). Foundation-
//  only folder helpers (isFolder / filenames / filePaths) — FileManager and the
//  URL resource-value APIs used here are present in swift-corelibs-foundation,
//  so it compiles unchanged on macOS and Linux.
//

import Foundation

public extension FileManager {
	/// Returns whether a path refers to a folder.
	///
	/// - Parameter path: The file path to check.
	///
	/// - Returns: `true` if the path refers to a folder; otherwise `false`.

	func isFolder(atPath path: String) -> Bool {
		let url = URL(fileURLWithPath: path)

		if let values = try? url.resourceValues(forKeys: [.isDirectoryKey]) {
			return values.isDirectory ?? false
		}

		return false
	}

	/// Retrieve the names of files contained in a folder.
	///
	/// - Parameter folder: The path to the folder whose contents to retrieve.
	///
	/// - Returns: An array containing the names of files in `folder`, an empty
	///   array if `folder` does not refer to a folder, or `nil` if an error occurs.
	func filenames(inFolder folder: String) -> [String]? {
		assert(isFolder(atPath: folder))

		guard isFolder(atPath: folder) else {
			return []
		}

		return try? self.contentsOfDirectory(atPath: folder)
	}

	/// Retrieve the full paths of files contained in a folder.
	///
	/// - Parameter folder: The path to the folder whose contents to retrieve.
	///
	/// - Returns: An array containing the full paths of files in `folder`,
	///   an empty array if `folder` does not refer to a folder, or `nil` if an error occurs.
	func filePaths(inFolder folder: String) -> [String]? {
		guard let filenames = self.filenames(inFolder: folder) else {
			return nil
		}

		let url = URL(fileURLWithPath: folder)
		return filenames.map { url.appendingPathComponent($0).path }
	}
}
