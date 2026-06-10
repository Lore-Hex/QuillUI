import Foundation
import CoreFoundation
@_exported import CoreMedia
@_exported import CoreVideo
@_exported import QuillFoundation

public let kVTCouldNotFindVideoEncoderErr: OSStatus = -12908
public let kVTProfileLevel_HEVC_Main_AutoLevel: String = "HEVC_Main_AutoLevel"

public func VTIsHardwareDecodeSupported(_ codecType: CMVideoCodecType) -> Bool {
    _ = codecType
    return false
}

public func VTCreateCGImageFromCVPixelBuffer(
    _ pixelBuffer: CVPixelBuffer,
    options: CFDictionary?,
    imageOut: inout CGImage?
) -> OSStatus {
    _ = (pixelBuffer, options)
    imageOut = nil
    return noErr
}

public func VTCopySupportedPropertyDictionaryForEncoder(
    width: Int32,
    height: Int32,
    codecType: CMVideoCodecType,
    encoderSpecification: CFDictionary?,
    encoderIDOut: UnsafeMutablePointer<CFString?>?,
    supportedPropertiesOut: UnsafeMutablePointer<CFDictionary?>?
) -> OSStatus {
    _ = (width, height, codecType, encoderSpecification)
    encoderIDOut?.pointee = nil
    supportedPropertiesOut?.pointee = nil
    return kVTCouldNotFindVideoEncoderErr
}
