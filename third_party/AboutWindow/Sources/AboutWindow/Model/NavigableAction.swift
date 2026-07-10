//
//  NavigableAction.swift
//  AboutWindow
//
//  Created by Giorgi Tchelidze on 04.06.25.
//

import SwiftUI

/// A protocol defining an action that can provide a destination view for navigation.
/// Conforming types must implement a method to return a SwiftUI view as the navigation target.
public protocol NavigableAction {
    /// Returns the destination view for the navigation action.
    /// - Returns: An `AnyView` representing the target view for navigation.
    @MainActor
    func destinationView() -> AnyView
}
