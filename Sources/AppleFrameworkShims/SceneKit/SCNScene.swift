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
            try QuillSceneArchiveCodec.load(Data(contentsOf: url), sourceURL: url, into: self)
        } catch let error as SCNSceneShimError {
            throw error
        } catch {
            throw SCNSceneShimError.loadingFailed(url, error)
        }
    }

    public convenience init?(named name: String) {
        self.init(named: name, inDirectory: nil, options: nil)
    }

    public convenience init?(
        named name: String,
        inDirectory directory: String?,
        options: [SCNSceneSource.LoadingOption: Any]? = nil
    ) {
        guard let url = Self.quillNamedSceneURL(named: name, inDirectory: directory) else { return nil }
        self.init()
        do {
            try QuillSceneArchiveCodec.load(Data(contentsOf: url), sourceURL: url, into: self)
        } catch {
            return nil
        }
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

    private static func quillNamedSceneURL(named name: String, inDirectory directory: String?) -> URL? {
        guard !name.isEmpty else { return nil }

        var candidates: [URL] = []
        if name.hasPrefix("/") {
            candidates.append(URL(fileURLWithPath: name))
        }
        if let directory, !directory.isEmpty {
            candidates.append(URL(fileURLWithPath: directory, isDirectory: true).appendingPathComponent(name))
        }
        if let resourceURL = Bundle.main.resourceURL {
            candidates.append(resourceURL.appendingPathComponent(name))
        }
        candidates.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(name))

        return candidates.first { url in
            var isDirectory = ObjCBool(false)
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && !isDirectory.boolValue
        }
    }
}

public enum SCNSceneShimError: Error, CustomStringConvertible {
    case loadingUnsupported(URL)
    case loadingFailed(URL, Error)

    public var description: String {
        switch self {
        case let .loadingUnsupported(url):
            return "SCNScene(url:) cannot load unsupported SceneKit asset format \(url.lastPathComponent); "
                + "QuillOS currently reads Quill scene archives written by SCNScene.write(to:)."
        case let .loadingFailed(url, error):
            return "SCNScene(url:) could not load \(url.lastPathComponent): \(error)"
        }
    }
}

public final class SCNSceneSource: @unchecked Sendable {
    public enum LoadingOption: String, Hashable, Sendable {
        case checkConsistency = "kSceneSourceCheckConsistency"
        case flattenScene = "kSceneSourceFlattenScene"
        case createNormalsIfAbsent = "kSceneSourceCreateNormalsIfAbsent"
        case convertToYUp = "kSceneSourceConvertToYUpIfNeeded"
        case convertUnitsToMeters = "kSceneSourceConvertToUnit"
        case preserveOriginalTopology = "kSceneSourcePreserveOriginalTopology"
        case animationImportPolicy = "kSceneSourceAnimationLoadingMode"
    }

    public enum AnimationImportPolicy: String, Hashable, Sendable {
        case play = "playOnce"
        case playRepeatedly
        case doNotPlay = "keepSeparate"
        case playUsingSceneTimeBase = "playUsingSceneTime"
    }

    public let url: URL?

    public init(url: URL, options: [LoadingOption: Any]? = nil) {
        self.url = url
    }

    public func scene(options: [LoadingOption: Any]? = nil) -> SCNScene? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? QuillSceneArchiveCodec.scene(from: data, sourceURL: url)
    }
}
