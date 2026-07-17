import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Mirror of SwiftUI's `AsyncImagePhase` — the loading state passed to an
/// `AsyncImage` content closure.
public enum AsyncImagePhase {
    case empty
    case success(Image)
    case failure(any Error)

    /// The loaded image, or `nil` while loading / on failure.
    public var image: Image? {
        if case let .success(image) = self { return image }
        return nil
    }

    /// The load error, or `nil` unless the phase is `.failure`.
    public var error: (any Error)? {
        if case let .failure(error) = self { return error }
        return nil
    }
}

final class AsyncImageLoader: ObservableObject, @unchecked Sendable {
    let objectWillChange = ObservableObjectPublisher()

    private let lock = NSLock()
    private let url: URL?
    private var phase: AsyncImagePhase = .empty
    private var didStart = false

    init(url: URL?) {
        self.url = url
    }

    func phaseStartingIfNeeded() -> AsyncImagePhase {
        lock.lock()
        let currentPhase = phase
        let shouldStart = !didStart
        didStart = true
        lock.unlock()

        if shouldStart {
            Task { @MainActor [weak self] in
                await self?.load()
            }
        }
        return currentPhase
    }

    @MainActor
    private func load() async {
        guard let url else {
            updatePhase(.failure(URLError(.badURL)))
            return
        }
        if let cachedPath = AsyncImageFileCache.shared.filePath(for: url) {
            updatePhase(.success(Image(filePath: cachedPath)))
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let path = try AsyncImageFileCache.shared.store(data, for: url)
            updatePhase(.success(Image(filePath: path)))
        } catch {
            updatePhase(.failure(error))
        }
    }

    @MainActor
    private func updatePhase(_ newPhase: AsyncImagePhase) {
        lock.lock()
        phase = newPhase
        lock.unlock()
        objectWillChange.send()
    }
}

final class AsyncImageLoaderRegistry: @unchecked Sendable {
    static let shared = AsyncImageLoaderRegistry()

    private final class WeakLoader: @unchecked Sendable {
        weak var value: AsyncImageLoader?

        init(_ value: AsyncImageLoader) {
            self.value = value
        }
    }

    private enum Key: Hashable {
        case url(URL)
        case missingURL
    }

    private let lock = NSLock()
    private var loaders: [Key: WeakLoader] = [:]

    func loader(for url: URL?) -> AsyncImageLoader {
        let key = url.map(Key.url) ?? .missingURL
        lock.lock()
        if let existing = loaders[key]?.value {
            lock.unlock()
            return existing
        }
        loaders = loaders.filter { $0.value.value != nil }
        let loader = AsyncImageLoader(url: url)
        loaders[key] = WeakLoader(loader)
        lock.unlock()
        return loader
    }
}

/// Mirror of SwiftUI's `AsyncImage`: asynchronously loads and displays an
/// image from a URL, showing a placeholder until it arrives.
///
/// The image is fetched with `URLSession` to a temporary file and then
/// rendered through the existing `Image(filePath:)` backend path, so no
/// backend-specific async-image rendering is needed — every backend that
/// can draw a file-backed `Image` gets `AsyncImage` for free.
///
/// Unlike Apple's generic `AsyncImage<Content>`, this is type-erased over
/// `AnyView`. The public initializers match SwiftUI exactly, so call sites
/// like `AsyncImage(url:) { $0.resizable() } placeholder: { Color.gray }`
/// compile unchanged; the erasure is invisible to callers.
public struct AsyncImage: View {
    private let url: URL?
    private let scale: CGFloat
    private let contentForPhase: (AsyncImagePhase) -> AnyView

    @ObservedObject private var loader: AsyncImageLoader

    /// Phase-based form: the content closure sees every loading phase
    /// (`.empty` / `.success` / `.failure`). Mirrors
    /// `AsyncImage(url:scale:transaction:content:)`.
    public init<C: View>(
        url: URL?,
        scale: CGFloat = 1,
        @ViewBuilder content: @escaping (AsyncImagePhase) -> C
    ) {
        self.url = url
        self.scale = scale
        self.contentForPhase = { phase in AnyView(content(phase)) }
        self._loader = ObservedObject(
            wrappedValue: AsyncImageLoaderRegistry.shared.loader(for: url)
        )
    }

    /// Content + placeholder form: transform the loaded `Image`, with a
    /// placeholder shown until it loads (or on failure). Mirrors
    /// `AsyncImage(url:scale:content:placeholder:)`.
    public init<I: View, P: View>(
        url: URL?,
        scale: CGFloat = 1,
        @ViewBuilder content: @escaping (Image) -> I,
        @ViewBuilder placeholder: @escaping () -> P
    ) {
        self.url = url
        self.scale = scale
        self.contentForPhase = { phase in
            if let image = phase.image {
                return AnyView(content(image))
            }
            return AnyView(placeholder())
        }
        self._loader = ObservedObject(
            wrappedValue: AsyncImageLoaderRegistry.shared.loader(for: url)
        )
    }

    /// Simplest form: the loaded image, or a neutral gray placeholder.
    /// Mirrors `AsyncImage(url:scale:)`.
    public init(url: URL?, scale: CGFloat = 1) {
        self.url = url
        self.scale = scale
        self.contentForPhase = { phase in
            if let image = phase.image {
                return AnyView(image)
            }
            return AnyView(Color.gray)
        }
        self._loader = ObservedObject(
            wrappedValue: AsyncImageLoaderRegistry.shared.loader(for: url)
        )
    }

    public var body: some View {
        contentForPhase(loader.phaseStartingIfNeeded())
    }
}

private final class AsyncImageFileCache: @unchecked Sendable {
    static let shared = AsyncImageFileCache()

    private let lock = NSLock()
    private var paths: [URL: String] = [:]

    func filePath(for url: URL) -> String? {
        lock.lock()
        let path = paths[url]
        lock.unlock()
        guard let path, FileManager.default.fileExists(atPath: path) else {
            return nil
        }
        return path
    }

    func store(_ data: Data, for url: URL) throws -> String {
        if let path = filePath(for: url) {
            return path
        }

        let fileExtension = url.pathExtension
        let filename = "swiftopenui-asyncimage-\(UUID().uuidString)"
            + (fileExtension.isEmpty ? "" : ".\(fileExtension)")
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent(filename)
        try data.write(to: file, options: [.atomic])

        lock.lock()
        paths[url] = file.path
        lock.unlock()
        return file.path
    }
}
