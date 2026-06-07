//
// SignalServiceKit IndexPath(row:section:) convenience for QuillOS (Track B).
//
// IndexPath(row:section:) is a UIKit addition (UIKit indexes a table/collection
// view as [section, row]); swift-corelibs Foundation's IndexPath has only the
// generic init(indexes:) / init(index:), not row:section: (verified via 1-file
// swiftc). CollectionDifference+SSK builds IndexPaths for diff offsets and
// imports only Foundation, so the convenience lives in a same-module port (linked
// via quill-signal-link-ports) -- visible to SSK without an import. On Apple the
// real SignalServiceKit + UIKit are used, so this file is Linux-only (the port
// dir is only added to the Linux SSK target).
//
import Foundation

extension IndexPath {
    init(row: Int, section: Int) {
        // UIKit's ordering: section is the outer index, row the inner one.
        self.init(indexes: [section, row])
    }
}
