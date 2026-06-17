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

    public init(url: URL, options: [SCNSceneSource.LoadingOption: Any]? = nil) throws {
        do {
            try QuillSceneArchiveCodec.load(Data(contentsOf: url), into: self)
        } catch let error as SCNSceneShimError {
            throw error
        } catch {
            throw SCNSceneShimError.loadingFailed(url, error)
        }
    }

    public init(named name: String) {
        // Empty scene; the named-asset catalog is not modeled on QuillOS yet.
    }

    public func quillStepActions(by deltaTime: TimeInterval) {
        guard !isPaused else { return }
        rootNode.quillStepActions(by: deltaTime)
    }

    /// Writes Quill's deterministic SceneKit archive format. This is not a
    /// `.scn`/`.dae`/`.obj` exporter; it preserves the scene-graph subset this
    /// shim can render and reloads through `SCNSceneSource`/`SCNScene(url:)`.
    @discardableResult
    public func write(
        to url: URL,
        options: [String: Any]? = nil,
        delegate: Any? = nil,
        progressHandler: ((Float, Error?, UnsafeMutablePointer<ObjCBool>) -> Void)? = nil
    ) -> Bool {
        var stop = ObjCBool(false)
        progressHandler?(0, nil, &stop)
        guard !stop.boolValue else { return false }

        do {
            let data = try QuillSceneArchiveCodec.data(for: self)
            try data.write(to: url, options: [.atomic])
            progressHandler?(1, nil, &stop)
            return !stop.boolValue
        } catch {
            progressHandler?(1, error, &stop)
            return false
        }
    }
}

public enum SCNSceneShimError: Error, CustomStringConvertible {
    case loadingUnsupported(URL)
    case loadingFailed(URL, Error)

    public var description: String {
        switch self {
        case let .loadingUnsupported(url):
            return "SCNScene(url:) is not yet supported on QuillOS (\(url.lastPathComponent))"
        case let .loadingFailed(url, error):
            return "SCNScene(url:) could not load \(url.lastPathComponent): \(error)"
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
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? QuillSceneArchiveCodec.scene(from: data)
    }
}
