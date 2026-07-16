import Foundation
import Photos
import QuillKit
import UIKit

private func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("quill-photos-smoke: \(message)\n".utf8))
    exit(1)
}

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fail(message)
    }
}

@main
private struct QuillPhotosSmoke {
    static func main() async throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("quill-photos-smoke-\(UUID().uuidString)", isDirectory: true)
        PHPhotoLibrary.quillUseLibraryDirectoryForTesting(temporaryDirectory)
        defer {
            PHPhotoLibrary.quillUseLibraryDirectoryForTesting(nil)
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        QuillCompatibilityDiagnostics.shared.clear()

        let image = UIGraphicsImageRenderer(size: CGSize(width: 3, height: 2)).image { _ in
            UIColor(red: 1, green: 0, blue: 0, alpha: 1).setFill()
            UIRectFill(CGRect(x: 0, y: 0, width: 3, height: 2))
        }
        guard let pixels = image.cgImage?.quillBGRAPixels else {
            fail("renderer produced no pixels")
        }
        require(pixels[2] > 240, "renderer red channel mismatch")

        require(PHPhotoLibrary.authorizationStatus(for: .addOnly) == .authorized, "add authorization mismatch")
        let authorization = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        require(authorization == .authorized, "read-write authorization mismatch")

        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)

        let options = PHFetchOptions()
        options.fetchLimit = 10
        let fetched = PHAsset.fetchAssets(with: .image, options: options)
        require(fetched.count == 1, "expected one saved asset")

        let asset = fetched.object(at: 0)
        require(asset.mediaType == .image, "saved asset media type mismatch")

        var loadedData: Data?
        var loadedType: String?
        var loadedOrientation: UIImage.Orientation?
        let dataRequestID = PHImageManager.default().requestImageDataAndOrientation(for: asset, options: nil) {
            data,
            type,
            orientation,
            _ in
            loadedData = data
            loadedType = type
            loadedOrientation = orientation
        }
        require(dataRequestID > 0, "image data request id mismatch")
        guard let loadedData else {
            fail("image data request returned nil")
        }
        require(Array(loadedData.prefix(4)) == [0x89, 0x50, 0x4E, 0x47], "loaded PNG magic mismatch")
        require(loadedType == "public.png", "loaded type mismatch")
        require(loadedOrientation == .up, "loaded orientation mismatch")

        var loadedImage: UIImage?
        let imageRequestID = PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: 1, height: 1),
            contentMode: .aspectFit,
            options: nil
        ) { image, _ in
            loadedImage = image
        }
        require(imageRequestID > dataRequestID, "image request id did not advance")
        require(loadedImage?.size == CGSize(width: 1, height: 1), "loaded thumbnail size mismatch")
        require(loadedImage?.cgImage?.quillBGRAPixels?.isEmpty == false, "loaded thumbnail has no pixels")
        PHImageManager.default().cancelImageRequest(imageRequestID)

        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.creationRequestForAsset(from: image)
            require(request.placeholderForCreatedAsset != nil, "created asset placeholder missing")
        }
        require(PHAsset.fetchAssets(with: .image, options: nil).count == 2, "performChanges asset count mismatch")

        let operations = Set(QuillCompatibilityDiagnostics.shared.events.map(\.operation))
        require(operations.contains("photos.saveImage"), "missing saveImage diagnostic")
        require(operations.contains("photos.fetchAssets"), "missing fetchAssets diagnostic")
        require(operations.contains("photos.requestImageData"), "missing requestImageData diagnostic")
        require(operations.contains("photos.requestImage"), "missing requestImage diagnostic")

        print("quill-photos-smoke: passed")
    }
}
