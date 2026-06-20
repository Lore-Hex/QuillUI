#if os(Linux)
import Foundation

open class NSScriptClassDescription: NSObject {
    public var quillScriptClassName: String

    public init(className: String = "") {
        self.quillScriptClassName = className
        super.init()
    }
}

open class NSScriptObjectSpecifier: NSObject {
    open var containerClassDescription: NSScriptClassDescription?
    open var containerSpecifier: NSScriptObjectSpecifier?
    open var key: String
    open var evaluatedObject: Any?

    public override init() {
        self.containerClassDescription = nil
        self.containerSpecifier = nil
        self.key = ""
        self.evaluatedObject = nil
        super.init()
    }

    public init?(
        descriptor: NSAppleEventDescriptor
    ) {
        self.containerClassDescription = nil
        self.containerSpecifier = nil
        self.key = descriptor.stringValue ?? ""
        self.evaluatedObject = nil
        super.init()
    }

    public init(
        containerClassDescription: NSScriptClassDescription,
        containerSpecifier: NSScriptObjectSpecifier?,
        key: String
    ) {
        self.containerClassDescription = containerClassDescription
        self.containerSpecifier = containerSpecifier
        self.key = key
        self.evaluatedObject = nil
        super.init()
    }

    open var objectsByEvaluatingSpecifier: Any? {
        evaluatedObject
    }

    open func objectsByEvaluating(withContainers containers: Any) -> Any? {
        evaluatedObject ?? containers
    }
}

open class NSNameSpecifier: NSScriptObjectSpecifier {
    open var name: String

    public init(
        containerClassDescription: NSScriptClassDescription,
        containerSpecifier: NSScriptObjectSpecifier?,
        key: String,
        name: String
    ) {
        self.name = name
        super.init(containerClassDescription: containerClassDescription, containerSpecifier: containerSpecifier, key: key)
    }
}

open class NSUniqueIDSpecifier: NSScriptObjectSpecifier {
    open var uniqueID: Any

    public init(
        containerClassDescription: NSScriptClassDescription,
        containerSpecifier: NSScriptObjectSpecifier?,
        key: String,
        uniqueID: Any
    ) {
        self.uniqueID = uniqueID
        super.init(containerClassDescription: containerClassDescription, containerSpecifier: containerSpecifier, key: key)
    }
}

open class NSScriptCommand: NSObject {
    open var arguments: [String: Any]?
    open var evaluatedArguments: [String: Any]?
    open var appleEvent: NSAppleEventDescriptor?
    open var createClassDescription: NSScriptClassDescription
    open var receiversSpecifier: NSScriptObjectSpecifier?
    open var keySpecifier: NSScriptObjectSpecifier
    public private(set) var isExecutionSuspended = false
    public private(set) var resumedResult: Any?

    public init(
        arguments: [String: Any]? = nil,
        evaluatedArguments: [String: Any]? = nil,
        appleEvent: NSAppleEventDescriptor? = nil,
        createClassDescription: NSScriptClassDescription = NSScriptClassDescription(),
        receiversSpecifier: NSScriptObjectSpecifier? = nil,
        keySpecifier: NSScriptObjectSpecifier = NSScriptObjectSpecifier()
    ) {
        self.arguments = arguments
        self.evaluatedArguments = evaluatedArguments
        self.appleEvent = appleEvent
        self.createClassDescription = createClassDescription
        self.receiversSpecifier = receiversSpecifier
        self.keySpecifier = keySpecifier
        super.init()
    }

    open func performDefaultImplementation() -> Any? {
        nil
    }

    open func suspendExecution() {
        isExecutionSuspended = true
    }

    open func resumeExecution(withResult result: Any?) {
        isExecutionSuspended = false
        resumedResult = result
    }
}

open class NSCreateCommand: NSScriptCommand {}
open class NSDeleteCommand: NSScriptCommand {}

open class NSExistsCommand: NSScriptCommand {
    open override func performDefaultImplementation() -> Any? {
        true as NSNumber
    }
}

public extension NSObject {
    var classDescription: Any {
        NSScriptClassDescription(className: String(describing: type(of: self)))
    }
}
#endif
