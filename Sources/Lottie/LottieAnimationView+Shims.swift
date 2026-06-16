// Lottie -- Linux shim for compiling Signal-iOS SignalUI against QuillUI (QuillOS).
//
// Additive extension members on the existing `LottieAnimationView` (declared in
// Lottie.swift). lottie-ios exposes these as stored properties / a configuration
// method on `LottieAnimationView`; SignalUI references them, so they are mirrored
// here. Because Swift extensions cannot declare stored properties, the two
// "stored" values are backed by @MainActor global dictionaries keyed by the
// view's ObjectIdentifier — the standard shim pattern in this module.
//
// `setValueProvider(_:keypath:)` is a deliberate no-op: there is no animation
// runtime in this module, so supplying a type-erased value to a (non-existent)
// render tree has nothing to mutate.
import Foundation
import QuillUIKit

// Backing storage for the synthesized stored properties. Keyed by
// ObjectIdentifier(view); never read or written off the main actor.
@MainActor private var lottieBackgroundBehaviorStorage: [ObjectIdentifier: LottieBackgroundBehavior] = [:]
@MainActor private var lottieIsAnimationQueuedStorage: [ObjectIdentifier: Bool] = [:]

extension LottieAnimationView {
    /// How the animation would behave when the host view backgrounds.
    ///
    /// Mirrors lottie-ios's `LottieAnimationView.backgroundBehavior`. Defaults to
    /// `.stop`; there is no runtime here, so the value is purely stored.
    public var backgroundBehavior: LottieBackgroundBehavior {
        get { lottieBackgroundBehaviorStorage[ObjectIdentifier(self)] ?? .stop }
        set { lottieBackgroundBehaviorStorage[ObjectIdentifier(self)] = newValue }
    }

    /// Whether a play request is queued pending the animation loading.
    ///
    /// Mirrors lottie-ios's `LottieAnimationView.isAnimationQueued`. Defaults to
    /// `false`.
    public var isAnimationQueued: Bool {
        get { lottieIsAnimationQueuedStorage[ObjectIdentifier(self)] ?? false }
        set { lottieIsAnimationQueuedStorage[ObjectIdentifier(self)] = newValue }
    }

    /// Supplies a type-erased value for nodes addressed by `keypath`.
    ///
    /// Mirrors lottie-ios's `setValueProvider(_:keypath:)`. No-op in this shim:
    /// there is no animation render tree to update.
    public func setValueProvider(_ provider: AnyValueProvider, keypath: AnimationKeypath) {
        _ = (provider, keypath)
    }
}
