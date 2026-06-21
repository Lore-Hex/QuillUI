import AppKit
@_exported import QuillRSTree

public extension NSOutlineView {
    @discardableResult
    func revealAndSelectNodeAtPath(_ nodePath: NodePath) -> Bool {
        let numberOfNodes = nodePath.components.count
        guard numberOfNodes >= 2 else { return false }

        let indexOfNodeToSelect = numberOfNodes - 1
        for index in 1...indexOfNodeToSelect {
            let node = nodePath.components[index]
            let row = row(forItem: node)
            guard row >= 0 else { return false }

            if index == indexOfNodeToSelect {
                selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                scrollRowToVisible(row)
                return true
            }
            expandItem(node)
        }
        return false
    }

    @discardableResult
    func revealAndSelectRepresentedObject(_ representedObject: AnyObject, _ treeController: TreeController) -> Bool {
        guard let nodePath = NodePath(representedObject: representedObject, treeController: treeController) else {
            return false
        }
        return revealAndSelectNodeAtPath(nodePath)
    }
}
