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

    // Marks a view-once message complete and strips its renderable content (body
    // / attachments). Declared in TSMessage.h, implemented in the excluded
    // TSMessage.m, so its Swift caller (ViewOnceMessages.completeIfNecessary)
    // can't resolve it on Linux. Like updateWithRemotelyDeleted above, the real
    // `.m` does an SDS update; deferred (inert) until that mutation path is
    // ported. View-once completion runs only with a real linked account (paused).
    public func updateWithViewOnceCompleteAndRemoveRenderableContent(with transaction: DBWriteTransaction) {
        _ = transaction
    }
}

extension TSIncomingMessage {
    // -markAsViewedAtTimestamp:thread:circumstance:transaction: from
    // TSIncomingMessage.h, implemented in the excluded TSIncomingMessage.m
    // (Swift: markAsViewed(atTimestamp:thread:circumstance:transaction:)). The
    // real `.m` SDS-updates `viewed = YES` and notifies receiptManager
    // (messageWasViewed:). Deferred (inert) on Linux until the SDS-mutation +
    // receipt path is ported; the view/read pipeline runs only with a real
    // linked account (paused). Lets ViewOnceMessages.sendSyncMessage compile.
    public func markAsViewed(
        atTimestamp viewedTimestamp: UInt64,
        thread: TSThread,
        circumstance: OWSReceiptCircumstance,
        transaction: DBWriteTransaction
    ) {
        _ = viewedTimestamp
        _ = thread
        _ = circumstance
        _ = transaction
    }
}
