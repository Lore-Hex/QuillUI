//
// QuillUI Linux shim for Apple's `AudioToolbox` framework.
//
// SignalServiceKit's `Sounds` plays short notification/ringtone clips via the
// AudioServices system-sound API. There is no Linux audio backend wired up yet,
// so this is INERT: a sound "registers" successfully (so callers don't log a
// failure) but is given a placeholder id, and play is a no-op -- i.e. sounds
// silently do not play. Real playback needs a Linux audio backend (PipeWire /
// ALSA). HONEST STATUS: notification sounds are silent on Linux.
//
import Foundation
import CoreFoundation
import QuillKit

/// Re-exported so AudioToolbox consumers (Telegram's AudioRecorder and
/// audio-queue callers) see the OSStatus the audio APIs return without
/// leaking the whole CoreFoundation module.
public typealias OSStatus = CoreFoundation.OSStatus

public typealias SystemSoundID = UInt32
/// On Apple platforms `AudioServicesCreateSystemSoundID` takes a CFURL and
/// callers write `url as CFURL` (toll-free bridging). corelibs has no
/// URL→CFURL bridge, so model CFURL as URL itself — the cast becomes an
/// identity upcast and the shim function takes the URL directly
/// (IceCubes' SoundEffectManager is the first consumer).
public typealias CFURL = URL
public typealias AudioFormatID = UInt32
public typealias AudioFormatFlags = UInt32
public typealias AudioChannelLayoutTag = UInt32
public typealias AudioUnit = AudioComponentInstance
public typealias AudioComponent = OpaquePointer
public typealias AudioComponentInstance = OpaquePointer
public typealias AudioConverterRef = OpaquePointer
public typealias AUGraph = OpaquePointer
public typealias AUNode = Int32
public typealias AudioDeviceID = UInt32
public typealias AudioObjectID = UInt32
public typealias AudioObjectPropertySelector = UInt32
public typealias AudioObjectPropertyScope = UInt32
public typealias AudioObjectPropertyElement = UInt32
public typealias AudioUnitPropertyID = UInt32
public typealias AudioUnitScope = UInt32
public typealias AudioUnitElement = UInt32
public typealias AudioUnitParameterID = UInt32
public typealias AudioUnitRenderActionFlags = UInt32

public let kAudioFormatLinearPCM: AudioFormatID = 0x6c70_636d // "lpcm"
public let kAudioFormatFlagIsSignedInteger: AudioFormatFlags = 1 << 2
public let kAudioFormatFlagIsPacked: AudioFormatFlags = 1 << 3
public let kAudioFormatFlagsNativeEndian: AudioFormatFlags = 0
public let kAudioChannelLayoutTag_Mono: AudioChannelLayoutTag = 0x0064_0001
public let kAudioUnitErr_FailedInitialization: OSStatus = -10875
public let kAudioFileInvalidFileError: OSStatus = -43
public let kAudioFileStreamError_InvalidFile: OSStatus = -43

public let kAudioUnitType_Output: UInt32 = 0x6175_6f75 // "auou"
public let kAudioUnitType_FormatConverter: UInt32 = 0x6175_6663 // "aufc"
public let kAudioUnitSubType_HALOutput: UInt32 = 0x6168_616c // "ahal"
public let kAudioUnitSubType_AUConverter: UInt32 = 0x636f_6e76 // "conv"
public let kAudioUnitSubType_AUiPodTimeOther: UInt32 = 0x6970_746f // "ipto"
public let kAudioUnitManufacturer_Apple: UInt32 = 0x6170_706c // "appl"

public let kAudioUnitScope_Global: AudioUnitScope = 0
public let kAudioUnitScope_Input: AudioUnitScope = 1
public let kAudioUnitScope_Output: AudioUnitScope = 2
public let kAudioOutputUnitProperty_EnableIO: AudioUnitPropertyID = 2003
public let kAudioOutputUnitProperty_CurrentDevice: AudioUnitPropertyID = 2000
public let kAudioOutputUnitProperty_SetInputCallback: AudioUnitPropertyID = 2005
public let kAudioUnitProperty_StreamFormat: AudioUnitPropertyID = 8
public let kAudioUnitProperty_ShouldAllocateBuffer: AudioUnitPropertyID = 51
public let kAudioUnitProperty_MaximumFramesPerSlice: AudioUnitPropertyID = 14
public let kTimePitchParam_Rate: AudioUnitParameterID = 0
public let kHALOutputParam_Volume: AudioUnitParameterID = 14

