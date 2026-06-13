// Lottie -- Linux shim for compiling Signal-iOS SignalUI against QuillUI (QuillOS).
// Symbols are added on demand as the SignalUI compile reports missing API.
import Foundation
import UIKit

public enum LottieLoopMode: Sendable {
    case playOnce
    case loop
    case autoReverse
    case `repeat`(Float)
    case repeatBackwards(Float)
}

public final class LottieAnimation: NSObject {
    public let name: String

    public init(name: String) {
        self.name = name
        super.init()
    }

    public static func named(_ name: String) -> LottieAnimation? {
        LottieAnimation(name: name)
    }
}

public protocol AnimationImageProvider: AnyObject {}

public final class BundleImageProvider: AnimationImageProvider {
    public init(bundle: Bundle = .main, searchPath: String? = nil) {
        _ = (bundle, searchPath)
    }
}

@MainActor open class LottieAnimationView: UIView {
    public var animation: LottieAnimation?
    public var loopMode: LottieLoopMode = .playOnce
    public var animationSpeed: CGFloat = 1
    public var currentProgress: CGFloat = 0
    public var isAnimationPlaying = false

    public init(name: String) {
        self.animation = LottieAnimation(name: name)
        super.init(frame: .zero)
    }

    public init(animation: LottieAnimation?, imageProvider: AnimationImageProvider? = nil) {
        self.animation = animation
        _ = imageProvider
        super.init(frame: .zero)
    }

    public required init?(coder: NSCoder) {
        super.init(frame: .zero)
    }

    public func play() {
        isAnimationPlaying = true
        currentProgress = 1
    }

    public func play(completion: ((Bool) -> Void)? = nil) {
        play()
        completion?(true)
    }

    public func play(fromProgress: CGFloat? = nil, toProgress: CGFloat, loopMode: LottieLoopMode? = nil, completion: ((Bool) -> Void)? = nil) {
        if let fromProgress {
            currentProgress = fromProgress
        }
        if let loopMode {
            self.loopMode = loopMode
        }
        currentProgress = toProgress
        isAnimationPlaying = true
        completion?(true)
    }

    public func stop() {
        isAnimationPlaying = false
        currentProgress = 0
    }

    public func pause() {
        isAnimationPlaying = false
    }
}
