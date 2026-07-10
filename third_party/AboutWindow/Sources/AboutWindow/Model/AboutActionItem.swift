//
//  AboutActionItem.swift
//  AboutWindow
//
//  Created by Giorgi Tchelidze on 04.06.25.
//

import SwiftUI

public struct AboutActionItem: Identifiable {
    public let id = UUID()
    public let button: AnyView
    public let navTarget: (any NavigableAction)?

    public init<V: View>(_ view: V) {
        if let nav = view as? any NavigableAction {
            self.navTarget = nav
            self.button = AnyView(view)
        } else {
            self.navTarget = nil
            self.button = AnyView(view)
        }
    }
}
