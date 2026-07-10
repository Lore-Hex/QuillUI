//
//  AboutActions.swift
//  WelcomeWindow
//
//  Created by Giorgi Tchelidze on 28.05.25.
//

import SwiftUI

/// An enumeration representing different configurations of actions for the About window.
/// To be used with ActionsBuilder @resultBuilder
/// It defines cases for zero, one, two, or three action items, each containing `AboutActionItem` instances.
public enum AboutActions {
    /// No action items.
    case none

    /// A single action item.
    /// - Parameter item: The `AboutActionItem` to include.
    case one(AboutActionItem)

    /// Two action items.
    /// - Parameters:
    ///   - first: The first `AboutActionItem`.
    ///   - second: The second `AboutActionItem`.
    case two(AboutActionItem, AboutActionItem)

    /// Three action items.
    /// - Parameters:
    ///   - first: The first `AboutActionItem`.
    ///   - second: The second `AboutActionItem`.
    ///   - third: The third `AboutActionItem`.
    case three(AboutActionItem, AboutActionItem, AboutActionItem)

    /// A computed property that returns an array of all `AboutActionItem` instances for the current case.
    public var all: [AboutActionItem] {
        switch self {
        case .none:
            return []
        case .one(let view1):
            return [view1]
        case let .two(view1, view2):
            return [view1, view2]
        case let .three(view1, view2, view3):
            return [view1, view2, view3]
        }
    }

    /// The number of action items in the current case.
    public var count: Int {
        all.count
    }

    /// An array of navigable actions derived from the action items.
    /// Filters `AboutActionItem` instances to include only those with a valid `navTarget`.
    public var navigable: [any NavigableAction] {
        all.compactMap { $0.navTarget }
    }
}
