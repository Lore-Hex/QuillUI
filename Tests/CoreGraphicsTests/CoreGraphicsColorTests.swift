import CoreGraphics
import Testing

struct CoreGraphicsColorTests {
    @Test("CGColorSpace models and CGColor components match RGB and gray spaces")
    func colorSpaceModelsAndColorComponents() throws {
        let rgb = CGColorSpaceCreateDeviceRGB()
        #expect(rgb.model == .rgb)
        #expect(rgb.numberOfComponents == 3)
        #expect(CGColorSpaceCreateDeviceRGB() == rgb)

        let gray = CGColorSpaceCreateDeviceGray()
        #expect(gray.model == .monochrome)
        #expect(gray.numberOfComponents == 1)
        #expect(CGColorSpaceCreateDeviceGray() == gray)
        #expect(CGColorSpaceCreateDeviceGray() != rgb)

        let displayP3 = try #require(CGColorSpace(name: CGColorSpace.displayP3))
        #expect(displayP3.name == CGColorSpace.displayP3)
        #expect(displayP3.model == .rgb)
        #expect(displayP3.numberOfComponents == 3)

        let rgbComponents: [CGFloat] = [0.1, 0.2, 0.3, 0.4]
        let rgbColor = rgbComponents.withUnsafeBufferPointer { buffer -> CGColor? in
            guard let baseAddress = buffer.baseAddress else {
                return nil
            }
            return CGColor(colorSpace: rgb, components: baseAddress)
        }
        let unwrappedRGB = try #require(rgbColor)
        #expect(unwrappedRGB.colorSpace == rgb)
        #expect(unwrappedRGB.components == rgbComponents)
        #expect(unwrappedRGB.numberOfComponents == 4)
        #expect(unwrappedRGB.alpha == 0.4)

        let grayComponents: [CGFloat] = [0.25, 0.75]
        let grayColor = grayComponents.withUnsafeBufferPointer { buffer -> CGColor? in
            guard let baseAddress = buffer.baseAddress else {
                return nil
            }
            return CGColor(colorSpace: gray, components: baseAddress)
        }
        let unwrappedGray = try #require(grayColor)
        #expect(unwrappedGray.colorSpace == gray)
        #expect(unwrappedGray.components == grayComponents)
        #expect(unwrappedGray.numberOfComponents == 2)
        #expect(unwrappedGray.alpha == 0.75)

        let convenienceGray = CGColor(gray: 0.2, alpha: 0.6)
        #expect(convenienceGray.colorSpace?.model == .monochrome)
        #expect(convenienceGray.components == [0.2, 0.6])
        #expect(convenienceGray.alpha == 0.6)
    }
}
