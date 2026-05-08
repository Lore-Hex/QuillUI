@_exported import Foundation
@_exported import Dispatch
@_exported import QuillUI

#if os(Linux)
public extension Image {
    init(nsImage: NSImage) {
        if let data = nsImage.data {
            self.init(data: data)
        } else {
            self.init(systemName: "photo")
        }
    }
}
#endif
