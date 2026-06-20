//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//
// Faithful Swift port of SignalUI's `LinkPreviewCallLink`, which is absent from
// the Linux upstream checkout but referenced by LinkPreviewView/TextAttachmentView.
// Linked into <SignalUI>/QuillPort/ by scripts/quill-signal-lower-ui.sh (step 4)
// so it compiles inside the SignalUI module and can see LinkPreviewState,
// LinkPreviewImageState, ConversationStyle, CallLink, OWSLinkPreviewDraft, etc.
//
// Models the call-link link-preview state: it carries an `OWSLinkPreviewDraft`
// (the parsed signal.link/call URL) plus the decoded `CallLink`, and reports
// `isCallLink == true`. The rendering path (`configureAsCallLinkPreview`) reads
// `title`, `displayDomain`, and `date`; it draws its own call-link iconography
// and subtitle (`CallStrings.callLinkDescription`), so this state only needs to
// surface the draft's display metadata faithfully.
//

import UIKit
import Foundation

public import SignalServiceKit

public class LinkPreviewCallLink: LinkPreviewState {

    public enum PreviewType {
        case draft(OWSLinkPreviewDraft)
        case sent(OWSLinkPreview, ConversationStyle)
    }

    public let previewType: PreviewType
    public let callLink: CallLink

    public init(previewType: PreviewType, callLink: CallLink) {
        self.previewType = previewType
        self.callLink = callLink
    }

    private var draft: OWSLinkPreviewDraft? {
        switch previewType {
        case .draft(let draft):
            return draft
        case .sent:
            return nil
        }
    }

    private var sentPreview: OWSLinkPreview? {
        switch previewType {
        case .draft:
            return nil
        case .sent(let linkPreview, _):
            return linkPreview
        }
    }

    public var isLoaded: Bool { true }

    public var urlString: String? {
        // Prefer the draft's URL string; fall back to the canonical call-link URL.
        draft?.urlString ?? sentPreview?.urlString ?? callLink.url().absoluteString
    }

    public var displayDomain: String? {
        guard let urlString else { return nil }
        return URL(string: urlString).flatMap(LinkPreviewHelper.displayDomain(forUrl:))
    }

    public var title: String? {
        // A call link has no server-resolved title in the draft preview; use the
        // draft title if one was provided, otherwise the localized call-link name.
        if let title = draft?.title?.nilIfEmpty ?? sentPreview?.title?.nilIfEmpty {
            return title
        }
        return OWSLocalizedString(
            "CALL_LINK_DEFAULT_TITLE",
            comment: "Default title for a Signal call link with no custom name."
        )
    }

    public var imageState: LinkPreviewImageState { .none }

    public func imageAsync(thumbnailQuality: AttachmentThumbnailQuality, completion: @escaping (UIImage) -> Void) {
        owsFailDebug("Should not be called.")
    }

    public func imageCacheKey(thumbnailQuality: AttachmentThumbnailQuality) -> LinkPreviewImageCacheKey? {
        owsFailDebug("Should not be called.")
        return nil
    }

    public var imagePixelSize: CGSize { .zero }

    public var previewDescription: String? { draft?.previewDescription ?? sentPreview?.previewDescription }

    public var date: Date? { draft?.date ?? sentPreview?.date }

    public var isGroupInviteLink: Bool { false }

    public var isCallLink: Bool { true }

    public var conversationStyle: ConversationStyle? {
        switch previewType {
        case .draft:
            return nil
        case .sent(_, let conversationStyle):
            return conversationStyle
        }
    }
}
