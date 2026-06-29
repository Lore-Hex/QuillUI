//
//  AboutButton.swift
//  AboutWindow
//
//  Created by Giorgi Tchelidze on 02.06.25.
//
import SwiftUI

public struct AboutButton: View {

    private let id = UUID()
    private let title: String
    private let destination: AnyView?
    private let action: (() -> Void)?

    @FocusState private var isfocused: Bool

    @Environment(\.aboutWindowNavigation)
    private var aboutWindow

    // Action only
    public init(title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
        self.destination = nil
    }

    // Destination only
    public init<V: View>(title: String, @ViewBuilder destination: () -> V) {
        self.title = title
        self.action = nil
        self.destination = AnyView(destination())
    }

    // Action + Destination
    public init<V: View>(title: String, action: @escaping () -> Void, @ViewBuilder destination: () -> V) {
        self.title = title
        self.action = action
        self.destination = AnyView(destination())
    }

    public var body: some View {
        Button {
            withAnimation {
                action?()
                if destination != nil {
                    aboutWindow?.navigate(self)
                }
            }
        } label: {
            Text(title)
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
        .buttonStyle(.blur)
        .focused($isfocused)
        .modifier(FocusRingModifier(isFocused: isfocused, shape: .rect(cornerRadius: 6.5)))
    }
}

// MARK: - Navigable
extension AboutButton: NavigableAction {
    public func destinationView() -> AnyView {
        destination ?? AnyView(EmptyView())
    }
}
