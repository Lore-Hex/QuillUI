import Foundation

public struct ShelfPackItem {
    public var itemId: Int32
    public var x: Int32
    public var y: Int32
    public var width: Int32
    public var height: Int32

    public init(itemId: Int32 = -1, x: Int32 = 0, y: Int32 = 0, width: Int32 = 0, height: Int32 = 0) {
        self.itemId = itemId
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public final class ShelfPackContext: NSObject {
    private let width: Int32
    private let height: Int32
    private var nextItemId: Int32 = 0
    private var cursorX: Int32 = 0
    private var cursorY: Int32 = 0
    private var rowHeight: Int32 = 0
    private var liveItemIds: Set<Int32> = []

    public var isEmpty: Bool {
        liveItemIds.isEmpty
    }

    public init(width: Int32, height: Int32) {
        self.width = max(0, width)
        self.height = max(0, height)
        super.init()
    }

    public func addItem(withWidth requestedWidth: Int32, height requestedHeight: Int32) -> ShelfPackItem {
        let itemWidth = max(0, requestedWidth)
        let itemHeight = max(0, requestedHeight)
        guard itemWidth > 0, itemHeight > 0, itemWidth <= width, itemHeight <= height else {
            return ShelfPackItem()
        }

        if cursorX + itemWidth > width {
            cursorX = 0
            cursorY += rowHeight
            rowHeight = 0
        }
        guard cursorY + itemHeight <= height else {
            return ShelfPackItem()
        }

        let itemId = nextItemId
        nextItemId += 1
        let item = ShelfPackItem(itemId: itemId, x: cursorX, y: cursorY, width: itemWidth, height: itemHeight)
        cursorX += itemWidth
        rowHeight = max(rowHeight, itemHeight)
        liveItemIds.insert(itemId)
        return item
    }

    public func removeItem(_ itemId: Int32) {
        liveItemIds.remove(itemId)
    }
}
