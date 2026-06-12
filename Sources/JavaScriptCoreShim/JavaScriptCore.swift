import Foundation

public protocol JSExport {}

open class JSValue: NSObject {
    private let storage: Any?

    public init(_ storage: Any? = nil) {
        self.storage = storage
        super.init()
    }

    open var isObject: Bool {
        storage is [String: Any] || storage is NSDictionary
    }

    open func toDictionary() -> [AnyHashable: Any]? {
        if let dictionary = storage as? [AnyHashable: Any] {
            return dictionary
        }
        if let dictionary = storage as? NSDictionary {
            var result: [AnyHashable: Any] = [:]
            for (key, value) in dictionary {
                if let key = key as? AnyHashable {
                    result[key] = value
                }
            }
            return result
        }
        return nil
    }

    @discardableResult
    open func call(withArguments arguments: [Any]?) -> JSValue? {
        _ = arguments
        return nil
    }

    open override var description: String {
        storage.map { String(describing: $0) } ?? "undefined"
    }
}

open class JSContext: NSObject {
    public typealias ExceptionHandler = (JSContext?, JSValue?) -> Void

    open var exceptionHandler: ExceptionHandler?

    public override init() {
        super.init()
    }

    @discardableResult
    open func evaluateScript(_ script: String) -> JSValue? {
        _ = script
        return nil
    }

    @discardableResult
    open func evaluateScript(_ script: String, withSourceURL sourceURL: URL) -> JSValue? {
        _ = (script, sourceURL)
        return nil
    }

    open func setObject(_ object: Any!, forKeyedSubscript key: (NSCopying & NSObjectProtocol)!) {
        _ = (object, key)
    }
}
