//
// SignalServiceKit ObjC port for QuillOS (Track B).
//
// Signal-iOS uses `Data.WritingOptions.atomicWrite` at a few call sites
// (AudioWaveform, AudioWaveformManagerImpl, AttachmentContentValidatorImpl).
// That is the older/odd spelling of the option. Apple Foundation and
// swift-corelibs-foundation both expose the canonical `.atomic` (write to a
// temporary file and atomically rename into place), but corelibs does NOT vend
// the `.atomicWrite` alias. This faithful shim adds `.atomicWrite` as a static
// alias for the real `.atomic`, so the call sites compile unchanged with
// identical write semantics.
//
import Foundation

#if os(Linux)
public extension Data.WritingOptions {
    /// Legacy spelling used by Signal-iOS; aliases corelibs' canonical `.atomic`
    /// (write to a temp file, then atomically rename into place).
    static var atomicWrite: Data.WritingOptions { .atomic }
}
#endif
