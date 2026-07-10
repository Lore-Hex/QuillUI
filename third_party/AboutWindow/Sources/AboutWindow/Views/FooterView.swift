//
//  FooterView.swift
//  AboutWindow
//
//  Created by Giorgi Tchelidze on 02.06.25.
//

import SwiftUI

public struct FooterView<PrimaryView: View, SecondaryView: View>: View {
    let primaryView: PrimaryView?
    let secondaryView: SecondaryView?

    @Environment(\.colorScheme)
    private var colorScheme

    public init(
        @ViewBuilder primaryView: () -> PrimaryView? = { nil },
        @ViewBuilder secondaryView: () -> SecondaryView? = { nil }
    ) {
        self.primaryView = primaryView()
        self.secondaryView = secondaryView()
    }

    public var body: some View {
        VStack(spacing: 2) {
            if let primaryView {
                primaryView
            }
            if let secondaryView {
                secondaryView
            }
        }
        .textSelection(.disabled)
        .font(.system(size: 11, weight: .regular))
        .foregroundColor(Color(.tertiaryLabelColor))
        .blendMode(colorScheme == .dark ? .plusLighter : .plusDarker)
        .padding(.top, 12)
        .padding(.bottom, -4)
    }
}
