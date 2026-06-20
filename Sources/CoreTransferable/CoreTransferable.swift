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

public class NSItemProvider: NSObject, @unchecked Sendable {
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
        completionHandler: @escaping @Sendable (Result<T?, Error>) -> Void
    ) -> Progress {
        let progress = Progress(totalUnitCount: 1)
        let operation: any QuillTransferableLoadOperationProtocol = QuillTransferableLoadOperation(
            provider: self,
            type: type,
            progress: progress,
            completionHandler: completionHandler
        )
        Task { await operation.run() }
        return progress
    }

    public func loadTransferable<T: Transferable>(type: T.Type) async throws -> T? {
        for representation in representations {
            if case .object(let object) = representation, let value = object as? T {
                return value
            }
        }

        for transferRepresentation in Self.flatten(T.transferRepresentation) {
            if let fileRepresentation = transferRepresentation as? any QuillAnyFileTransferRepresentation,
               let value = try await importedValue(T.self, from: fileRepresentation) {
                return value
            }

            if let dataRepresentation = transferRepresentation as? QuillAnyDataTransferRepresentation,
               let value = try await importedValue(T.self, from: dataRepresentation) {
                return value
            }
        }

        return nil
    }

    private func importedValue<T>(
        _ type: T.Type,
        from representation: any QuillAnyFileTransferRepresentation
    ) async throws -> T? {
        if let fileURL = fileURL(conformingTo: representation.quillImportedContentType) {
            return try await representation.quillImport(file: fileURL, isOriginalFile: true) as? T
        }

        if let (data, contentType) = data(conformingTo: representation.quillImportedContentType) {
            let fileURL = try Self.writeTemporaryTransferFile(data: data, contentType: contentType)
            return try await representation.quillImport(file: fileURL, isOriginalFile: false) as? T
        }

        return nil
    }

    private func importedValue<T>(
        _ type: T.Type,
        from representation: QuillAnyDataTransferRepresentation
    ) async throws -> T? {
        guard let (data, _) = data(conformingTo: representation.quillImportedContentType) else {
            return nil
        }
        return try await representation.quillImport(data: data) as? T
    }

    private func fileURL(conformingTo contentType: UTType) -> URL? {
        for representation in representations {
            if case .file(let url, let type) = representation,
               type?.conforms(to: contentType) == true || contentType.quillAccepts(url: url) {
                return url
            }
        }
        return nil
    }

    private func data(conformingTo contentType: UTType) -> (Data, UTType)? {
        for representation in representations {
            switch representation {
            case .data(let data, let type) where type.conforms(to: contentType):
                return (data, type)
            case .file(let url, let type) where type?.conforms(to: contentType) == true || contentType.quillAccepts(url: url):
                if let data = try? Data(contentsOf: url) {
                    return (data, type ?? quillContentType(for: url) ?? contentType)
                }
            default:
                continue
            }
        }
        return nil
    }

    private static func flatten(_ representation: any TransferRepresentation) -> [any TransferRepresentation] {
        if let group = representation as? TransferRepresentationGroup {
            return group.representations.flatMap(flatten)
        }
        return [representation]
    }

    private static func writeTemporaryTransferFile(data: Data, contentType: UTType) throws -> URL {
        let preferredExtension = contentType.preferredFilenameExtension ?? "data"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("quill-transfer-\(UUID().uuidString)")
            .appendingPathExtension(preferredExtension)
        try data.write(to: url, options: [.atomic])
        return url
    }
}

private protocol QuillTransferableLoadOperationProtocol: Sendable {
    func run() async
}

private final class QuillTransferableLoadOperation<T: Transferable>: QuillTransferableLoadOperationProtocol, @unchecked Sendable {
    let provider: NSItemProvider
    let type: T.Type
    let progress: Progress
    let completionHandler: @Sendable (Result<T?, Error>) -> Void

    init(
        provider: NSItemProvider,
        type: T.Type,
        progress: Progress,
        completionHandler: @escaping @Sendable (Result<T?, Error>) -> Void
    ) {
        self.provider = provider
        self.type = type
        self.progress = progress
        self.completionHandler = completionHandler
    }

    func run() async {
        do {
            completionHandler(.success(try await provider.loadTransferable(type: type)))
        } catch {
            completionHandler(.failure(error))
        }
        progress.completedUnitCount = 1
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

public protocol Transferable: Sendable {
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

private protocol QuillAnyDataTransferRepresentation {
    var quillImportedContentType: UTType { get }
    func quillImport(data: Data) async throws -> Any
}

public struct DataRepresentation: TransferRepresentation, QuillAnyDataTransferRepresentation {
    public let exportedContentType: UTType
    public let importedContentType: UTType?
    private let importingValue: (@Sendable (Data) async throws -> Any)?

    public init(
        exportedContentType: UTType,
        exporting: @escaping @Sendable (TransferableExportProxy) async -> Data
    ) {
        self.exportedContentType = exportedContentType
        self.importedContentType = nil
        self.importingValue = nil
        _ = exporting
    }

    public init(
        exportedContentType: UTType,
        exporting: @escaping @Sendable (TransferableExportProxy) async throws -> Data
    ) {
        self.exportedContentType = exportedContentType
        self.importedContentType = nil
        self.importingValue = nil
        _ = exporting
    }

    public init<Imported>(
        importedContentType: UTType,
        importing: @escaping @Sendable (Data) async throws -> Imported
    ) {
        self.exportedContentType = importedContentType
        self.importedContentType = importedContentType
        self.importingValue = { data in try await importing(data) }
    }

    public init<Imported>(
        importedContentType: UTType,
        importing: @escaping @Sendable (Data) throws -> Imported
    ) {
        self.exportedContentType = importedContentType
        self.importedContentType = importedContentType
        self.importingValue = { data in try importing(data) }
    }

    fileprivate var quillImportedContentType: UTType {
        importedContentType ?? exportedContentType
    }

    fileprivate func quillImport(data: Data) async throws -> Any {
        guard let importingValue else {
            throw QuillCompatibilityError.representationUnavailable(quillImportedContentType.identifier)
        }
        return try await importingValue(data)
    }
}

private protocol QuillAnyFileTransferRepresentation {
    var quillImportedContentType: UTType { get }
    func quillImport(file: URL, isOriginalFile: Bool) async throws -> Any
}

public struct FileRepresentation<Imported>: TransferRepresentation, QuillAnyFileTransferRepresentation {
    public let importedContentType: UTType
    private let importingValue: @Sendable (ReceivedTransferredFile) async throws -> Imported

    public init(
        importedContentType: UTType,
        importing: @escaping @Sendable (ReceivedTransferredFile) async throws -> Imported
    ) {
        self.importedContentType = importedContentType
        self.importingValue = importing
    }

    public init(
        importedContentType: UTType,
        importing: @escaping @Sendable (ReceivedTransferredFile) throws -> Imported
    ) {
        self.importedContentType = importedContentType
        self.importingValue = { file in try importing(file) }
    }

    fileprivate var quillImportedContentType: UTType {
        importedContentType
    }

    fileprivate func quillImport(file: URL, isOriginalFile: Bool) async throws -> Any {
        try await importingValue(ReceivedTransferredFile(file: file, isOriginalFile: isOriginalFile))
    }
}
#endif
