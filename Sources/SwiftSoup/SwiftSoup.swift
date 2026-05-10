import Foundation

// Implement classes with unique internal names to avoid scope recursion
public class QuillNode {
    public func nodeName() -> String { "" }
    public func attr(_ key: String) throws -> String { "" }
    public func getChildNodes() -> [QuillNode] { [] }
    public var description: String { "" }
}

public class QuillDocument: QuillNode {
    public func outputSettings(_ settings: Any) {}
    public func select(_ query: String) throws -> QuillElements { QuillElements() }
    public func html() throws -> String { "" }
}

public class QuillElements {
    public func remove() throws {}
    public func after(_ html: String) throws {}
    public func array() -> [QuillNode] { [] }
}

public enum QuillWhitelist {
    public static func none() -> Any { 0 }
}

public struct QuillOutputSettings {
    public init() {}
    public func prettyPrint(pretty: Bool) -> Any { 0 }
}

public enum QuillEntities {
    public static func unescape(_ string: String) throws -> String { string }
}

// Global scope aliases (for unqualified access: let d: Document)
public typealias Node = QuillNode
public typealias Document = QuillDocument
public typealias Elements = QuillElements
public typealias Whitelist = QuillWhitelist
public typealias OutputSettings = QuillOutputSettings
public typealias Entities = QuillEntities

// Namespace aliases (for qualified access: SwiftSoup.Node)
public enum SwiftSoup {
    public static func parse(_ html: String) throws -> Document { Document() }
    public static func clean(_ html: String, _ baseUri: String, _ whitelist: Any, _ outputSettings: Any) throws -> String? { html }

    public typealias Node = QuillNode
    public typealias Document = QuillDocument
    public typealias Elements = QuillElements
    public typealias Whitelist = QuillWhitelist
    public typealias OutputSettings = QuillOutputSettings
    public typealias Entities = QuillEntities
}