public let kAudioObjectSystemObject: AudioObjectID = 1
public let kAudioHardwarePropertyDefaultOutputDevice: AudioObjectPropertySelector = 0x646f_7574 // "dout"
public let kAudioHardwarePropertyDefaultInputDevice: AudioObjectPropertySelector = 0x6469_6e20 // "din "
public let kAudioDevicePropertyStreamFormat: AudioObjectPropertySelector = 0x7366_6d74 // "sfmt"
public let kAudioDevicePropertyAvailableNominalSampleRates: AudioObjectPropertySelector = 0x6e73_723f // "nsr?"
public let kAudioDevicePropertyNominalSampleRate: AudioObjectPropertySelector = 0x6e73_7274 // "nsrt"
public let kAudioObjectPropertyScopeGlobal: AudioObjectPropertyScope = 0x676c_6f62 // "glob"
public let kAudioObjectPropertyScopeOutput: AudioObjectPropertyScope = 0x6f75_7470 // "outp"
public let kAudioObjectPropertyElementMaster: AudioObjectPropertyElement = 0

public struct AudioStreamBasicDescription: Sendable {
    public var mSampleRate: Float64
    public var mFormatID: AudioFormatID
    public var mFormatFlags: AudioFormatFlags
    public var mBytesPerPacket: UInt32
    public var mFramesPerPacket: UInt32
    public var mBytesPerFrame: UInt32
    public var mChannelsPerFrame: UInt32
    public var mBitsPerChannel: UInt32
    public var mReserved: UInt32

    public init(
        mSampleRate: Float64 = 0,
        mFormatID: AudioFormatID = 0,
        mFormatFlags: AudioFormatFlags = 0,
        mBytesPerPacket: UInt32 = 0,
        mFramesPerPacket: UInt32 = 0,
        mBytesPerFrame: UInt32 = 0,
        mChannelsPerFrame: UInt32 = 0,
        mBitsPerChannel: UInt32 = 0,
        mReserved: UInt32 = 0
    ) {
        self.mSampleRate = mSampleRate
        self.mFormatID = mFormatID
        self.mFormatFlags = mFormatFlags
        self.mBytesPerPacket = mBytesPerPacket
        self.mFramesPerPacket = mFramesPerPacket
        self.mBytesPerFrame = mBytesPerFrame
        self.mChannelsPerFrame = mChannelsPerFrame
        self.mBitsPerChannel = mBitsPerChannel
        self.mReserved = mReserved
    }
}

public struct AudioChannelDescription: Sendable {
    public var mChannelLabel: UInt32
    public var mChannelFlags: UInt32
    public var mCoordinates: (Float32, Float32, Float32)

    public init(mChannelLabel: UInt32 = 0, mChannelFlags: UInt32 = 0, mCoordinates: (Float32, Float32, Float32) = (0, 0, 0)) {
        self.mChannelLabel = mChannelLabel
        self.mChannelFlags = mChannelFlags
        self.mCoordinates = mCoordinates
    }
}

public struct AudioChannelLayout: Sendable {
    public var mChannelLayoutTag: AudioChannelLayoutTag
    public var mChannelBitmap: UInt32
    public var mNumberChannelDescriptions: UInt32

    public init(
        mChannelLayoutTag: AudioChannelLayoutTag = 0,
        mChannelBitmap: UInt32 = 0,
        mNumberChannelDescriptions: UInt32 = 0
    ) {
        self.mChannelLayoutTag = mChannelLayoutTag
        self.mChannelBitmap = mChannelBitmap
        self.mNumberChannelDescriptions = mNumberChannelDescriptions
    }
}

public struct AudioBuffer {
    public var mNumberChannels: UInt32
    public var mDataByteSize: UInt32
    public var mData: UnsafeMutableRawPointer?

    public init(mNumberChannels: UInt32 = 0, mDataByteSize: UInt32 = 0, mData: UnsafeMutableRawPointer? = nil) {
        self.mNumberChannels = mNumberChannels
        self.mDataByteSize = mDataByteSize
        self.mData = mData
    }
}

public struct AudioBufferList {
    public var mNumberBuffers: UInt32
    public var mBuffers: AudioBuffer

