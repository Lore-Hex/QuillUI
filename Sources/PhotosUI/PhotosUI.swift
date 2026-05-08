import SwiftUI

public struct PhotosPickerItem: Hashable, Sendable {
    public init() {}
}

public struct PhotosPicker<Label: View>: View {
    private let selection: Binding<PhotosPickerItem?>
    private let label: Label

    public init(selection: Binding<PhotosPickerItem?>, @ViewBuilder label: () -> Label) {
        self.selection = selection
        self.label = label()
    }

    public var body: some View {
        label
    }
}

