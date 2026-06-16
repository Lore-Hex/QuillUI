@_exported import Foundation
@_exported import QuillFoundation

#if os(Linux)
public enum PHAccessLevel: Sendable {
    case addOnly
    case readWrite
}

public enum PHAuthorizationStatus: Sendable {
    case notDetermined
    case restricted
    case denied
    case authorized
    case limited
}

public final class PHPhotoLibrary: @unchecked Sendable {
    public static let sharedLibrary = PHPhotoLibrary()
    public static func shared() -> PHPhotoLibrary { sharedLibrary }

    public static func authorizationStatus(for accessLevel: PHAccessLevel) -> PHAuthorizationStatus {
        _ = accessLevel
        return .authorized
    }

    @discardableResult
    public static func requestAuthorization(for accessLevel: PHAccessLevel) async -> PHAuthorizationStatus {
        _ = accessLevel
        return .authorized
    }

    public func performChanges(_ changeBlock: () -> Void) async throws {
        changeBlock()
    }
}

public final class PHObjectPlaceholder: Hashable, Sendable {
    public let localIdentifier: String

    public init(localIdentifier: String = UUID().uuidString) {
        self.localIdentifier = localIdentifier
    }

    public static func == (lhs: PHObjectPlaceholder, rhs: PHObjectPlaceholder) -> Bool {
        lhs.localIdentifier == rhs.localIdentifier
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(localIdentifier)
    }
}

public final class PHAssetCreationRequest: @unchecked Sendable {
    public let placeholderForCreatedAsset: PHObjectPlaceholder?

    private init() {
        placeholderForCreatedAsset = PHObjectPlaceholder()
    }

    @discardableResult
    public static func creationRequestForAsset(from image: UIImage) -> PHAssetCreationRequest {
        _ = image
        return PHAssetCreationRequest()
    }

    @discardableResult
    public static func creationRequestForAssetFromImage(atFileURL fileURL: URL) -> PHAssetCreationRequest? {
        _ = fileURL
        return PHAssetCreationRequest()
    }

    @discardableResult
    public static func creationRequestForAssetFromVideo(atFileURL fileURL: URL) -> PHAssetCreationRequest? {
        _ = fileURL
        return PHAssetCreationRequest()
    }
}

public enum PHAssetMediaType: Sendable {
    case unknown
    case image
    case video
    case audio
}

public final class PHFetchOptions {
    public var sortDescriptors: [NSSortDescriptor]?
    public var fetchLimit: Int = 0
    public init() {}
}

public final class PHFetchResult<ObjectType> {
    private let values: [ObjectType]
    public init(_ values: [ObjectType] = []) {
        self.values = values
    }
    public var count: Int { values.count }
    public func enumerateObjects(_ block: (ObjectType, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {
        var stop = ObjCBool(false)
        for (index, value) in values.enumerated() {
            block(value, index, &stop)
            if stop.boolValue { break }
        }
    }
}

public final class PHAsset: Hashable, Sendable {
    public let localIdentifier: String
    public let mediaType: PHAssetMediaType
    public let creationDate: Date

    public init(
        localIdentifier: String = UUID().uuidString,
        mediaType: PHAssetMediaType = .image,
        creationDate: Date = Date()
    ) {
        self.localIdentifier = localIdentifier
        self.mediaType = mediaType
        self.creationDate = creationDate
    }

    public static func fetchAssets(with mediaType: PHAssetMediaType, options: PHFetchOptions?) -> PHFetchResult<PHAsset> {
        _ = mediaType
        _ = options
        return PHFetchResult([])
    }

    public static func == (lhs: PHAsset, rhs: PHAsset) -> Bool {
        lhs.localIdentifier == rhs.localIdentifier
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(localIdentifier)
    }
}

public final class PHImageRequestOptions {
    public enum DeliveryMode: Sendable {
        case opportunistic
        case highQualityFormat
        case fastFormat
    }

    public enum ResizeMode: Sendable {
        case none
        case fast
        case exact
    }

    public var isNetworkAccessAllowed = false
    public var deliveryMode: DeliveryMode = .opportunistic
    public var resizeMode: ResizeMode = .none
    public var isSynchronous = false
    public init() {}
}

public enum PHImageContentMode: Sendable {
    case aspectFit
    case aspectFill
    case `default`
}

public final class PHImageManager: @unchecked Sendable {
    public static let shared = PHImageManager()
    public static func `default`() -> PHImageManager { shared }

    public func requestImageDataAndOrientation(
        for asset: PHAsset,
        options: PHImageRequestOptions?,
        resultHandler: @escaping (Data?, String?, UIImage.Orientation, [AnyHashable: Any]?) -> Void
    ) {
        _ = asset
        _ = options
        resultHandler(nil, nil, .up, nil)
    }

    public func requestImage(
        for asset: PHAsset,
        targetSize: CGSize,
        contentMode: PHImageContentMode,
        options: PHImageRequestOptions?,
        resultHandler: @escaping (UIImage?, [AnyHashable: Any]?) -> Void
    ) {
        _ = asset
        _ = targetSize
        _ = contentMode
        _ = options
        resultHandler(nil, nil)
    }
}

public func UIImageWriteToSavedPhotosAlbum(
    _ image: UIImage,
    _ completionTarget: Any?,
    _ completionSelector: Any?,
    _ contextInfo: UnsafeMutableRawPointer?
) {
    _ = image
    _ = completionTarget
    _ = completionSelector
    _ = contextInfo
}
#endif
