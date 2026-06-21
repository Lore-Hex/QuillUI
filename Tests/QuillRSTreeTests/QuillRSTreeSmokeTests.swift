import Foundation
import Testing
import AppKit
import RSTree
@testable import QuillRSTree

/// Smoke tests for the vendored upstream RSTree module. Pins
/// the parent/child wiring, indexPath, and TreeController
/// rebuild path that the upcoming sidebar feedsPane migration
/// will rely on. Upstream RSTree has no test target of its own
/// (per docs/netnewswire-audit.md), so these are Quill-side
/// guards.
@Suite("QuillRSTree — vendored upstream smoke tests")
@MainActor
struct QuillRSTreeSmokeTests {

    final class Folder {
        let name: String
        let children: [Any]
        init(_ name: String, _ children: [Any]) {
            self.name = name
            self.children = children
        }
    }

    final class Feed {
        let title: String
        let url: String
        init(_ title: String, _ url: String) {
            self.title = title
            self.url = url
        }
    }

    final class TreeDelegate: TreeControllerDelegate {
        func treeController(treeController: TreeController, childNodesFor node: Node) -> [Node]? {
            if let folder = node.representedObject as? Folder {
                return folder.children.compactMap { child in
                    let n = Node(representedObject: child as AnyObject, parent: node)
                    if child is Folder { n.canHaveChildNodes = true }
                    return n
                }
            }
            return nil
        }
    }

    final class NodeOutlineDataSource: NSObject, NSOutlineViewDataSource {
        let rootNode: Node

        init(rootNode: Node) {
            self.rootNode = rootNode
        }

        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            (item as? Node ?? rootNode).numberOfChildNodes
        }

        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            (item as? Node ?? rootNode).childNodes[index]
        }

        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            (item as? Node)?.canHaveChildNodes ?? false
        }
    }

    @MainActor
    @Test("Node parent/child + isRoot wiring")
    func nodeBasics() {
        let root = Node.genericRootNode()
        root.canHaveChildNodes = true
        #expect(root.isRoot)
        #expect(root.numberOfChildNodes == 0)

        let child = Node(representedObject: NSString("child"), parent: root)
        root.childNodes = [child]
        #expect(!child.isRoot)
        #expect(child.parent === root)
        #expect(root.numberOfChildNodes == 1)
    }

    @MainActor
    @Test("TreeController.rebuild() walks the delegate's children")
    func treeControllerRebuild() {
        let root = Folder("root", [
            Feed("Daring Fireball", "https://daringfireball.net/feeds/main"),
            Folder("Dev", [
                Feed("Swift Blog", "https://swift.org/atom.xml"),
                Feed("Hacker News", "https://hnrss.org/frontpage"),
            ]),
        ])

        let delegate = TreeDelegate()
        let rootNode = Node(representedObject: root as AnyObject, parent: nil)
        rootNode.canHaveChildNodes = true
        let controller = TreeController(delegate: delegate, rootNode: rootNode)

        #expect(controller.rootNode.numberOfChildNodes == 2)
        let firstChild = controller.rootNode.childNodes[0]
        #expect((firstChild.representedObject as? Feed)?.title == "Daring Fireball")

        let secondChild = controller.rootNode.childNodes[1]
        #expect((secondChild.representedObject as? Folder)?.name == "Dev")
        // Folders flag canHaveChildNodes so TreeController recurses on them.
        #expect(secondChild.numberOfChildNodes == 2)
        let nested = secondChild.childNodes[0]
        #expect((nested.representedObject as? Feed)?.title == "Swift Blog")
        #expect(nested.parent === secondChild)
    }

    @MainActor
    @Test("Node.indexPath walks back through parents")
    func nodeIndexPath() {
        let root = Node.genericRootNode()
        root.canHaveChildNodes = true
        let a = Node(representedObject: NSString("a"), parent: root)
        let b = Node(representedObject: NSString("b"), parent: root)
        root.childNodes = [a, b]
        // Upstream Node.indexPath prepends the synthetic root's
        // own index (0 for genericRootNode) before the child
        // position — so first child is [0,0], second is [0,1].
        // That's what the AppKit NSOutlineView extension expects;
        // matches NSTreeController's convention.
        #expect(a.indexPath == IndexPath(indexes: [0, 0]))
        #expect(b.indexPath == IndexPath(indexes: [0, 1]))
    }

    @MainActor
    @Test("RSTree NSOutlineView extension reveals and selects represented objects")
    func outlineRevealAndSelectRepresentedObject() {
        let root = Folder("root", [
            Folder("Dev", [
                Feed("Swift Blog", "https://swift.org/atom.xml"),
            ]),
            Feed("Daring Fireball", "https://daringfireball.net/feeds/main"),
        ])
        let delegate = TreeDelegate()
        let rootNode = Node(representedObject: root as AnyObject, parent: nil)
        rootNode.canHaveChildNodes = true
        let controller = TreeController(delegate: delegate, rootNode: rootNode)
        let folderNode = controller.rootNode.childNodes[0]
        let feedNode = folderNode.childNodes[0]
        let feed = feedNode.representedObject as AnyObject

        let outline = NSOutlineView()
        let dataSource = NodeOutlineDataSource(rootNode: controller.rootNode)
        outline.dataSource = dataSource
        outline.reloadData()

        withExtendedLifetime((delegate, dataSource)) {
            #expect(outline.numberOfRows == 2)
            #expect(outline.revealAndSelectRepresentedObject(feed, controller))
            #expect(outline.isItemExpanded(folderNode))
            #expect(outline.selectedItems.first === feedNode)
            #expect(outline.selectedRow == outline.row(forItem: feedNode))
        }
    }
}
