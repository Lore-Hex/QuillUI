//
// SignalServiceKit ObjC port for QuillOS (Track B).
//
// Two methods declared in ObjC headers and implemented in the excluded `.m`
// files (TSMessage.m / TSInfoMessage.m), so their Swift callers in
// TSMessage.swift can't resolve them on Linux:
//
//   TSMessage:     -updateWithRemotelyDeletedAndRemoveRenderableContentWithTransaction:
//                  (Swift: updateWithRemotelyDeletedAndRemoveRenderableContent(with:))
//   TSInfoMessage: -infoMessagePreviewTextWithTransaction:
//                  (Swift: infoMessagePreviewText(with:))
//
import Foundation

extension TSInfoMessage {
    // The real ObjC `-infoMessagePreviewTextWithTransaction:` forwards to the
    // Swift `_infoMessagePreviewText(tx:)` (TSInfoMessage.swift). Do the same —
    // a faithful forward (not a stub). Subclass `.m` overrides
    // (OWSUnknownProtocolVersionMessage / OWSDisappearingConfigurationUpdateInfoMessage
    // / etc.) are excluded on Linux; their specialized preview text is deferred.
    public func infoMessagePreviewText(with tx: DBReadTransaction) -> String {
        _infoMessagePreviewText(tx: tx)
    }
}

extension TSMessage {
    // Marks the message remotely-deleted and strips its renderable content. The
    // real `.m` performs an SDS update (set wasRemotelyDeleted, clear body /
    // attachments / quoted reply / etc.). Deferred on Linux (inert) until the
    // SDS mutation path is ported; this lets the remote-delete pipeline compile
    // and proceed.
    public func updateWithRemotelyDeletedAndRemoveRenderableContent(with transaction: DBWriteTransaction) {
        _ = transaction
    }
}
