//
//  AboutWindow.swift
//  CodeEdit
//
//  Created by Wouter Hennen on 14/03/2023.
//

import SwiftUI

public struct AboutWindow<Footer: View, SubtitleView: View>: Scene {
    private let actions: () -> AboutActions
    let footer: () -> Footer
    let iconImage: Image?
    let title: String?
    let subtitleView: (() -> SubtitleView)?

    public init(
        iconImage: Image? = nil,
        title: String? = nil,
        subtitleView: (() -> SubtitleView)? = nil,
        @ActionsBuilder actions: @escaping () -> AboutActions,
        @ViewBuilder footer: @escaping () -> Footer = { EmptyView() }
    ) {
        self.iconImage = iconImage
        self.title = title
        self.subtitleView = subtitleView
        self.actions = actions
        self.footer = footer
    }

    public var body: some Scene {
        Window("", id: DefaultSceneID.about) {
            AboutView(
                actions: actions,
                footer: footer,
                iconImage: iconImage,
                title: title,
                subtitleView: subtitleView
            )
                .task {
                    if let window = NSApp.findWindow(DefaultSceneID.about) {
                        window.styleMask = [
                            .titled, .closable, .fullSizeContentView, .nonactivatingPanel
                        ]

                        window.titleVisibility = .hidden
                        window.titlebarAppearsTransparent = true
                        window.backgroundColor = .clear
                        window.isMovableByWindowBackground = true

                        window.standardWindowButton(.zoomButton)?.isHidden = true
                        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
                    }
                }
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
    }
}

extension AboutWindow where SubtitleView == EmptyView {
    /// Creates an about window without a subtitle view.
    public init(
        iconImage: Image? = nil,
        title: String? = nil,
        @ActionsBuilder actions: @escaping () -> AboutActions,
        @ViewBuilder footer: @escaping () -> Footer = { EmptyView() }
    ) {
        self.init(
            iconImage: iconImage,
            title: title,
            subtitleView: nil,
            actions: actions,
            footer: footer
        )
    }
}