    public init(mNumberBuffers: UInt32 = 0, mBuffers: AudioBuffer = AudioBuffer()) {
        self.mNumberBuffers = mNumberBuffers
        self.mBuffers = mBuffers
    }
}

public struct UnsafeMutableAudioBufferListPointer: RandomAccessCollection, MutableCollection {
    public typealias Index = Int
    private let base: UnsafeMutablePointer<AudioBufferList>?

    public init(_ base: UnsafeMutablePointer<AudioBufferList>?) {
        self.base = base
    }

    public var startIndex: Int { 0 }
    public var endIndex: Int { count }
    public var count: Int { Int(base?.pointee.mNumberBuffers ?? 0) }

    public subscript(position: Int) -> AudioBuffer {
        get {
            precondition(position == 0, "AudioBufferList shim stores one inline buffer")
            return base?.pointee.mBuffers ?? AudioBuffer()
        }
        set {
            precondition(position == 0, "AudioBufferList shim stores one inline buffer")
            base?.pointee.mBuffers = newValue
        }
    }
}

public struct AudioStreamPacketDescription: Sendable {
    public var mStartOffset: Int64
    public var mVariableFramesInPacket: UInt32
    public var mDataByteSize: UInt32

    public init(mStartOffset: Int64 = 0, mVariableFramesInPacket: UInt32 = 0, mDataByteSize: UInt32 = 0) {
        self.mStartOffset = mStartOffset
        self.mVariableFramesInPacket = mVariableFramesInPacket
        self.mDataByteSize = mDataByteSize
    }
}

public struct AudioTimeStamp: Sendable {
    public var mSampleTime: Float64
    public var mHostTime: UInt64
    public var mRateScalar: Float64
    public var mWordClockTime: UInt64
    public var mSMPTETime: UInt64
    public var mFlags: UInt32
    public var mReserved: UInt32

    public init(
        mSampleTime: Float64 = 0,
        mHostTime: UInt64 = 0,
        mRateScalar: Float64 = 0,
        mWordClockTime: UInt64 = 0,
        mSMPTETime: UInt64 = 0,
        mFlags: UInt32 = 0,
        mReserved: UInt32 = 0
    ) {
        self.mSampleTime = mSampleTime
        self.mHostTime = mHostTime
        self.mRateScalar = mRateScalar
        self.mWordClockTime = mWordClockTime
        self.mSMPTETime = mSMPTETime
        self.mFlags = mFlags
        self.mReserved = mReserved
    }
}

public struct AudioComponentDescription: Sendable {
    public var componentType: UInt32
    public var componentSubType: UInt32
    public var componentManufacturer: UInt32
    public var componentFlags: UInt32
    public var componentFlagsMask: UInt32

    public init(componentType: UInt32 = 0, componentSubType: UInt32 = 0, componentManufacturer: UInt32 = 0, componentFlags: UInt32 = 0, componentFlagsMask: UInt32 = 0) {
        self.componentType = componentType
        self.componentSubType = componentSubType
        self.componentManufacturer = componentManufacturer
        self.componentFlags = componentFlags
        self.componentFlagsMask = componentFlagsMask
    }
}

public struct AURenderCallbackStruct {
    public var inputProc: AURenderCallback?
    public var inputProcRefCon: UnsafeMutableRawPointer?

    public init(inputProc: AURenderCallback? = nil, inputProcRefCon: UnsafeMutableRawPointer? = nil) {
        self.inputProc = inputProc
        self.inputProcRefCon = inputProcRefCon
    }
}

public typealias AURenderCallback = (
    UnsafeMutableRawPointer,
    UnsafeMutablePointer<AudioUnitRenderActionFlags>,
    UnsafePointer<AudioTimeStamp>,
    UInt32,
    UInt32,
    UnsafeMutablePointer<AudioBufferList>?
) -> OSStatus

public struct AudioObjectPropertyAddress: Sendable {
    public var mSelector: AudioObjectPropertySelector
    public var mScope: AudioObjectPropertyScope
    public var mElement: AudioObjectPropertyElement

    public init(mSelector: AudioObjectPropertySelector = 0, mScope: AudioObjectPropertyScope = 0, mElement: AudioObjectPropertyElement = 0) {
        self.mSelector = mSelector
        self.mScope = mScope
        self.mElement = mElement
    }
}

public struct AudioValueRange: Sendable {
    public var mMinimum: Float64
    public var mMaximum: Float64

