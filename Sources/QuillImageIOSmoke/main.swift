import Foundation
import ImageIO
import QuillFoundation

private func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("quill-imageio-smoke: \(message)\n".utf8))
    exit(1)
}

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fail(message)
    }
}

private func makeTestImage(width: Int = 8, height: Int = 4) -> CGImage {
    let image = CGImage()
    image.width = width
    image.height = height
    image.quillBytesPerRow = width * 4

    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    for y in 0..<height {
        for x in 0..<width {
            let offset = y * image.quillBytesPerRow + x * 4
            pixels[offset + 0] = UInt8(32 + x * 12)   // B
            pixels[offset + 1] = UInt8(80 + y * 24)   // G
            pixels[offset + 2] = 220                  // R
            pixels[offset + 3] = 255                  // A
        }
    }
    image.quillBGRAPixels = pixels
    image.quillUTType = "public.png"
    return image
}

let sourceImage = makeTestImage()
let pngData = NSMutableData()
guard let pngDestination = CGImageDestinationCreateWithData(pngData, "public.png", 1, nil) else {
    fail("could not create PNG destination")
}
CGImageDestinationAddImage(pngDestination, sourceImage, nil)
require(CGImageDestinationFinalize(pngDestination), "PNG destination did not finalize")

guard let source = CGImageSourceCreateWithData(pngData as Data, [kCGImageSourceShouldCache: false]) else {
    fail("could not create image source from encoded PNG")
}
require(CGImageSourceGetCount(source) == 1, "source count mismatch")
require(CGImageSourceGetType(source) == "public.png", "source type mismatch")

guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) else {
    fail("could not read image properties")
}
require(properties[kCGImagePropertyPixelWidth] as? Int == 8, "property width mismatch")
require(properties[kCGImagePropertyPixelHeight] as? Int == 4, "property height mismatch")
require(properties[kCGImagePropertyColorModel] as? String == kCGImagePropertyColorModelRGB, "color model mismatch")

guard let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    fail("could not decode full image")
}
require(decoded.width == 8, "decoded width mismatch")
require(decoded.height == 4, "decoded height mismatch")
require(decoded.utType == "public.png", "decoded type mismatch")
require(decoded.quillBGRAPixels?.isEmpty == false, "decoded image has no pixels")

guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(
    source,
    0,
    [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: 2,
    ]
) else {
    fail("could not create thumbnail")
}
require(thumbnail.width == 2, "thumbnail width mismatch")
require(thumbnail.height == 1, "thumbnail height mismatch")
require(thumbnail.utType == "public.png", "thumbnail type mismatch")

guard let cropped = decoded.cropping(to: CGRect(x: 2, y: 1, width: 3, height: 2)) else {
    fail("could not crop decoded image")
}
require(cropped.width == 3, "cropped width mismatch")
require(cropped.height == 2, "cropped height mismatch")
require(cropped.quillBGRAPixels?.count == 3 * 2 * 4, "cropped pixel buffer mismatch")

let jpegData = NSMutableData()
guard let jpegDestination = CGImageDestinationCreateWithData(jpegData, "public.jpeg", 1, nil) else {
    fail("could not create JPEG destination")
}
CGImageDestinationAddImage(jpegDestination, thumbnail, [kCGImageDestinationLossyCompressionQuality: 0.82])
require(CGImageDestinationFinalize(jpegDestination), "JPEG destination did not finalize")
require(Array((jpegData as Data).prefix(3)) == [0xFF, 0xD8, 0xFF], "JPEG magic mismatch")

let tempURL = FileManager.default.temporaryDirectory
    .appendingPathComponent("quill-imageio-smoke-\(UUID().uuidString)")
    .appendingPathExtension("jpg")
defer { try? FileManager.default.removeItem(at: tempURL) }
guard let urlDestination = CGImageDestinationCreateWithURL(tempURL, "public.jpeg", 1, nil) else {
    fail("could not create URL destination")
}
CGImageDestinationAddImage(urlDestination, thumbnail, nil)
require(CGImageDestinationFinalize(urlDestination), "URL destination did not finalize")
guard let urlSource = CGImageSourceCreateWithURL(tempURL, nil) else {
    fail("could not create image source from URL")
}
require(CGImageSourceGetType(urlSource) == "public.jpeg", "URL source type mismatch")

print("quill-imageio-smoke: passed")
