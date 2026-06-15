import Foundation
import CoreGraphics
import QuillFoundation

/// A model-only stand-in for lottie-ios's `AnimationKeypath`.
///
/// Mirrors the public API of `Lottie.AnimationKeypath`: a dot-delimited path
/// addressing nodes within an animation. This shim carries the parsed key
/// segments only; there is no animation runtime in this module.
public struct AnimationKeypath: ExpressibleByStringLiteral, Hashable {
    /// The individual path segments, in order.
    public let keys: [String]

    /// Creates a keypath by splitting a dot-delimited string into segments.
    public init(keypath: String) {
        self.keys = keypath.split(separator: ".").map(String.init)
    }

    /// Creates a keypath from explicit segments.
    public init(keys: [String]) {
        self.keys = keys
    }

    /// Creates a keypath from a string literal, splitting on the dot character.
    public init(stringLiteral value: String) {
        self.init(keypath: value)
    }
}

/// A model-only stand-in for lottie-ios's `LottieBackgroundBehavior`.
///
/// Describes how a (non-existent here) animation would behave when the
/// hosting view moves to the background.
public enum LottieBackgroundBehavior {
    case stop
    case pause
    case pauseAndRestore
    case forceFinish
    case continuePlaying
}

/// A model-only stand-in for lottie-ios's `AnimationProgressTime`.
public typealias AnimationProgressTime = CGFloat

/// A model-only stand-in for lottie-ios's `AnyValueProvider`.
///
/// In lottie-ios this provides type-erased values to the rendering engine.
/// Here it exposes only the type-erased stored value.
public protocol AnyValueProvider {
    /// The provided value, type-erased.
    var typeErasedStorage: Any { get }
}

/// A model-only stand-in for lottie-ios's `ColorValueProvider`.
///
/// Stores a single color. The parameter type is `UIColor` (from
/// `QuillFoundation`) deliberately, to avoid colliding with any existing
/// `LottieColor` type.
public final class ColorValueProvider: AnyValueProvider {
    /// The color supplied at initialization.
    public let color: UIColor

    /// Creates a provider for a single color.
    public init(_ color: UIColor) {
        self.color = color
    }

    /// The provided color, type-erased.
    public var typeErasedStorage: Any { color }
}
