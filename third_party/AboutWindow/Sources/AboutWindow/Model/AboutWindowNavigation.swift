//
//  AboutWindowNavigation.swift
//  AboutWindow
//
//  Created by Giorgi Tchelidze on 04.06.25.
//

import SwiftUI

/// A structure that manages navigation actions for the About window.
/// It provides closures for navigating to a target and popping the current view.
public struct AboutWindowNavigation {
    /// A closure to navigate to a specified `NavigableAction`.
    public let navigate: (any NavigableAction) -> Void

    /// A closure to pop the current view from the navigation stack.
    public let pop: () -> Void

    /// Initializes the navigation structure with navigation and pop actions.
    /// - Parameters:
    ///   - navigate: A closure that takes a `NavigableAction` to perform navigation.
    ///   - pop: A closure to pop the current view from the navigation stack.
    public init(
        navigate: @escaping (any NavigableAction) -> Void,
        pop: @escaping () -> Void
    ) {
        self.navigate = navigate
        self.pop = pop
    }
}
