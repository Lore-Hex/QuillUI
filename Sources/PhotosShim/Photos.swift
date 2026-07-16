@_exported import Foundation
@_exported import QuillFoundation
import QuillKit

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

    private init(asset: PHAsset?) {
        placeholderForCreatedAsset = asset.map { PHObjectPlaceholder(localIdentifier: $0.localIdentifier) }
    }

    @discardableResult
    public static func creationRequestForAsset(from image: UIImage) -> PHAssetCreationRequest {
        PHAssetCreationRequest(asset: QuillPhotoLibraryStore.shared.save(image: image))
    }

    @discardableResult
    public static func creationRequestForAssetFromImage(atFileURL fileURL: URL) -> PHAssetCreationRequest? {
        PHAssetCreationRequest(asset: QuillPhotoLibraryStore.shared.saveFile(fileURL, mediaType: .image))
    }

    @discardableResult
    public static func creationRequestForAssetFromVideo(atFileURL fileURL: URL) -> PHAssetCreationRequest? {
        PHAssetCreationRequest(asset: QuillPhotoLibraryStore.shared.saveFile(fileURL, mediaType: .video))
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
    public func object(at index: Int) -> ObjectType { values[index] }
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
    let quillFileURL: URL?

    public init(
        localIdentifier: String = UUID().uuidString,
        mediaType: PHAssetMediaType = .image,
        creationDate: Date = Date()
    ) {
        self.localIdentifier = localIdentifier
        self.mediaType = mediaType
        self.creationDate = creationDate
        self.quillFileURL = nil
    }

    init(localIdentifier: String, mediaType: PHAssetMediaType, creationDate: Date, fileURL: URL) {
        self.localIdentifier = localIdentifier
        self.mediaType = mediaType
        self.creationDate = creationDate
        self.quillFileURL = fileURL
    }

    public static func fetchAssets(with mediaType: PHAssetMediaType, options: PHFetchOptions?) -> PHFetchResult<PHAsset> {
        PHFetchResult(QuillPhotoLibraryStore.shared.fetchAssets(mediaType: mediaType, options: options))
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

public typealias PHImageRequestID = Int32

public final class PHImageManager: @unchecked Sendable {
    public static let shared = PHImageManager()
    public static func `default`() -> PHImageManager { shared }

    private let lock = NSLock()
    private var nextRequestID: PHImageRequestID = 1

    private func makeRequestID() -> PHImageRequestID {
        lock.withLock {
            defer {
                nextRequestID = nextRequestID == .max ? 1 : nextRequestID + 1
            }
            return nextRequestID
        }
    }

    @discardableResult
    public func requestImageDataAndOrientation(
        for asset: PHAsset,
        options: PHImageRequestOptions?,
        resultHandler: @escaping (Data?, String?, UIImage.Orientation, [AnyHashable: Any]?) -> Void
    ) -> PHImageRequestID {
        let requestID = makeRequestID()
        _ = options
        guard let fileURL = asset.quillFileURL, let data = try? Data(contentsOf: fileURL) else {
            resultHandler(nil, nil, .up, nil)
            return requestID
        }
        let type = QuillBitmapImageCodec.utType(forPathExtension: fileURL.pathExtension)
        QuillPhotoLibraryStore.record(
            operation: "photos.requestImageData",
            severity: .info,
            message: "Loaded photo asset data for \(asset.localIdentifier)."
        )
        resultHandler(data, type, .up, nil)
        return requestID
    }

    @discardableResult
    public func requestImage(
        for asset: PHAsset,
        targetSize: CGSize,
        contentMode: PHImageContentMode,
        options: PHImageRequestOptions?,
        resultHandler: @escaping (UIImage?, [AnyHashable: Any]?) -> Void
    ) -> PHImageRequestID {
        let requestID = makeRequestID()
        _ = contentMode
        _ = options
        guard
            let fileURL = asset.quillFileURL,
            let data = try? Data(contentsOf: fileURL),
            let image = UIImage(data: data)
        else {
            resultHandler(nil, nil)
            return requestID
        }

        if targetSize.width > 0,
           targetSize.height > 0,
           let cgImage = image.cgImage,
           let resized = QuillBitmapImageCodec.resized(cgImage, to: targetSize) {
            QuillPhotoLibraryStore.record(
                operation: "photos.requestImage",
                severity: .info,
                message: "Loaded resized photo asset image for \(asset.localIdentifier)."
            )
            resultHandler(UIImage(cgImage: resized, scale: image.scale, orientation: image.imageOrientation), nil)
        } else {
            QuillPhotoLibraryStore.record(
                operation: "photos.requestImage",
                severity: .info,
                message: "Loaded photo asset image for \(asset.localIdentifier)."
            )
            resultHandler(image, nil)
        }
        return requestID
    }

    public func cancelImageRequest(_ requestID: PHImageRequestID) {
        _ = requestID
    }
}

public func UIImageWriteToSavedPhotosAlbum(
    _ image: UIImage,
    _ completionTarget: Any?,
    _ completionSelector: Any?,
    _ contextInfo: UnsafeMutableRawPointer?
) {
    _ = QuillPhotoLibraryStore.shared.save(image: image)
    _ = completionTarget
    _ = completionSelector
    _ = contextInfo
}

private final class QuillPhotoLibraryStore: @unchecked Sendable {
    static let shared = QuillPhotoLibraryStore()

    private let lock = NSLock()
    private var testingDirectory: URL?

    private init() {}

    var libraryDirectory: URL {
        lock.withLock {
            if let testingDirectory {
                return testingDirectory
            }
            if let configured = ProcessInfo.processInfo.environment["QUILL_PHOTO_LIBRARY_DIR"],
               !configured.isEmpty {
                return URL(fileURLWithPath: configured, isDirectory: true)
            }
            return FileManager.default
                .homeDirectoryForCurrentUser
                .appendingPathComponent(".local/share/QuillUI/Photos", isDirectory: true)
        }
    }

    func setTestingDirectory(_ directory: URL?) {
        lock.withLock {
            testingDirectory = directory
        }
    }

    func save(image: UIImage) -> PHAsset? {
        guard let data = image.pngData() ?? image.jpegData(compressionQuality: 0.92) ?? image.data else {
            Self.record(
                operation: "photos.saveImage",
                severity: .unsupported,
                message: "Photo image save failed because no encodable image data was available."
            )
            return nil
        }
        return save(data: data, preferredExtension: "png", mediaType: .image)
    }

    func saveFile(_ fileURL: URL, mediaType: PHAssetMediaType) -> PHAsset? {
        guard let data = try? Data(contentsOf: fileURL) else {
            Self.record(
                operation: "photos.saveFile",
                severity: .unsupported,
                message: "Photo library could not read \(fileURL.path)."
            )
            return nil
        }
        let preferredExtension = fileURL.pathExtension.isEmpty
            ? defaultExtension(for: mediaType)
            : fileURL.pathExtension
        return save(data: data, preferredExtension: preferredExtension, mediaType: mediaType)
    }

    func fetchAssets(mediaType: PHAssetMediaType, options: PHFetchOptions?) -> [PHAsset] {
        let directory = libraryDirectory
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var assets = urls.compactMap { asset(from: $0) }
        if mediaType != .unknown {
            assets = assets.filter { $0.mediaType == mediaType }
        }

        let descending = options?.sortDescriptors?.first?.ascending == false
        assets.sort {
            descending ? $0.creationDate > $1.creationDate : $0.creationDate < $1.creationDate
        }

        if let limit = options?.fetchLimit, limit > 0, assets.count > limit {
            assets = Array(assets.prefix(limit))
        }

        Self.record(
            operation: "photos.fetchAssets",
            severity: .info,
            message: "Fetched \(assets.count) local photo asset(s)."
        )
        return assets
    }

    private func save(data: Data, preferredExtension: String, mediaType: PHAssetMediaType) -> PHAsset? {
        let directory = libraryDirectory
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let id = UUID().uuidString
            let sanitizedExtension = preferredExtension.isEmpty ? defaultExtension(for: mediaType) : preferredExtension
            let fileURL = directory.appendingPathComponent("\(Int(Date().timeIntervalSince1970 * 1000))-\(id)")
                .appendingPathExtension(sanitizedExtension)
            try data.write(to: fileURL, options: [.atomic])
            let asset = PHAsset(
                localIdentifier: id,
                mediaType: mediaType,
                creationDate: Date(),
                fileURL: fileURL
            )
            Self.record(
                operation: mediaType == .video ? "photos.saveVideo" : "photos.saveImage",
                severity: .info,
                message: "Saved local photo asset \(asset.localIdentifier) to \(fileURL.path)."
            )
            return asset
        } catch {
            Self.record(
                operation: mediaType == .video ? "photos.saveVideo" : "photos.saveImage",
                severity: .unsupported,
                message: "Photo library save failed: \(error.localizedDescription)"
            )
            return nil
        }
    }

    private func asset(from fileURL: URL) -> PHAsset? {
        let mediaType = mediaType(for: fileURL)
        guard mediaType != .unknown else { return nil }
        let values = try? fileURL.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        let date = values?.creationDate ?? values?.contentModificationDate ?? Date.distantPast
        let name = fileURL.deletingPathExtension().lastPathComponent
        let id = name.split(separator: "-").last.map(String.init) ?? name
        return PHAsset(localIdentifier: id, mediaType: mediaType, creationDate: date, fileURL: fileURL)
    }

    private func mediaType(for fileURL: URL) -> PHAssetMediaType {
        switch fileURL.pathExtension.lowercased() {
        case "png", "jpg", "jpeg", "jpe", "gif", "tif", "tiff", "webp", "bmp":
            return .image
        case "mov", "mp4", "m4v", "webm":
            return .video
        case "mp3", "m4a", "wav", "aac", "flac", "ogg":
            return .audio
        default:
            return .unknown
        }
    }

    private func defaultExtension(for mediaType: PHAssetMediaType) -> String {
        switch mediaType {
        case .image, .unknown: return "png"
        case .video: return "mov"
        case .audio: return "m4a"
        }
    }

    static func record(operation: String, severity: QuillCompatibilityEvent.Severity, message: String) {
        QuillCompatibilityDiagnostics.shared.record(
            subsystem: "Photos",
            operation: operation,
            severity: severity,
            message: message
        )
    }
}

public extension PHPhotoLibrary {
    static func quillUseLibraryDirectoryForTesting(_ directory: URL?) {
        QuillPhotoLibraryStore.shared.setTestingDirectory(directory)
    }
}
#endif
