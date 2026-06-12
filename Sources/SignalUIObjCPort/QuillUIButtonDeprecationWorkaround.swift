//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//
// Faithful Swift port of SignalUI/UIKitExtensions/UIButton+DeprecationWorkaround.{h,m}
// (an Objective-C category, excluded from the Linux SignalUI target). Same
// surface, same behavior: each ows_-prefixed property forwards 1:1 to the
// deprecated classic-layout UIButton property it wraps -- the category exists
// upstream only to confine the -Wdeprecated-declarations suppression to one
// file. Linked into <SignalUI>/QuillPort/ by scripts/quill-signal-link-ports.sh
// so it compiles into the SignalUI module itself.
//

import UIKit

extension UIButton {

    public var ows_adjustsImageWhenDisabled: Bool {
        get { adjustsImageWhenDisabled }
        set { adjustsImageWhenDisabled = newValue }
    }

    public var ows_adjustsImageWhenHighlighted: Bool {
        get { adjustsImageWhenHighlighted }
        set { adjustsImageWhenHighlighted = newValue }
    }

    public var ows_contentEdgeInsets: UIEdgeInsets {
        get { contentEdgeInsets }
        set { contentEdgeInsets = newValue }
    }

    public var ows_imageEdgeInsets: UIEdgeInsets {
        get { imageEdgeInsets }
        set { imageEdgeInsets = newValue }
    }

    public var ows_titleEdgeInsets: UIEdgeInsets {
        get { titleEdgeInsets }
        set { titleEdgeInsets = newValue }
    }
}
