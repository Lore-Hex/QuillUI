//
//  ActionsBuilder.swift
//  WelcomeWindow
//
//  Created by Giorgi Tchelidze on 28.05.25.
//

import SwiftUI

/// A result builder for constructing `AboutActions` from SwiftUI views.
/// It supports creating action configurations with zero, one, two, or three view-based action items.
@resultBuilder
public enum ActionsBuilder {
    /// Builds an empty `AboutActions` instance with no action items.
    /// - Returns: An `AboutActions.none` instance.
    public static func buildBlock() -> AboutActions {
        .none
    }

    /// Builds an `AboutActions` instance with a single view-based action item.
    /// - Parameter view1: A SwiftUI view to be wrapped as an `AboutActionItem`.
    /// - Returns: An `AboutActions.one` instance containing the action item.
    public static func buildBlock<V1: View>(_ view1: V1) -> AboutActions {
        .one(AboutActionItem(view1))
    }

    /// Builds an `AboutActions` instance with two view-based action items.
    /// - Parameters:
    ///   - view1: The first SwiftUI view to be wrapped as an `AboutActionItem`.
    ///   - view2: The second SwiftUI view to be wrapped as an `AboutActionItem`.
    /// - Returns: An `AboutActions.two` instance containing the two action items.
    public static func buildBlock<V1: View, V2: View>(_ view1: V1, _ view2: V2) -> AboutActions {
        .two(AboutActionItem(view1), AboutActionItem(view2))
    }

    /// Builds an `AboutActions` instance with three view-based action items.
    /// - Parameters:
    ///   - view1: The first SwiftUI view to be wrapped as an `AboutActionItem`.
    ///   - view2: The second SwiftUI view to be wrapped as an `AboutActionItem`.
    ///   - view3: The third SwiftUI view to be wrapped as an `AboutActionItem`.
    /// - Returns: An `AboutActions.three` instance containing the three action items.
    public static func buildBlock<V1: View, V2: View, V3: View>(_ view1: V1, _ view2: V2, _ view3: V3) -> AboutActions {
        .three(AboutActionItem(view1), AboutActionItem(view2), AboutActionItem(view3))
    }
}
