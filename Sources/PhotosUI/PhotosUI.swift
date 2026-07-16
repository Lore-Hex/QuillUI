import SwiftUI
import Photos
import CoreTransferable

#if os(Linux)
public struct PhotosPickerItem: Hashable, Sendable {
    public var itemIdentifier: String?
    private let fileURL: URL?

    public init(itemIdentifier: String? = nil, fileURL: URL? = nil) {
        self.itemIdentifier = itemIdentifier
        self.fileURL = fileURL
    }

    public init(fileURL: URL) {
        self.itemIdentifier = fileURL.lastPathComponent
        self.fileURL = fileURL
    }

    public func loadTransferable<T: Transferable>(type: T.Type) async throws -> T? {
        guard let fileURL else { return nil }
        return try await NSItemProvider(fileURL: fileURL).loadTransferable(type: type)
    }
}

public struct PHPickerFilter: Hashable, Sendable {
    fileprivate let rawValue: String
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
    ) -> OnChangeView<Self, Bool> {
        _ = photoLibrary
        return onChange(of: isPresented.wrappedValue) { presented in
            guard presented else { return }
            isPresented.wrappedValue = false
            let pickerItems = photosPickerItems(
                matching: matching,
                maxSelectionCount: maxSelectionCount,
                allowsMultipleSelection: true
            )
            if case .success(let items) = pickerItems {
                selection.wrappedValue = items
            }
        }
    }

    func photosPicker(
        isPresented: Binding<Bool>,
        selection: Binding<PhotosPickerItem?>,
        matching: PHPickerFilter? = nil,
        photoLibrary: PHPhotoLibrary = .shared()
    ) -> OnChangeView<Self, Bool> {
        _ = photoLibrary
        return onChange(of: isPresented.wrappedValue) { presented in
            guard presented else { return }
            isPresented.wrappedValue = false
            let pickerItems = photosPickerItems(
                matching: matching,
                maxSelectionCount: 1,
                allowsMultipleSelection: false
            )
            if case .success(let items) = pickerItems {
                selection.wrappedValue = items.first
            }
        }
    }

    private func photosPickerItems(
        matching: PHPickerFilter?,
        maxSelectionCount: Int?,
        allowsMultipleSelection: Bool
    ) -> Result<[PhotosPickerItem], Error> {
        QuillFileImporter
            .selectURLs(
                allowedContentTypes: photosPickerAllowedContentTypes(matching: matching),
                allowsMultipleSelection: allowsMultipleSelection
            )
            .map { urls in
                let limitedURLs: [URL]
                if let maxSelectionCount, maxSelectionCount > 0 {
                    limitedURLs = Array(urls.prefix(maxSelectionCount))
                } else {
                    limitedURLs = urls
                }
                return limitedURLs.map(PhotosPickerItem.init(fileURL:))
            }
    }

    private func photosPickerAllowedContentTypes(matching filter: PHPickerFilter?) -> [UTType] {
        guard let filter else { return [] }
        var contentTypes: [UTType] = []
        if filter.rawValue.contains("images") {
            contentTypes.append(.image)
        }
        if filter.rawValue.contains("videos") {
            contentTypes.append(contentsOf: [.video, .movie])
        }
        return contentTypes
    }
}
#endif
