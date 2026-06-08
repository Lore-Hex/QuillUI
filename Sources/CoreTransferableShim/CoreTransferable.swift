import Foundation
import UniformTypeIdentifiers

// Minimal Linux stand-in for Apple's CoreTransferable. Enough surface for vendored
// IceCubes source (MediaUI's MediaUIImageTransferable) to declare Transferable
// conformances and `transferRepresentation`. Nothing actually transfers on GTK —
// these are type/source-compatibility shims.

public protocol TransferRepresentation {}

@resultBuilder
public enum TransferRepresentationBuilder {
    public static func buildBlock<T: TransferRepresentation>(_ component: T) -> T { component }
    public static func buildExpression<T: TransferRepresentation>(_ expression: T) -> T { expression }
    public static func buildPartialBlock<T: TransferRepresentation>(first: T) -> T { first }
    public static func buildPartialBlock<T: TransferRepresentation>(accumulated: T, next: T) -> T { accumulated }
}

public protocol Transferable {
    associatedtype Representation: TransferRepresentation
    @TransferRepresentationBuilder static var transferRepresentation: Representation { get }
}

public struct DataRepresentation<Item>: TransferRepresentation {
    public init(
        exportedContentType: UTType,
        exporting: @escaping (Item) async throws -> Data
    ) {}

    public init(
        importedContentType: UTType,
        importing: @escaping (Data) async throws -> Item
    ) {}

    public init(
        contentType: UTType,
        exporting: @escaping (Item) async throws -> Data,
        importing: @escaping (Data) async throws -> Item
    ) {}
}

public struct ProxyRepresentation<Item, Content>: TransferRepresentation {
    public init(exporting: @escaping (Item) async throws -> Content) {}
    public init(importing: @escaping (Content) async throws -> Item) {}
}
