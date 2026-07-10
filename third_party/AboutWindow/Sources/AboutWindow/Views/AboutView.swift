//
//  AboutView.swift
//  CodeEditModules/About
//
//  Created by Andrei Vidrasco on 02.04.2022
//

import SwiftUI

public struct AboutView<Footer: View, SubtitleView: View>: View {
    @Environment(\.openURL)
    private var openURL

    @Environment(\.colorScheme)
    private var colorScheme

    @Environment(\.dismiss)
    private var dismiss

    @State private var currentView: AnyView? // Tracks the current view (nil for root)

    @Namespace private var animator

    private let actions: () -> AboutActions
    private let footer: () -> Footer
    private let iconImage: Image?
    private let title: String?
    private let subtitleView: (() -> SubtitleView)?

    public init(
        @ActionsBuilder actions: @escaping () -> AboutActions,
        @ViewBuilder footer: @escaping () -> Footer,
        iconImage: Image? = nil,
        title: String? = nil,
        subtitleView: (() -> SubtitleView)? = nil
    ) {
        self.actions = actions
        self.footer = footer
        self.iconImage = iconImage
        self.title = title
        self.subtitleView = subtitleView
    }

    public var body: some View {
        ZStack(alignment: .top) {
            // Root view (AboutDefaultView) or destination view
            if let destinationView = currentView {
                destinationView
            } else {
                AboutDefaultView(
                    namespace: animator,
                    actions: actions,
                    footer: footer,
                    iconImage: iconImage,
                    title: title,
                    subtitleView: subtitleView
                )
            }
        }
        .environmentObject(NamespaceWrapper(namespace: animator))
        .environment(\.isAboutDetailPresented, currentView != nil)
        .environment(\.aboutWindowNavigation, AboutWindowNavigation(
            navigate: { action in
                withAnimation {
                    currentView = action.destinationView()
                }
            },
            pop: {
                withAnimation {
                    currentView = nil
                }
            }
        ))
        .animation(.smooth, value: currentView == nil)
        .ignoresSafeArea()
        .frame(width: 280)
        .fixedSize(horizontal: true, vertical: false)
        // hack required to get buttons appearing correctly in light appearance
        // if anyone knows of a better way to do this feel free to refactor
        .background(.regularMaterial.opacity(0))
        .background(EffectView(.popover, blendingMode: .behindWindow).ignoresSafeArea())
        .background {
            Button("") {
                dismiss()
            }
            .keyboardShortcut(.escape, modifiers: [])
            .hidden()
        }
    }
}
