//
//  AppNotifications.swift
//  NetNewsWire — vendored (subset) into QuillRSCoreShim
//
//  Created by Brent Simmons on 3/7/26.
//  Copyright © Ranchero Software, LLC. All rights reserved.
//
//  Quill bring-up: the `Notification.Name` constants from upstream RSCore's
//  AppNotifications.swift, reached by RSWeb's DownloadCache (clears itself on
//  background/low-memory). The posting-side `AppNotification` struct is not
//  vendored yet — it needs `os.Logger` and the `postOnMainThread` helper,
//  and nothing on the Linux build posts these notifications so far.
//
//  Refresh: re-copy from
//  .upstream/netnewswire/Modules/RSCore/Sources/RSCore/AppNotifications.swift
//

import Foundation

public extension Notification.Name {

	/// Posted on actual low memory condition. Main thread.
	static let lowMemory = Notification.Name("LowMemoryNotification")

	/// Posted when the app goes to background. Main thread.
	static let appDidGoToBackground = Notification.Name("AppDidGoToBackgroundNotification")
}
