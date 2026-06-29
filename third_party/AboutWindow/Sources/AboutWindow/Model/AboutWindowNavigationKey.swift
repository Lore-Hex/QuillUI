//
//  AboutWindowNavigationKey.swift
//  AboutWindow
//
//  Created by Giorgi Tchelidze on 04.06.25.
//

import SwiftUI

/// A key for accessing the `AboutWindowNavigation` controller in the SwiftUI environment.
public struct AboutWindowNavigationKey: @preconcurrency EnvironmentKey {
    @MainActor public static let defaultValue: AboutWindowNavigation? = nil
}

public extension EnvironmentValues {
    /// Provides access to navigation control for the About window.
    var aboutWindowNavigation: AboutWindowNavigation? {
        get { self[AboutWindowNavigationKey.self] }
        set { self[AboutWindowNavigationKey.self] = newValue }
    }
}
