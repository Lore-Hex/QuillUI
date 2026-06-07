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

public typealias SystemSoundID = UInt32

/// `kAudioServicesNoError` is `OSStatus` (Int32) on Apple. Typed Int32 here so we
/// don't depend on whether swift-corelibs exposes `OSStatus`.
public let kAudioServicesNoError: Int32 = 0
public let kSystemSoundID_Vibrate: SystemSoundID = 0x0000_0FFF

/// Inert: registers a placeholder sound id and reports success, so the caller's
/// `kAudioServicesNoError == ...` guard passes and playback is simply a no-op.
@discardableResult
public func AudioServicesCreateSystemSoundID(
    _ inFileURL: URL,
    _ outSystemSoundID: UnsafeMutablePointer<SystemSoundID>
) -> Int32 {
    outSystemSoundID.pointee = 1
    return kAudioServicesNoError
}

@discardableResult
public func AudioServicesDisposeSystemSoundID(_ inSystemSoundID: SystemSoundID) -> Int32 {
    kAudioServicesNoError
}

/// Playback no-ops (nothing is audible on Linux yet).
public func AudioServicesPlaySystemSound(_ inSystemSoundID: SystemSoundID) {}
public func AudioServicesPlayAlertSound(_ inSystemSoundID: SystemSoundID) {}

public func AudioServicesAddSystemSoundCompletion(
    _ inSystemSoundID: SystemSoundID,
    _ inRunLoop: CFRunLoop?,
    _ inRunLoopMode: CFString?,
    _ inCompletionRoutine: @convention(c) (SystemSoundID, UnsafeMutableRawPointer?) -> Void,
    _ inClientData: UnsafeMutableRawPointer?
) -> Int32 {
    kAudioServicesNoError
}

public func AudioServicesRemoveSystemSoundCompletion(_ inSystemSoundID: SystemSoundID) {}
