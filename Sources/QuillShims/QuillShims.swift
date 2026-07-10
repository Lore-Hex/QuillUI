@_exported import QuillKit
@_exported import QuillFoundation
@_exported import QuillWebKit
@_exported import QuillUIKit
@_exported import QuillRS

#if os(Linux)
import Glibc
@_exported import CoreGraphics
@_exported import AppKit
@_exported import UIKit
@_exported import Combine
@_exported import MessageUI
@_exported import SafariServices
@_exported import MobileCoreServices
@_exported import UniformTypeIdentifiers
@_exported import Zip
@_exported import Tidemark
@_exported import KeychainSwift
@_exported import os
@_exported import NetNewsWireContext
@_exported import SearchKit
@_exported import CoreServices

public let O_EVTONLY = O_RDONLY

public func quillClosureFilter<Element>(
    _ sequence: some Sequence<Element>,
    _ isIncluded: (Element) throws -> Bool
) rethrows -> [Element] {
    var result: [Element] = []
    for element in sequence {
        if try isIncluded(element) {
            result.append(element)
        }
    }
    return result
}
#endif
