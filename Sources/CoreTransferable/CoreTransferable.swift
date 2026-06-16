@_exported import Foundation
@_exported import UniformTypeIdentifiers

#if os(Linux)
public enum QuillCompatibilityError: Error, LocalizedError, Equatable {
    case representationUnavailable(String)
    case fileSelectionUnavailable
    case unsupportedFileSelection(URL, [UTType])

    public var errorDescription: String? {
        switch self {
        case .representationUnavailable(let identifier):
            return "No data representation is available for \(identifier)."
        case .fileSelectionUnavailable:
            return "No file selection provider is available."
        case .unsupportedFileSelection(let url, let allowedTypes):
            let allowed = allowedTypes.map(\.identifier).joined(separator: ", ")
            return "\(url.path) is not one of the allowed file types: \(allowed)."
        }
    }
}

private func quillContentType(for url: URL) -> UTType? {
    UTType(filenameExtension: url.pathExtension)
}

private extension UTType {
    func quillAccepts(url: URL) -> Bool {
        quillContentType(for: url)?.conforms(to: self) == true
    }
}

public class NSItemProvider: NSObject {
    private enum Representation {
        case data(Data, UTType)
        case file(URL, UTType?)
        case object(Any)
    }

    public let suggestedName: String?
    private let representations: [Representation]

    public init(fileURL: URL) {
        self.suggestedName = fileURL.lastPathComponent
        self.representations = [.file(fileURL, quillContentType(for: fileURL))]
        super.init()
    }

    public init?(contentsOf url: URL) {
        self.suggestedName = url.lastPathComponent
        self.representations = [.file(url, quillContentType(for: url))]
        super.init()
    }

    public init(data: Data, type: UTType) {
        self.suggestedName = nil
        self.representations = [.data(data, type)]
        super.init()
    }

    public init(object: Any) {
        self.suggestedName = nil
        self.representations = [.object(object)]
        super.init()
    }

    public override init() {
        self.suggestedName = nil
        self.representations = []
        super.init()
    }

    public func registeredContentTypes(conformingTo contentType: UTType) -> [UTType] {
        representations.compactMap { representation in
            switch representation {
            case .data(_, let type) where type.conforms(to: contentType):
                return type
            case .file(let url, let type) where type?.conforms(to: contentType) == true || contentType.quillAccepts(url: url):
                return type ?? quillContentType(for: url)
            default:
                return nil
            }
        }
    }

    public var registeredTypeIdentifiers: [String] {
        representations.compactMap { representation in
            switch representation {
            case .data(_, let type):
                return type.identifier
            case .file(let url, let type):
                return (type ?? quillContentType(for: url))?.identifier
            case .object:
                return nil
            }
        }
    }

    public func hasItemConformingToTypeIdentifier(_ typeIdentifier: String) -> Bool {
        guard let requestedType = UTType(typeIdentifier) else {
            return registeredTypeIdentifiers.contains(typeIdentifier)
        }
        return registeredTypeIdentifiers.contains { identifier in
            identifier == typeIdentifier || UTType(identifier)?.conforms(to: requestedType) == true
        }
    }

    @discardableResult
    public func loadDataRepresentation(
        for contentType: UTType,
        completionHandler: @escaping (Data?, Error?) -> Void
    ) -> Progress? {
        for representation in representations {
            switch representation {
            case .data(let data, let type) where type.conforms(to: contentType):
                completionHandler(data, nil)
                return nil
            case .file(let url, let type) where type?.conforms(to: contentType) == true || contentType.quillAccepts(url: url):
                do {
                    completionHandler(try Data(contentsOf: url), nil)
                } catch {
                    completionHandler(nil, error)
                }
                return nil
            default:
                continue
            }
        }
        completionHandler(nil, QuillCompatibilityError.representationUnavailable(contentType.identifier))
        return nil
    }

    @discardableResult
    public func loadDataRepresentation(
        forTypeIdentifier typeIdentifier: String,
        completionHandler: @escaping (Data?, Error?) -> Void
    ) -> Progress? {
        guard let contentType = UTType(typeIdentifier) else {
            completionHandler(nil, QuillCompatibilityError.representationUnavailable(typeIdentifier))
            return nil
        }
        return loadDataRepresentation(for: contentType, completionHandler: completionHandler)
    }

    public func loadItem(
        forTypeIdentifier typeIdentifier: String,
        options: [AnyHashable: Any]? = nil,
        completionHandler: @escaping (Any?, Error?) -> Void
    ) {
        _ = options
        for representation in representations {
            switch representation {
            case .file(let url, let type) where type?.identifier == typeIdentifier || quillContentType(for: url)?.identifier == typeIdentifier:
                completionHandler(url, nil)
                return
            case .data(let data, let type) where type.identifier == typeIdentifier:
                completionHandler(data, nil)
                return
            case .object(let object):
                completionHandler(object, nil)
                return
            default:
                continue
            }
        }
        completionHandler(nil, QuillCompatibilityError.representationUnavailable(typeIdentifier))
    }

