//
//  SpecialCases.swift
//  RSWeb
//
//  Created by Brent Simmons on 12/12/24.
//
//  Quill bring-up: ONLY the `localeForLowercasing` global is vendored verbatim
//  from RSWeb's SpecialCases.swift. The rest of that file (the `SpecialCase`
//  domain matching + the Bundle.main-force-unwrapping `UserAgent.extendedUserAgent`
//  + url.host()-based URL/Set extensions) is deferred as test-hostile on Linux.
//  URL+RSWeb needs only this locale for its case-insensitive scheme comparison.
//

import Foundation

nonisolated public let localeForLowercasing = Locale(identifier: "en_US")