    public init(mMinimum: Float64 = 48000, mMaximum: Float64 = 48000) {
        self.mMinimum = mMinimum
        self.mMaximum = mMaximum
    }
}

public typealias AudioObjectPropertyListenerProc = (
    AudioObjectID,
    UInt32,
    UnsafePointer<AudioObjectPropertyAddress>,
    UnsafeMutableRawPointer?
) -> OSStatus

/// `kAudioServicesNoError` is `OSStatus` (Int32) on Apple. Typed Int32 here so we
/// don't depend on whether swift-corelibs exposes `OSStatus`.
public let kAudioServicesNoError: Int32 = 0
public let kSystemSoundID_Vibrate: SystemSoundID = 0x0000_0FFF

@discardableResult
public func AudioServicesCreateSystemSoundID(
    _ inFileURL: URL,
    _ outSystemSoundID: UnsafeMutablePointer<SystemSoundID>
) -> Int32 {
    outSystemSoundID.pointee = QuillAudioPlayerService.shared.createSystemSoundID(url: inFileURL)
    return kAudioServicesNoError
}

@discardableResult
public func AudioServicesDisposeSystemSoundID(_ inSystemSoundID: SystemSoundID) -> Int32 {
    QuillAudioPlayerService.shared.disposeSystemSoundID(inSystemSoundID)
    return kAudioServicesNoError
}

public func AudioServicesPlaySystemSound(_ inSystemSoundID: SystemSoundID) {
    QuillAudioPlayerService.shared.playSystemSound(inSystemSoundID)
}

public func AudioServicesPlayAlertSound(_ inSystemSoundID: SystemSoundID) {
    QuillAudioPlayerService.shared.playSystemSound(inSystemSoundID, alert: true)
}

public func AudioServicesAddSystemSoundCompletion(
    _ inSystemSoundID: SystemSoundID,
    _ inRunLoop: CFRunLoop?,
    _ inRunLoopMode: CoreFoundation.CFString?,
    _ inCompletionRoutine: @convention(c) (SystemSoundID, UnsafeMutableRawPointer?) -> Void,
    _ inClientData: UnsafeMutableRawPointer?
) -> Int32 {
    QuillAudioPlayerService.shared.addSystemSoundCompletion(inSystemSoundID)
    return kAudioServicesNoError
}

public func AudioServicesRemoveSystemSoundCompletion(_ inSystemSoundID: SystemSoundID) {
    QuillAudioPlayerService.shared.removeSystemSoundCompletion(inSystemSoundID)
}

@discardableResult
public func AudioConverterNew(
    _ inSourceFormat: UnsafePointer<AudioStreamBasicDescription>,
    _ inDestinationFormat: UnsafePointer<AudioStreamBasicDescription>,
    _ outAudioConverter: UnsafeMutablePointer<AudioConverterRef?>
) -> OSStatus {
    _ = (inSourceFormat, inDestinationFormat)
    outAudioConverter.pointee = OpaquePointer(bitPattern: 0xA11D10)
    return kAudioServicesNoError
}

public typealias AudioConverterComplexInputDataProc = (
    AudioConverterRef,
    UnsafeMutablePointer<UInt32>,
    UnsafeMutablePointer<AudioBufferList>,
    UnsafeMutablePointer<UnsafeMutablePointer<AudioStreamPacketDescription>?>?,
    UnsafeMutableRawPointer?
) -> OSStatus

@discardableResult
public func AudioConverterFillComplexBuffer(
    _ inAudioConverter: AudioConverterRef,
    _ inInputDataProc: AudioConverterComplexInputDataProc,
    _ inInputDataProcUserData: UnsafeMutableRawPointer?,
    _ ioOutputDataPacketSize: UnsafeMutablePointer<UInt32>,
    _ outOutputData: UnsafeMutablePointer<AudioBufferList>,
    _ outPacketDescription: UnsafeMutablePointer<AudioStreamPacketDescription>?
) -> OSStatus {
    _ = (inAudioConverter, inInputDataProc, inInputDataProcUserData, outOutputData, outPacketDescription)
    ioOutputDataPacketSize.pointee = 0
    return kAudioServicesNoError
}

@discardableResult
public func AudioConverterDispose(_ inAudioConverter: AudioConverterRef) -> OSStatus {
    _ = inAudioConverter
    return kAudioServicesNoError
}

