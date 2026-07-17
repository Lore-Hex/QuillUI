import Foundation
import XCTest
@testable import SwiftOpenUI

final class AsyncImageTests: XCTestCase {
    func testAsyncImagePhaseAccessors() {
        let success = AsyncImagePhase.success(Image(systemName: "photo"))
        XCTAssertNotNil(success.image)
        XCTAssertNil(success.error)

        XCTAssertNil(AsyncImagePhase.empty.image)
        XCTAssertNil(AsyncImagePhase.empty.error)

        let failure = AsyncImagePhase.failure(URLError(.badURL))
        XCTAssertNil(failure.image)
        XCTAssertNotNil(failure.error)
    }

    func testAsyncImageInitializersMatchSwiftUI() {
        // Constructing all three SwiftUI-shaped initializers IS the assertion:
        // the test fails to compile if the mirror's API diverges from SwiftUI,
        // so call sites like `AsyncImage(url:) { $0.resizable() } placeholder:`
        // are guaranteed to bind unchanged.
        _ = AsyncImage(url: nil) { phase in
            phase.image == nil ? Color.gray : Color.clear
        }
        _ = AsyncImage(url: URL(string: "https://example.test/a.png")) { image in
            image.resizable()
        } placeholder: {
            Color.gray
        }
        _ = AsyncImage(url: nil)
    }

    func testAsyncImageLoaderRegistryReusesLoaderForMatchingURL() {
        let firstURL = URL(string: "https://example.test/\(UUID().uuidString).png")!
        let secondURL = URL(string: "https://example.test/\(UUID().uuidString).png")!

        let first = AsyncImageLoaderRegistry.shared.loader(for: firstURL)
        let matching = AsyncImageLoaderRegistry.shared.loader(for: firstURL)
        let different = AsyncImageLoaderRegistry.shared.loader(for: secondURL)

        XCTAssertTrue(first === matching)
        XCTAssertFalse(first === different)
    }

    func testAsyncImageLoaderReportsMissingURLFailure() async {
        let loader = AsyncImageLoader(url: nil)
        XCTAssertNil(loader.phaseStartingIfNeeded().error)

        for _ in 0..<100 where loader.phaseStartingIfNeeded().error == nil {
            await Task.yield()
        }

        let failure = loader.phaseStartingIfNeeded().error as? URLError
        XCTAssertEqual(failure?.code, .badURL)
    }
}
