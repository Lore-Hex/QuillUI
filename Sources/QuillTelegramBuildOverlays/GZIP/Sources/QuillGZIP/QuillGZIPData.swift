@_exported import CGZIP
import Foundation

public func TGGUnzipData(_ data: Data, _ sizeLimit: Int) -> Data? {
    guard data.count <= sizeLimit || sizeLimit == 0 else {
        return nil
    }
    return data
}

public func TGGZipData(_ data: Data, _ level: Float) -> Data? {
    _ = level
    return data
}