    @discardableResult
    public func loadFileRepresentation(
        forTypeIdentifier typeIdentifier: String,
        completionHandler: @escaping (URL?, Error?) -> Void
    ) -> Progress? {
        for representation in representations {
            switch representation {
            case .file(let url, let type) where type?.identifier == typeIdentifier || quillContentType(for: url)?.identifier == typeIdentifier:
                completionHandler(url, nil)
                return nil
            default:
                continue
            }
        }
        completionHandler(nil, QuillCompatibilityError.representationUnavailable(typeIdentifier))
        return nil
    }

    public func canLoadObject<T: NSItemProviderReading>(ofClass aClass: T.Type) -> Bool {
        _ = aClass
        return representations.contains { representation in
            if case .object(let object) = representation {
                return object is T
            }
            return false
        }
    }

    public func loadObject<T: NSItemProviderReading>(
        ofClass aClass: T.Type,
        completionHandler: @escaping (T?, Error?) -> Void
    ) -> Progress {
        _ = aClass
        for representation in representations {
            if case .object(let object) = representation, let value = object as? T {
                completionHandler(value, nil)
                return Progress(totalUnitCount: 1)
            }
        }
        completionHandler(nil, nil)
        return Progress(totalUnitCount: 1)
    }

    @discardableResult
    public func loadTransferable<T: Transferable>(
        type: T.Type,
        completionHandler: @escaping (Result<T?, Error>) -> Void
    ) -> Progress {
        _ = type
        completionHandler(.success(nil))
        return Progress(totalUnitCount: 1)
    }
}

public protocol NSItemProviderReading {
    static var readableTypeIdentifiersForItemProvider: [String] { get }
    static func object(withItemProviderData data: Data, typeIdentifier: String) throws -> Self
}

public extension NSItemProviderReading {
    static var readableTypeIdentifiersForItemProvider: [String] { [] }
}

extension NSString: NSItemProviderReading {
    public static var readableTypeIdentifiersForItemProvider: [String] {
        [UTType.text.identifier, UTType.plainText.identifier]
    }

    public static func object(withItemProviderData data: Data, typeIdentifier: String) throws -> Self {
        let value = String(data: data, encoding: .utf8) ?? ""
        return self.init(string: value)
    }
}

extension NSURL: NSItemProviderReading {
    public static var readableTypeIdentifiersForItemProvider: [String] {
        [UTType.url.identifier, UTType.fileURL.identifier]
    }

    public static func object(withItemProviderData data: Data, typeIdentifier: String) throws -> Self {
        let value = String(data: data, encoding: .utf8) ?? ""
        let url = typeIdentifier == UTType.fileURL.identifier
            ? URL(fileURLWithPath: value)
            : (URL(string: value) ?? URL(fileURLWithPath: value))
        return NSURL(string: url.absoluteString)! as! Self
    }
}

public protocol TransferRepresentation {}

public struct TransferRepresentationGroup: TransferRepresentation {
    public let representations: [any TransferRepresentation]
    public init(_ representations: [any TransferRepresentation]) {
        self.representations = representations
    }
}

@resultBuilder
public enum TransferRepresentationBuilder {
    public static func buildBlock<R: TransferRepresentation>(_ representation: R) -> R {
        representation
    }

    public static func buildBlock(_ representations: any TransferRepresentation...) -> TransferRepresentationGroup {
        TransferRepresentationGroup(representations)
    }
}

public protocol Transferable {
    associatedtype TransferRepresentationValue: TransferRepresentation

    @TransferRepresentationBuilder
    static var transferRepresentation: TransferRepresentationValue { get }
}

public struct TransferableExportProxy: Sendable {
    public init() {}
    public func fetchData() async -> Data { Data() }
}

public struct ReceivedTransferredFile: Sendable {
    public let file: URL
    public let isOriginalFile: Bool

    public init(file: URL, isOriginalFile: Bool = true) {
        self.file = file
        self.isOriginalFile = isOriginalFile
    }
}

public struct DataRepresentation: TransferRepresentation {
    public let exportedContentType: UTType

    public init(
        exportedContentType: UTType,
        exporting: @escaping @Sendable (TransferableExportProxy) async -> Data
    ) {
        self.exportedContentType = exportedContentType
        _ = exporting
    }

    public init(
        exportedContentType: UTType,
        exporting: @escaping @Sendable (TransferableExportProxy) async throws -> Data
    ) {
        self.exportedContentType = exportedContentType
        _ = exporting
    }
}

public struct FileRepresentation<Imported>: TransferRepresentation {
    public let importedContentType: UTType

    public init(
        importedContentType: UTType,
        importing: @escaping @Sendable (ReceivedTransferredFile) async throws -> Imported
    ) {
        self.importedContentType = importedContentType
        _ = importing
    }

    public init(
        importedContentType: UTType,
        importing: @escaping @Sendable (ReceivedTransferredFile) throws -> Imported
    ) {
        self.importedContentType = importedContentType
        _ = importing
    }
}
#endif
