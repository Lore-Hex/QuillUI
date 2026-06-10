import SwiftUI
import Photos
import CoreTransferable

#if os(Linux)
public struct PhotosPickerItem: Hashable, Sendable {
    public var itemIdentifier: String?
    public init(itemIdentifier: String? = nil) {
        self.itemIdentifier = itemIdentifier
    }

    public func loadTransferable<T: Transferable>(type: T.Type) async throws -> T? {
        _ = type
        return nil
    }
}

public struct PHPickerFilter: Hashable, Sendable {
    private let rawValue: String
    private init(_ rawValue: String) { self.rawValue = rawValue }
    public static let images = PHPickerFilter("images")
    public static let videos = PHPickerFilter("videos")
    public static func any(of filters: [PHPickerFilter]) -> PHPickerFilter {
        PHPickerFilter(filters.map(\.rawValue).joined(separator: ","))
    }
}

public struct PhotosPicker<Label: View>: View {
    private let label: Label

    public init(selection: Binding<PhotosPickerItem?>, @ViewBuilder label: () -> Label) {
        _ = selection
        self.label = label()
    }

    public init(
        selection: Binding<[PhotosPickerItem]>,
        maxSelectionCount: Int? = nil,
        matching: PHPickerFilter? = nil,
        photoLibrary: PHPhotoLibrary = .shared(),
        @ViewBuilder label: () -> Label
    ) {
        _ = selection
        _ = maxSelectionCount
        _ = matching
        _ = photoLibrary
        self.label = label()
    }

    public var body: some View {
        label
    }
}

public extension View {
    func photosPicker(
        isPresented: Binding<Bool>,
        selection: Binding<[PhotosPickerItem]>,
        maxSelectionCount: Int? = nil,
        matching: PHPickerFilter? = nil,
        photoLibrary: PHPhotoLibrary = .shared()
    ) -> Self {
        _ = isPresented
        _ = selection
        _ = maxSelectionCount
        _ = matching
        _ = photoLibrary
        return self
    }

    func photosPicker(
        isPresented: Binding<Bool>,
        selection: Binding<PhotosPickerItem?>,
        matching: PHPickerFilter? = nil,
        photoLibrary: PHPhotoLibrary = .shared()
    ) -> Self {
        _ = isPresented
        _ = selection
        _ = matching
        _ = photoLibrary
        return self
    }
}
#endif
