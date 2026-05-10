import XCTest
#if !os(macOS) && !os(iOS)
@testable import QuillShims
#endif

final class QuillShimsTests: XCTestCase {
    
    @MainActor
    func testUIImageShim() async throws {
        #if !os(macOS) && !os(iOS)
        let image = UIImage()
        XCTAssertNotNil(image)
        XCTAssertEqual(image.size, CGSize(width: 0, height: 0))
        #endif
    }
    
    @MainActor
    func testUIViewShim() {
        #if !os(macOS) && !os(iOS)
        let view = UIView()
        XCTAssertNotNil(view)
        XCTAssertEqual(view.subviews.count, 0)
        XCTAssertFalse(view.isHidden)
        XCTAssertEqual(view.alpha, 1.0)
        
        let subview = UIView()
        view.addSubview(subview)
        XCTAssertNotNil(subview)
        #endif
    }
    
    @MainActor
    func testTreeControllerShim() {
        #if !os(macOS) && !os(iOS)
        let delegate = MockTreeDelegate()
        let controller = TreeController(delegate: delegate)
        
        XCTAssertNotNil(controller.rootNode)
        XCTAssertTrue(controller.rootNode.isRoot)
        #endif
    }
}

#if !os(macOS) && !os(iOS)
@MainActor
class MockTreeDelegate: TreeControllerDelegate {
    func treeController(treeController: TreeController, childNodesFor node: Node) -> [Node]? {
        return []
    }
}
#endif
