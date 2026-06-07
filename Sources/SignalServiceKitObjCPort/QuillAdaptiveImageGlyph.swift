//
// SignalServiceKit ObjC port for QuillOS (Track B).
//
// NSAdaptiveImageGlyph (UIKit, iOS 18 -- "Genmoji"/animated image glyphs) and
// the NSAttributedString.Key.adaptiveImageGlyph attribute. SSK's
// NSAttributedString+SSK references them inside an `if #available(iOS 18, *)`
// branch that is dead on Linux, but Swift still type-checks it, so the symbols
// must exist. Inert on Linux (the branch never runs).
//
import Foundation
import UIKit
import UniformTypeIdentifiers

public class NSAdaptiveImageGlyph: NSObject {
    public var imageContent: Data { Data() }
    public var contentIdentifier: String { "" }
    public var contentDescription: String { "" }
    public class var contentType: UTType { .data }
}

public extension NSAttributedString.Key {
    static let adaptiveImageGlyph = NSAttributedString.Key("NSAdaptiveImageGlyph")
}
