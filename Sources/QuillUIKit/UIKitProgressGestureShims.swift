//
//  UIKitProgressGestureShims.swift
//  QuillUIKit
//
//  Additive shims for UIKit types that Signal references but that are
//  absent from this Linux UIKit reimplementation. This file IS the UIKit
//  base layer, so the UIKit types below (UIView, UIControl,
//  UIPanGestureRecognizer, UIBarButtonItem, NSObject, UIRectEdge, etc.)
//  are same-module and referenced directly without importing UIKit.
//

import Foundation
import CoreGraphics
import QuillFoundation

// MARK: - UIProgressView

@MainActor
open class UIProgressView: UIView {

    public enum Style: Int {
        case `default`
        case bar
    }

    open var progress: Float = 0

    open var progressTintColor: UIColor?

    open var trackTintColor: UIColor?

    open var progressViewStyle: Style

    open func setProgress(_ progress: Float, animated: Bool) {
        self.progress = progress
    }

    public init(progressViewStyle: Style) {
        self.progressViewStyle = progressViewStyle
        super.init(frame: .zero)
    }

    public override init(frame: CGRect) {
        self.progressViewStyle = .default
        super.init(frame: frame)
    }

    public required init?(coder: NSCoder) {
        self.progressViewStyle = .default
        super.init(coder: coder)
    }
}

// MARK: - UIScreenEdgePanGestureRecognizer

@MainActor
open class UIScreenEdgePanGestureRecognizer: UIPanGestureRecognizer {

    open var edges: UIRectEdge = []

    public override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
    }
}

// MARK: - UIAccessibilityCustomAction

@MainActor
open class UIAccessibilityCustomAction: NSObject {

    public typealias Handler = @MainActor (UIAccessibilityCustomAction) -> Bool

    open var name: String

    private let actionHandler: Handler?

    private weak var target: AnyObject?

    private let selector: Selector?

    public init(name: String, actionHandler: @escaping Handler) {
        self.name = name
        self.actionHandler = actionHandler
        self.target = nil
        self.selector = nil
        super.init()
    }

    public init(name: String, target: Any?, selector: Selector) {
        self.name = name
        self.actionHandler = nil
        self.target = target as AnyObject?
        self.selector = selector
        super.init()
    }
}

// MARK: - UIBarButtonItemGroup

@MainActor
open class UIBarButtonItemGroup: NSObject {

    open var barButtonItems: [UIBarButtonItem]

    open var representativeItem: UIBarButtonItem?

    public init(barButtonItems: [UIBarButtonItem], representativeItem: UIBarButtonItem?) {
        self.barButtonItems = barButtonItems
        self.representativeItem = representativeItem
        super.init()
    }
}

// MARK: - UIRectEdge (absent from the base module; used by edge-pan gestures)
public struct UIRectEdge: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let top = UIRectEdge(rawValue: 1 << 0)
    public static let left = UIRectEdge(rawValue: 1 << 1)
    public static let bottom = UIRectEdge(rawValue: 1 << 2)
    public static let right = UIRectEdge(rawValue: 1 << 3)
    public static let all: UIRectEdge = [.top, .left, .bottom, .right]
}
