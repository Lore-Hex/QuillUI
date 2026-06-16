// SceneKit shim — the scene container and its loader.
import Foundation
import QuillFoundation

public final class SCNScene: @unchecked Sendable {
    public let rootNode = SCNNode()
    /// `background.contents` accepts an NSColor / CGColor / image, as on macOS.
    public let background = SCNMaterialProperty()
    public let lightingEnvironment = SCNMaterialProperty()
    public var fogColor: Any?
    public var fogStartDistance: CGFloat = 0
    public var fogEndDistance: CGFloat = 0
    public var isPaused = false

    public init() {}

    /// Loading a scene from a URL is a rung-4 concern (it needs the model
    /// importers). Until then this throws, matching the throwing macOS API
    /// shape so callers compile unmodified.
    public init(url: URL, options: [SCNSceneSource.LoadingOption: Any]? = nil) throws {
        throw SCNSceneShimError.loadingUnsupported(url)
    }

    public init(named name: String) {
        // Empty scene; the named-asset catalog is not modeled on QuillOS yet.
    }

    /// Exporting a scene to a model file (.scn/.dae/.obj/…) is a rung-4
    /// concern (it needs the exporters). The API shape matches macOS so
    /// callers — e.g. Euclid's `Mesh` writers — compile unmodified; it
    /// reports failure until the exporters land.
    @discardableResult
    public func write(
        to url: URL,
        options: [String: Any]? = nil,
        delegate: Any? = nil,
        progressHandler: ((Float, Error?, UnsafeMutablePointer<ObjCBool>) -> Void)? = nil
    ) -> Bool {
        false
    }
}

public enum SCNSceneShimError: Error, CustomStringConvertible {
    case loadingUnsupported(URL)

    public var description: String {
        switch self {
        case let .loadingUnsupported(url):
            return "SCNScene(url:) is not yet supported on QuillOS (\(url.lastPathComponent))"
        }
    }
}

public final class SCNSceneSource: @unchecked Sendable {
    public enum LoadingOption: String, Hashable, Sendable {
        case checkConsistency
        case flattenScene
        case createNormalsIfAbsent
        case convertToYUp
        case convertUnitsToMeters
        case preserveOriginalTopology
        case animationImportPolicy
    }

    public let url: URL?

    public init(url: URL, options: [LoadingOption: Any]? = nil) {
        self.url = url
    }

    public func scene(options: [LoadingOption: Any]? = nil) -> SCNScene? {
        nil
    }
}
