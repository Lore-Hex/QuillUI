import Foundation
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

public protocol TSYTextStorageDelegate: NSTextStorageDelegate {
    func textStorage(_ textStorage: TSYTextStorage, willReplaceCharactersIn range: NSRange, with string: String)
    func textStorage(_ textStorage: TSYTextStorage, didReplaceCharactersIn range: NSRange, with string: String)
    func textStorageWillCompleteProcessingEdit(_ textStorage: TSYTextStorage)
    func textStorageDidCompleteProcessingEdit(_ textStorage: TSYTextStorage)
    func textStorage(_ textStorage: TSYTextStorage, doubleClickRangeForLocation location: Int) -> NSRange
    func textStorage(_ textStorage: TSYTextStorage, nextWordIndexFromLocation location: Int, direction forward: Bool) -> Int
}

public extension TSYTextStorageDelegate {
    func textStorage(_ textStorage: TSYTextStorage, willReplaceCharactersIn range: NSRange, with string: String) {}
    func textStorage(_ textStorage: TSYTextStorage, didReplaceCharactersIn range: NSRange, with string: String) {}
    func textStorageWillCompleteProcessingEdit(_ textStorage: TSYTextStorage) {}
    func textStorageDidCompleteProcessingEdit(_ textStorage: TSYTextStorage) {}
    func textStorage(_ textStorage: TSYTextStorage, doubleClickRangeForLocation location: Int) -> NSRange {
        NSRange(location: location, length: 0)
    }
    func textStorage(_ textStorage: TSYTextStorage, nextWordIndexFromLocation location: Int, direction forward: Bool) -> Int {
        location
    }
}

open class TSYTextStorage: NSTextStorage {
    public let internalStorage: NSTextStorage
    public weak var storageDelegate: (any TSYTextStorageDelegate)?
    private var hasProcessedEdit = false

    public init(storage: NSTextStorage) {
        self.internalStorage = storage
        super.init(string: storage.string)
    }

    public override init() {
        self.internalStorage = NSTextStorage(string: "")
        super.init(string: "")
    }

    public override init(string str: String) {
        self.internalStorage = NSTextStorage(string: str)
        super.init(string: str)
    }

    public override init(attributedString attrStr: NSAttributedString) {
        self.internalStorage = NSTextStorage(attributedString: attrStr)
        super.init(attributedString: attrStr)
    }

    public required init?(coder: NSCoder) {
        self.internalStorage = NSTextStorage(string: "")
        super.init(coder: coder)
    }

    open override var string: String {
        internalStorage.string
    }

    open override func replaceCharacters(in range: NSRange, with str: String) {
        storageDelegate?.textStorage(self, willReplaceCharactersIn: range, with: str)
        beginEditing()
        internalStorage.replaceCharacters(in: range, with: str)
        storageDelegate?.textStorage(self, didReplaceCharactersIn: range, with: str)
        edited(.editedCharacters, range: range, changeInLength: str.utf16.count - range.length)
        endEditing()
    }

    open override func attributes(at location: Int, effectiveRange range: NSRangePointer?) -> [NSAttributedString.Key: Any] {
        internalStorage.attributes(at: location, effectiveRange: range)
    }

    open override func setAttributes(_ attrs: [NSAttributedString.Key: Any]?, range: NSRange) {
        beginEditing()
        internalStorage.setAttributes(attrs, range: range)
        edited(.editedAttributes, range: range, changeInLength: 0)
        endEditing()
    }

    open override func processEditing() {
        super.processEditing()
        precondition(!hasProcessedEdit)
        hasProcessedEdit = true
        storageDelegate?.textStorageWillCompleteProcessingEdit(self)
    }

    open override func endEditing() {
        super.endEditing()
        guard hasProcessedEdit else {
            return
        }
        hasProcessedEdit = false
        storageDelegate?.textStorageDidCompleteProcessingEdit(self)
    }
}
