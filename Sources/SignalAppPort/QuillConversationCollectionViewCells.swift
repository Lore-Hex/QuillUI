// QuillConversationCollectionViewCells.swift -- SignalApp Linux port.
//
// ConversationViewController registers CVCell.self for its message-cell reuse
// identifiers, then CVLoadCoordinator expects dequeue to return CVCell. Generic
// QuillUIKit cannot instantiate arbitrary registered subclasses from erased
// metatypes yet, so the concrete Signal collection view opts into a narrow
// factory for the known CVC cells.

public import UIKit

extension ConversationCollectionView: QuillUICollectionViewCellFactory {
    func quillCollectionView(
        _ collectionView: UICollectionView,
        makeCellWithReuseIdentifier identifier: String,
        for indexPath: IndexPath
    ) -> UICollectionViewCell? {
        _ = (collectionView, indexPath)
        guard CVCellReuseIdentifier(rawValue: identifier) != nil else {
            return nil
        }
        return CVCell(frame: .zero)
    }
}
