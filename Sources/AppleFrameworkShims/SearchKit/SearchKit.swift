#if os(Linux)

import Foundation

public typealias CFIndex = Int
public typealias CFURL = NSURL

public typealias SKIndexType = UInt32
public let kSKIndexUnknown: SKIndexType = 0
public let kSKIndexInverted: SKIndexType = 1
public let kSKIndexVector: SKIndexType = 2
public let kSKIndexInvertedVector: SKIndexType = 3

public typealias SKDocumentID = Int
public typealias SKDocumentIndexState = Int
public let kSKDocumentStateNotIndexed: SKDocumentIndexState = 0
public let kSKDocumentStateIndexed: SKDocumentIndexState = 1
public let kSKDocumentStateAddPending: SKDocumentIndexState = 2
public let kSKDocumentStateDeletePending: SKDocumentIndexState = 3

public typealias SKSearchOptions = UInt32
public let kSKSearchOptionDefault: SKSearchOptions = 0

public let kSKProximityIndexing = "kSKProximityIndexing"
public let kSKStopWords = "kSKStopWords"
public let kSKMinTermLength = "kSKMinTermLength"

public final class SKDocument: NSObject, @unchecked Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
        super.init()
    }
}

public final class SKIndex: NSObject, @unchecked Sendable {
    private var documentsByID: [SKDocumentID: SKDocument] = [:]
    private var idsByURL: [URL: SKDocumentID] = [:]
    private var nextDocumentID: SKDocumentID = 1

    public let url: URL?
    public let name: String?
    public let indexType: SKIndexType
    public let properties: [String: Any]

    public init(url: URL? = nil, name: String? = nil, indexType: SKIndexType = kSKIndexInverted, properties: [String: Any] = [:]) {
        self.url = url
        self.name = name
        self.indexType = indexType
        self.properties = properties
        super.init()
    }

    @discardableResult
    fileprivate func documentID(for document: SKDocument, inserting: Bool) -> SKDocumentID {
        if let existing = idsByURL[document.url] {
            return existing
        }

        guard inserting else {
            return 0
        }

        let id = nextDocumentID
        nextDocumentID += 1
        idsByURL[document.url] = id
        documentsByID[id] = document
        return id
    }

    fileprivate func document(for id: SKDocumentID) -> SKDocument? {
        documentsByID[id]
    }

    fileprivate func remove(_ document: SKDocument) {
        guard let id = idsByURL.removeValue(forKey: document.url) else {
            return
        }
        documentsByID.removeValue(forKey: id)
    }

    fileprivate var allDocuments: [SKDocument] {
        documentsByID.keys.sorted().compactMap { documentsByID[$0] }
    }
}

public final class SKSearch: NSObject, @unchecked Sendable {
    fileprivate let index: SKIndex?
    fileprivate let query: String
    fileprivate var cursor: Int = 0

    public init(index: SKIndex?, query: String) {
        self.index = index
        self.query = query
        super.init()
    }
}

public final class SKIndexDocumentIterator: NSObject, @unchecked Sendable {
    fileprivate let documents: [SKDocument]
    fileprivate var cursor: Int = 0

    fileprivate init(documents: [SKDocument]) {
        self.documents = documents
        super.init()
    }
}

public func SKLoadDefaultExtractorPlugIns() {}

public func SKIndexCreateWithURL(
    _ url: URL,
    _ name: String?,
    _ indexType: SKIndexType,
    _ properties: Any?
) -> Unmanaged<SKIndex>? {
    Unmanaged.passRetained(SKIndex(url: url, name: name, indexType: indexType, properties: dictionary(from: properties)))
}

public func SKIndexOpenWithURL(_ url: URL, _ name: String?, _ writeable: Bool) -> Unmanaged<SKIndex>? {
    _ = writeable
    return Unmanaged.passRetained(SKIndex(url: url, name: name))
}

public func SKIndexCreateWithMutableData(
    _ data: NSMutableData,
    _ name: String?,
    _ indexType: SKIndexType,
    _ properties: Any?
) -> Unmanaged<SKIndex>? {
    _ = data
    return Unmanaged.passRetained(SKIndex(name: name, indexType: indexType, properties: dictionary(from: properties)))
}

public func SKIndexOpenWithMutableData(_ data: NSMutableData, _ name: String?) -> Unmanaged<SKIndex>? {
    _ = data
    return Unmanaged.passRetained(SKIndex(name: name))
}

public func SKIndexFlush(_ index: SKIndex) {
    _ = index
}

public func SKIndexCompact(_ index: SKIndex) {
    _ = index
}

public func SKIndexClose(_ index: SKIndex) {
    _ = index
}

public func SKIndexGetAnalysisProperties(_ index: SKIndex?) -> Unmanaged<NSDictionary> {
    var properties = index?.properties ?? [:]
    properties[kSKStopWords] = properties[kSKStopWords] ?? Set<String>()
    properties[kSKProximityIndexing] = properties[kSKProximityIndexing] ?? false
    properties[kSKMinTermLength] = properties[kSKMinTermLength] ?? UInt(1)
    return Unmanaged.passRetained(properties as NSDictionary)
}

public func SKDocumentCreateWithURL(_ url: URL) -> Unmanaged<SKDocument>? {
    Unmanaged.passRetained(SKDocument(url: url))
}

public func SKDocumentCopyURL(_ document: SKDocument?) -> Unmanaged<CFURL> {
    let url = document?.url ?? URL(fileURLWithPath: "/")
    return retainedCFURL(for: url)
}