public func AudioComponentFindNext(_ inComponent: AudioComponent?, _ inDesc: UnsafePointer<AudioComponentDescription>) -> AudioComponent? {
    _ = (inComponent, inDesc)
    return OpaquePointer(bitPattern: 0xA11D11)
}

@discardableResult
public func AudioComponentInstanceNew(_ inComponent: AudioComponent, _ outInstance: UnsafeMutablePointer<AudioComponentInstance?>) -> OSStatus {
    _ = inComponent
    outInstance.pointee = OpaquePointer(bitPattern: 0xA11D12)
    return kAudioServicesNoError
}

@discardableResult
public func AudioComponentInstanceDispose(_ inInstance: AudioComponentInstance) -> OSStatus {
    _ = inInstance
    return kAudioServicesNoError
}

@discardableResult
public func AudioUnitSetProperty(
    _ inUnit: AudioUnit,
    _ inID: AudioUnitPropertyID,
    _ inScope: AudioUnitScope,
    _ inElement: AudioUnitElement,
    _ inData: UnsafeRawPointer,
    _ inDataSize: UInt32
) -> OSStatus {
    _ = (inUnit, inID, inScope, inElement, inData, inDataSize)
    return kAudioServicesNoError
}

@discardableResult
public func AudioUnitSetParameter(
    _ inUnit: AudioUnit,
    _ inID: AudioUnitParameterID,
    _ inScope: AudioUnitScope,
    _ inElement: AudioUnitElement,
    _ inValue: Float32,
    _ inBufferOffsetInFrames: UInt32
) -> OSStatus {
    _ = (inUnit, inID, inScope, inElement, inValue, inBufferOffsetInFrames)
    return kAudioServicesNoError
}

@discardableResult
public func AudioUnitInitialize(_ inUnit: AudioUnit) -> OSStatus {
    _ = inUnit
    return kAudioServicesNoError
}

@discardableResult
public func AudioUnitUninitialize(_ inUnit: AudioUnit) -> OSStatus {
    _ = inUnit
    return kAudioServicesNoError
}

@discardableResult
public func AudioUnitRender(
    _ inUnit: AudioUnit,
    _ ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
    _ inTimeStamp: UnsafePointer<AudioTimeStamp>,
    _ inOutputBusNumber: UInt32,
    _ inNumberFrames: UInt32,
    _ ioData: UnsafeMutablePointer<AudioBufferList>
) -> OSStatus {
    _ = (inUnit, ioActionFlags, inTimeStamp, inOutputBusNumber, inNumberFrames, ioData)
    return kAudioServicesNoError
}

@discardableResult
public func AudioOutputUnitStart(_ ci: AudioUnit) -> OSStatus {
    _ = ci
    return kAudioServicesNoError
}

@discardableResult
public func AudioOutputUnitStop(_ ci: AudioUnit) -> OSStatus {
    _ = ci
    return kAudioServicesNoError
}

@discardableResult
public func NewAUGraph(_ outGraph: UnsafeMutablePointer<AUGraph?>) -> OSStatus {
    outGraph.pointee = OpaquePointer(bitPattern: 0xA116A9)
    return kAudioServicesNoError
}

@discardableResult
public func AUGraphAddNode(_ inGraph: AUGraph, _ inDescription: UnsafePointer<AudioComponentDescription>, _ outNode: UnsafeMutablePointer<AUNode>) -> OSStatus {
    _ = (inGraph, inDescription)
    outNode.pointee += 1
    return kAudioServicesNoError
}

@discardableResult
public func AUGraphOpen(_ inGraph: AUGraph) -> OSStatus {
    _ = inGraph
    return kAudioServicesNoError
}

@discardableResult
public func AUGraphConnectNodeInput(_ inGraph: AUGraph, _ inSourceNode: AUNode, _ inSourceOutputNumber: UInt32, _ inDestNode: AUNode, _ inDestInputNumber: UInt32) -> OSStatus {
    _ = (inGraph, inSourceNode, inSourceOutputNumber, inDestNode, inDestInputNumber)
    return kAudioServicesNoError
}

@discardableResult
public func AUGraphNodeInfo(_ inGraph: AUGraph, _ inNode: AUNode, _ outDescription: UnsafeMutablePointer<AudioComponentDescription>?, _ outAudioUnit: UnsafeMutablePointer<AudioComponentInstance?>?) -> OSStatus {
    _ = (inGraph, inNode, outDescription)
    outAudioUnit?.pointee = OpaquePointer(bitPattern: 0xA11D13)
    return kAudioServicesNoError
}

