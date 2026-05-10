import Foundation
@_exported import QuillFoundation
@_exported import QuillUIKit
#if os(macOS) || os(iOS) || os(visionOS)
import AppKit
import UniformTypeIdentifiers
#else
import QuillKit
import QuillData
#endif

#if !os(macOS) && !os(iOS)
@MainActor public protocol TreeControllerDelegate: AnyObject {
    func treeController(treeController: TreeController, childNodesFor node: Node) -> [Node]?
}

@MainActor public class TreeController: NSObject {
    public weak var delegate: TreeControllerDelegate?
    public var rootNode: Node
    
    public init(delegate: TreeControllerDelegate?) {
        self.delegate = delegate
        self.rootNode = Node(representedObject: nil, parent: nil)
        super.init()
        rebuild()
    }
    
    public func rebuild() {
        if let children = delegate?.treeController(treeController: self, childNodesFor: rootNode) {
            rootNode.childNodes = children
        }
    }
}

public class Node: NSObject {
    public var representedObject: AnyObject?
    public weak var parent: Node?
    public var childNodes: [Node] = []
    
    public var isRoot: Bool { parent == nil }
    public var canHaveChildNodes: Bool = true
    public var isGroupItem: Bool = false
    
    public init(representedObject: Any?, parent: Node?) {
        self.representedObject = representedObject as AnyObject?
        self.parent = parent
        super.init()
    }
    
    public func existingOrNewChildNode(with representedObject: Any) -> Node {
        if let existing = childNodes.first(where: { ($0.representedObject as? NSObject) === (representedObject as? NSObject) }) {
            return existing
        }
        return createChildNode(representedObject)
    }
    
    public func childNodeRepresentingObject(_ representedObject: Any) -> Node? {
        return childNodes.first(where: { ($0.representedObject as? NSObject) === (representedObject as? NSObject) })
    }
    
    public func createChildNode(_ representedObject: Any) -> Node {
        let node = Node(representedObject: representedObject, parent: self)
        childNodes.append(node)
        return node
    }
}

public class NodePath: NSObject {
    public init?(node: Node) {}
    @MainActor public init?(representedObject: AnyObject, treeController: TreeController) {}
}

public protocol SmallIconProvider {}
public protocol PasteboardWriterOwner {}

public func postUnreadCountDidChangeNotification() {}

public enum Browser {
    public static func open(_ urlString: String, inBackground: Bool) {}
}

public extension NSString {
    static func rs_SQLValueList(withPlaceholders count: UInt) -> String? {
        if count == 0 { return nil }
        let placeholders = Array(repeating: "?", count: Int(count)).joined(separator: ", ")
        return "(\(placeholders))"
    }
}

public extension NSObject {
    var preferredLink: String? { return nil }
    var attributionString: String { return "" }
    var linkString: String { return "" }
}

public class IconImage: NSObject {
    public var image: RSImage?
    public var isDark: Bool = false
    public init(image: RSImage?, isDark: Bool = false) {
        self.image = image
        self.isDark = isDark
    }
}

import QuillUIKit
public class NonIntrinsicImageView: UIImageView {}
#else
public extension NSObject {
    @objc var preferredLink: String? { return nil }
    @objc var attributionString: String { return "" }
    @objc var linkString: String { return "" }
}
#endif