public func SKIndexGetDocumentID(_ index: SKIndex, _ document: SKDocument?) -> SKDocumentID {
    guard let document else {
        return 0
    }
    return index.documentID(for: document, inserting: true)
}

public func SKIndexGetDocumentTermCount(_ index: SKIndex, _ documentID: SKDocumentID) -> Int {
    _ = (index, documentID)
    return 0
}

public func SKIndexGetDocumentTermFrequency(_ index: SKIndex, _ documentID: SKDocumentID, _ termID: CFIndex) -> Int {
    _ = (index, documentID, termID)
    return 0
}

public func SKIndexCopyTermIDArrayForDocumentID(_ index: SKIndex, _ documentID: SKDocumentID) -> Unmanaged<NSArray>? {
    _ = (index, documentID)
    return Unmanaged.passRetained([] as NSArray)
}

public func SKIndexCopyTermStringForTermID(_ index: SKIndex, _ termID: CFIndex) -> Unmanaged<NSString>? {
    _ = (index, termID)
    return nil
}

@discardableResult
public func SKIndexAddDocumentWithText(_ index: SKIndex, _ document: SKDocument, _ text: String, _ canReplace: Bool) -> Bool {
    _ = (text, canReplace)
    index.documentID(for: document, inserting: true)
    return true
}

@discardableResult
public func SKIndexAddDocument(_ index: SKIndex, _ document: SKDocument, _ mimeType: String?, _ canReplace: Bool) -> Bool {
    _ = (mimeType, canReplace)
    index.documentID(for: document, inserting: true)
    return true
}

@discardableResult
public func SKIndexRemoveDocument(_ index: SKIndex, _ document: SKDocument) -> Bool {
    index.remove(document)
    return true
}

public func SKIndexGetDocumentState(_ index: SKIndex, _ document: SKDocument?) -> SKDocumentIndexState {
    guard let document else {
        return kSKDocumentStateNotIndexed
    }
    return index.documentID(for: document, inserting: false) == 0 ? kSKDocumentStateNotIndexed : kSKDocumentStateIndexed
}

public func SKIndexDocumentIteratorCreate(_ index: SKIndex, _ parent: SKDocument?) -> Unmanaged<SKIndexDocumentIterator> {
    _ = parent
    return Unmanaged.passRetained(SKIndexDocumentIterator(documents: index.allDocuments))
}

public func SKIndexDocumentIteratorCopyNext(_ iterator: SKIndexDocumentIterator) -> Unmanaged<SKDocument>? {
    guard iterator.cursor < iterator.documents.count else {
        return nil
    }
    let document = iterator.documents[iterator.cursor]
    iterator.cursor += 1
    return Unmanaged.passRetained(document)
}

public func SKSearchCreate(_ index: SKIndex?, _ query: String, _ options: SKSearchOptions) -> Unmanaged<SKSearch> {
    _ = options
    return Unmanaged.passRetained(SKSearch(index: index, query: query))
}

public func SKSearchFindMatches(
    _ search: SKSearch,
    _ maxCount: Int,
    _ documentIDs: UnsafeMutablePointer<SKDocumentID>?,
    _ scores: UnsafeMutablePointer<Float>?,
    _ maxTime: TimeInterval,
    _ foundCount: UnsafeMutablePointer<Int>?
) -> Bool {
    _ = (search.query, maxTime)
    let documents = search.index?.allDocuments ?? []
    let remaining = documents.dropFirst(search.cursor).prefix(max(0, maxCount))

    var written = 0
    for document in remaining {
        guard let id = search.index?.documentID(for: document, inserting: false), id != 0 else {
            continue
        }
        documentIDs?.advanced(by: written).pointee = id
        scores?.advanced(by: written).pointee = 1
        written += 1
    }
    search.cursor += written
    foundCount?.pointee = written
    return search.cursor < documents.count
}

public func SKIndexCopyDocumentURLsForDocumentIDs(
    _ index: SKIndex?,
    _ count: Int,
    _ documentIDs: UnsafeMutablePointer<SKDocumentID>?,
    _ urls: UnsafeMutablePointer<Unmanaged<CFURL>?>?
) {
    guard let index, let documentIDs, let urls else {
        return
    }

    for offset in 0..<max(0, count) {
        let id = documentIDs.advanced(by: offset).pointee
        guard let document = index.document(for: id) else {
            urls.advanced(by: offset).pointee = nil
            continue
        }
        urls.advanced(by: offset).pointee = retainedCFURL(for: document.url)
    }
}

public func SKSearchCancel(_ search: SKSearch) {
    _ = search
}

private func dictionary(from value: Any?) -> [String: Any] {
    switch value {
    case let dictionary as [String: Any]:
        return dictionary
    case let dictionary as NSDictionary:
        var result: [String: Any] = [:]
        for (key, value) in dictionary {
            if let key = key as? String {
                result[key] = value
            }
        }
        return result
    default:
        return [:]
    }
}

private func retainedCFURL(for url: URL) -> Unmanaged<CFURL> {
    Unmanaged.passRetained(NSURL(fileURLWithPath: url.path))
}

public extension Optional where Wrapped == Unmanaged<SKDocument> {
    func takeRetainedValue() -> SKDocument {
        self!.takeRetainedValue()
    }

    func takeUnretainedValue() -> SKDocument {
        self!.takeUnretainedValue()
    }
}

#endif
