@_exported import Foundation
@_exported import UniformTypeIdentifiers

#if os(Linux)
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
