//
//  Date+Extensions.swift
//  RSCore
//
//  Created by Brent Simmons on 6/21/16.
//  Copyright © 2016 Ranchero Software, LLC. All rights reserved.
//
//  Quill bring-up: vendored verbatim from NetNewsWire's RSCore module into the
//  live RSCore clone (QuillRSCoreShim, module-aliased to `RSCore`). Foundation-
//  only — the rough (non-calendar) day/hour Date offsets RSCore source uses.
//

import Foundation

public extension Date {
	// Below are for rough use only — they don't use the calendar.

	func bySubtracting(days: Int) -> Date {
		return addingTimeInterval(0.0 - TimeInterval(days: days))
	}

	func bySubtracting(hours: Int) -> Date {
		return addingTimeInterval(0.0 - TimeInterval(hours: hours))
	}

	func byAdding(days: Int) -> Date {
		return addingTimeInterval(TimeInterval(days: days))
	}
}

nonisolated public extension TimeInterval {

	init(days: Int) {
		self.init(days * 24 * 60 * 60)
	}

	init(hours: Int) {
		self.init(hours * 60 * 60)
	}
}