@discardableResult
public func AUGraphSetNodeInputCallback(_ inGraph: AUGraph, _ inDestNode: AUNode, _ inDestInputNumber: UInt32, _ inInputCallback: UnsafePointer<AURenderCallbackStruct>) -> OSStatus {
    _ = (inGraph, inDestNode, inDestInputNumber, inInputCallback)
    return kAudioServicesNoError
}

@discardableResult
public func AUGraphInitialize(_ inGraph: AUGraph) -> OSStatus {
    _ = inGraph
    return kAudioServicesNoError
}

@discardableResult
public func AUGraphStart(_ inGraph: AUGraph) -> OSStatus {
    _ = inGraph
    return kAudioServicesNoError
}

@discardableResult
public func AUGraphStop(_ inGraph: AUGraph) -> OSStatus {
    _ = inGraph
    return kAudioServicesNoError
}

@discardableResult
public func AUGraphUninitialize(_ inGraph: AUGraph) -> OSStatus {
    _ = inGraph
    return kAudioServicesNoError
}

@discardableResult
public func AUGraphClose(_ inGraph: AUGraph) -> OSStatus {
    _ = inGraph
    return kAudioServicesNoError
}

@discardableResult
public func DisposeAUGraph(_ inGraph: AUGraph) -> OSStatus {
    _ = inGraph
    return kAudioServicesNoError
}

@discardableResult
public func AudioObjectGetPropertyDataSize(
    _ inObjectID: AudioObjectID,
    _ inAddress: UnsafePointer<AudioObjectPropertyAddress>,
    _ inQualifierDataSize: UInt32,
    _ inQualifierData: UnsafeRawPointer?,
    _ outDataSize: UnsafeMutablePointer<UInt32>
) -> OSStatus {
    _ = (inObjectID, inAddress, inQualifierDataSize, inQualifierData)
    outDataSize.pointee = UInt32(MemoryLayout<AudioValueRange>.stride * 2)
    return kAudioServicesNoError
}

@discardableResult
public func AudioObjectGetPropertyData(
    _ inObjectID: AudioObjectID,
    _ inAddress: UnsafePointer<AudioObjectPropertyAddress>,
    _ inQualifierDataSize: UInt32,
    _ inQualifierData: UnsafeRawPointer?,
    _ ioDataSize: UnsafeMutablePointer<UInt32>,
    _ outData: UnsafeMutableRawPointer
) -> OSStatus {
    _ = (inObjectID, inQualifierDataSize, inQualifierData)
    if inAddress.pointee.mSelector == kAudioHardwarePropertyDefaultInputDevice || inAddress.pointee.mSelector == kAudioHardwarePropertyDefaultOutputDevice {
        outData.assumingMemoryBound(to: AudioDeviceID.self).pointee = 1
        ioDataSize.pointee = UInt32(MemoryLayout<AudioDeviceID>.size)
    }
    return kAudioServicesNoError
}

@discardableResult
public func AudioObjectSetPropertyData(
    _ inObjectID: AudioObjectID,
    _ inAddress: UnsafePointer<AudioObjectPropertyAddress>,
    _ inQualifierDataSize: UInt32,
    _ inQualifierData: UnsafeRawPointer?,
    _ inDataSize: UInt32,
    _ inData: UnsafeRawPointer
) -> OSStatus {
    _ = (inObjectID, inAddress, inQualifierDataSize, inQualifierData, inDataSize, inData)
    return kAudioServicesNoError
}

@discardableResult
public func AudioObjectAddPropertyListener(
    _ inObjectID: AudioObjectID,
    _ inAddress: UnsafePointer<AudioObjectPropertyAddress>,
    _ inListener: AudioObjectPropertyListenerProc,
    _ inClientData: UnsafeMutableRawPointer?
) -> OSStatus {
    _ = (inObjectID, inAddress, inListener, inClientData)
    return kAudioServicesNoError
}

@discardableResult
public func AudioObjectRemovePropertyListener(
    _ inObjectID: AudioObjectID,
    _ inAddress: UnsafePointer<AudioObjectPropertyAddress>,
    _ inListener: AudioObjectPropertyListenerProc,
    _ inClientData: UnsafeMutableRawPointer?
) -> OSStatus {
    _ = (inObjectID, inAddress, inListener, inClientData)
    return kAudioServicesNoError
}
