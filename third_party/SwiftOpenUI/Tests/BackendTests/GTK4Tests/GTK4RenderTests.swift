import XCTest
import Foundation
import SwiftOpenUI
@testable import BackendGTK4
import CGTK
import CGTKBridge

final class GTK4RenderTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        if gtk_is_initialized() == 0 {
            _ = gtk_init_check()
        }
    }

    func testViewHostAllocationConstraintDoesNotChaseGrowth() {
        XCTAssertTrue(gtkShouldTightenViewHostConstraint(
            allocated: 640,
            previouslyConstrained: -1
        ))
        XCTAssertTrue(gtkShouldTightenViewHostConstraint(
            allocated: 560,
            previouslyConstrained: 640
        ))
        XCTAssertFalse(gtkShouldTightenViewHostConstraint(
            allocated: 700,
            previouslyConstrained: 640
        ))
        XCTAssertFalse(gtkShouldTightenViewHostConstraint(
            allocated: 640,
            previouslyConstrained: 640
        ))
        XCTAssertFalse(gtkShouldTightenViewHostConstraint(
            allocated: 1,
            previouslyConstrained: -1
        ))
    }

    func testFrameViewCentersTextUsingFixedChildPosition() throws {
        try requireGTK()

        let wrapper = widgetFromOpaque(gtkRenderView(Text("Hi").frame(width: 56, height: 56)))
        let child = try unwrapFirstChild(of: wrapper)

        let wrapperSize = measuredSize(of: wrapper)
        allocate(widget: wrapper, size: wrapperSize)
        let childSize = allocatedSize(of: child)
        let childOrigin = translatedChildOrigin(child: child, in: wrapper)

        XCTAssertEqual(wrapperSize.width, 56, accuracy: 0.01)
        XCTAssertEqual(wrapperSize.height, 56, accuracy: 0.01)
        XCTAssertEqual(childOrigin.x, (56 - childSize.width) / 2, accuracy: 0.01)
        XCTAssertEqual(childOrigin.y, (56 - childSize.height) / 2, accuracy: 0.01)
    }

    func testFrameViewExpandsColorToFillFixedFrame() throws {
        try requireGTK()

        let wrapper = widgetFromOpaque(gtkRenderView(Color.red.frame(width: 50, height: 24)))
        let child = try unwrapFirstChild(of: wrapper)

        let wrapperSize = measuredSize(of: wrapper)
        allocate(widget: wrapper, size: wrapperSize)
        let childSize = allocatedSize(of: child)
        let childOrigin = translatedChildOrigin(child: child, in: wrapper)

        XCTAssertEqual(wrapperSize.width, 50, accuracy: 0.01)
        XCTAssertEqual(wrapperSize.height, 24, accuracy: 0.01)
        XCTAssertEqual(childSize.width, 50, accuracy: 0.01)
        XCTAssertEqual(childSize.height, 24, accuracy: 0.01)
        XCTAssertEqual(childOrigin.x, 0, accuracy: 0.01)
        XCTAssertEqual(childOrigin.y, 0, accuracy: 0.01)
    }

    func testFrameViewExpandsShapeOverlayContentToFillFixedFrame() throws {
        try requireGTK()

        let wrapper = widgetFromOpaque(gtkRenderView(
            Group {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(red: 0.28, green: 0.52, blue: 0.86))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.gray, style: StrokeStyle(lineWidth: 1))
                    )
            }
            .frame(width: 160, height: 90, alignment: .topLeading)
        ))
        let slot = try unwrapFirstChild(of: wrapper)
        let overlay = try unwrapFirstDescendant(ofType: "GtkOverlay", in: slot)
        let drawingArea = try unwrapFirstDescendant(ofType: "GtkDrawingArea", in: overlay)

        let wrapperSize = measuredSize(of: wrapper)
        allocate(widget: wrapper, size: wrapperSize)
        let slotSize = allocatedSize(of: slot)
        let overlaySize = allocatedSize(of: overlay)
        let drawingAreaSize = allocatedSize(of: drawingArea)
        let slotOrigin = translatedChildOrigin(child: slot, in: wrapper)

        XCTAssertEqual(wrapperSize.width, 160, accuracy: 0.01)
        XCTAssertEqual(wrapperSize.height, 90, accuracy: 0.01)
        XCTAssertEqual(slotSize.width, 160, accuracy: 0.01)
        XCTAssertEqual(slotSize.height, 90, accuracy: 0.01)
        XCTAssertEqual(overlaySize.width, 160, accuracy: 0.01)
        XCTAssertEqual(overlaySize.height, 90, accuracy: 0.01)
        XCTAssertEqual(drawingAreaSize.width, 160, accuracy: 0.01)
        XCTAssertEqual(drawingAreaSize.height, 90, accuracy: 0.01)
        XCTAssertEqual(slotOrigin.x, 0, accuracy: 0.01)
        XCTAssertEqual(slotOrigin.y, 0, accuracy: 0.01)
    }

    func testClippedViewPreservesFixedFrameNaturalWidth() throws {
        try requireGTK()

        let wrapper = widgetFromOpaque(gtkRenderView(
            Color(red: 0.28, green: 0.52, blue: 0.86)
                .frame(width: 160, height: 90)
                .clipped()
        ))
        let child = try unwrapFirstChild(of: wrapper)

        let wrapperSize = measuredSize(of: wrapper)
        allocate(widget: wrapper, size: wrapperSize)
        let childSize = allocatedSize(of: child)

        XCTAssertEqual(wrapperSize.width, 160, accuracy: 0.01)
        XCTAssertEqual(wrapperSize.height, 90, accuracy: 0.01)
        XCTAssertEqual(childSize.width, 160, accuracy: 0.01)
        XCTAssertEqual(childSize.height, 90, accuracy: 0.01)
    }

    func testFrameViewClampsOversizedChildHeight() throws {
        try requireGTK()

        let childText = Text("Tall")
        let naturalChild = widgetFromOpaque(gtkRenderView(childText))
        let naturalSize = measuredSize(of: naturalChild)
        XCTAssertGreaterThan(naturalSize.height, 8)

        let wrapper = widgetFromOpaque(gtkRenderView(
            childText.frame(minWidth: 60, maxHeight: 8, alignment: .leading)
        ))
        let slot = try unwrapFirstChild(of: wrapper)
        let innerText = try unwrapFirstDescendant(
            ofType: "GtkLabel",
            in: slot
        )

        let wrapperSize = measuredSize(of: wrapper)
        allocate(widget: wrapper, size: wrapperSize)
        let slotSize = allocatedSize(of: slot)
        let innerTextSize = allocatedSize(of: innerText)
        let slotOrigin = translatedChildOrigin(child: slot, in: wrapper)

        XCTAssertEqual(wrapperSize.width, 60, accuracy: 0.01)
        XCTAssertEqual(wrapperSize.height, 8, accuracy: 0.01)
        XCTAssertEqual(slotSize.height, 8, accuracy: 0.01)
        XCTAssertGreaterThan(innerTextSize.height, 8)
        XCTAssertEqual(slotOrigin.x, 0, accuracy: 0.01)
        XCTAssertEqual(slotOrigin.y, 0, accuracy: 0.01)
        XCTAssertEqual(gtk_widget_get_overflow(wrapper), GTK_OVERFLOW_HIDDEN)
    }

    func testCustomSystemCalloutSizeFitsTwentyPointFrame() throws {
        try requireGTK()

        let label = widgetFromOpaque(gtkRenderView(
            Text("status.summary.n-favorites 42")
                .font(.system(size: 16))
        ))

        let labelSize = measuredSize(of: label)

        XCTAssertLessThanOrEqual(labelSize.height, 20)
    }

    func testVStackSharedLayoutAppliesTrailingAlignmentAndSpacing() throws {
        try requireGTK()

        let wrapper = widgetFromOpaque(gtkRenderView(
            VStack(alignment: .trailing, spacing: 4) {
                Text("WWWWWW")
                Text("I")
            }
        ))
        let first = try unwrapFirstChild(of: wrapper)
        let second = try unwrapNextSibling(of: first)

        let wrapperSize = measuredSize(of: wrapper)
        allocate(widget: wrapper, size: wrapperSize)

        let firstSize = allocatedSize(of: first)
        let secondSize = allocatedSize(of: second)
        let firstOrigin = translatedChildOrigin(child: first, in: wrapper)
        let secondOrigin = translatedChildOrigin(child: second, in: wrapper)

        XCTAssertEqual(firstOrigin.x, 0, accuracy: 0.01)
        XCTAssertEqual(firstOrigin.y, 0, accuracy: 0.01)
        XCTAssertEqual(secondOrigin.x, wrapperSize.width - secondSize.width, accuracy: 0.01)
        XCTAssertEqual(secondOrigin.y, firstSize.height + 4, accuracy: 0.01)
    }

    func testHStackSharedLayoutAppliesBottomAlignmentAndSpacing() throws {
        try requireGTK()

        let wrapper = widgetFromOpaque(gtkRenderView(
            HStack(alignment: .bottom, spacing: 6) {
                Text("Tall")
                Text("I")
            }
        ))
        let first = try unwrapFirstChild(of: wrapper)
        let second = try unwrapNextSibling(of: first)

        let wrapperSize = measuredSize(of: wrapper)
        allocate(widget: wrapper, size: wrapperSize)

        let firstSize = allocatedSize(of: first)
        let secondSize = allocatedSize(of: second)
        let firstOrigin = translatedChildOrigin(child: first, in: wrapper)
        let secondOrigin = translatedChildOrigin(child: second, in: wrapper)

        XCTAssertEqual(firstOrigin.x, 0, accuracy: 0.01)
        XCTAssertEqual(firstOrigin.y, 0, accuracy: 0.01)
        XCTAssertEqual(secondOrigin.x, firstSize.width + 6, accuracy: 0.01)
        XCTAssertEqual(secondOrigin.y, wrapperSize.height - secondSize.height, accuracy: 0.01)
    }

    func testZStackSharedLayoutAppliesBottomTrailingAlignment() throws {
        try requireGTK()

        let wrapper = widgetFromOpaque(gtkRenderView(
            ZStack(alignment: .bottomTrailing) {
                Text("WWWWWW")
                Text("I")
            }
        ))
        let first = try unwrapFirstChild(of: wrapper)
        let second = try unwrapNextSibling(of: first)

        let wrapperSize = measuredSize(of: wrapper)
        allocate(widget: wrapper, size: wrapperSize)

        let firstOrigin = translatedChildOrigin(child: first, in: wrapper)
        let secondSize = allocatedSize(of: second)
        let secondOrigin = translatedChildOrigin(child: second, in: wrapper)

        XCTAssertEqual(firstOrigin.x, 0, accuracy: 0.01)
        XCTAssertEqual(firstOrigin.y, 0, accuracy: 0.01)
        XCTAssertEqual(secondOrigin.x, wrapperSize.width - secondSize.width, accuracy: 0.01)
        XCTAssertEqual(secondOrigin.y, wrapperSize.height - secondSize.height, accuracy: 0.01)
    }

    func testZStackFallbackAppliesBottomTrailingAlignment() throws {
        try requireGTK()

        let wrapper = widgetFromOpaque(gtkRenderView(
            ZStack(alignment: .bottomTrailing) {
                Text("WWWWWW")
                Color.red
                Text("I")
            }
        ))
        let base = try unwrapFirstChild(of: wrapper)
        let colorOverlay = try unwrapNextSibling(of: base)
        let trailingOverlay = try unwrapNextSibling(of: colorOverlay)

        let wrapperSize = measuredSize(of: wrapper)
        allocate(widget: wrapper, size: wrapperSize)

        let baseOrigin = translatedChildOrigin(child: base, in: wrapper)
        let trailingSize = allocatedSize(of: trailingOverlay)
        let trailingOrigin = translatedChildOrigin(child: trailingOverlay, in: wrapper)

        XCTAssertEqual(gtkWidgetTypeName(wrapper), "GtkOverlay")
        XCTAssertEqual(baseOrigin.x, 0, accuracy: 0.01)
        XCTAssertEqual(baseOrigin.y, 0, accuracy: 0.01)
        XCTAssertEqual(trailingOrigin.x, wrapperSize.width - trailingSize.width, accuracy: 0.01)
        XCTAssertEqual(trailingOrigin.y, wrapperSize.height - trailingSize.height, accuracy: 0.01)
    }

    func testZStackTopOverlayDoesNotFillHeightFromUnmarkedVExpand() throws {
        try requireGTK()

        let wrapper = widgetFromOpaque(gtkRenderView(
            ZStack(alignment: .top) {
                Color.gray
                GTKAccidentalVExpandOverlayProbe()
            }
        ))
        let base = try unwrapFirstChild(of: wrapper)
        let overlay = try unwrapNextSibling(of: base)

        allocate(widget: wrapper, size: ViewSize(width: 320, height: 280))

        let overlaySize = allocatedSize(of: overlay)
        let overlayOrigin = translatedChildOrigin(child: overlay, in: wrapper)

        XCTAssertEqual(gtkWidgetTypeName(wrapper), "GtkOverlay")
        XCTAssertEqual(overlayOrigin.y, 0, accuracy: 0.01)
        XCTAssertLessThan(
            overlaySize.height,
            120,
            "Inherited GTK vexpand without SwiftUI fill intent must not make a top ZStack overlay cover the whole container."
        )
    }

    func testZStackTopOverlayFillsHeightForExplicitFlexibleFrame() throws {
        try requireGTK()

        let wrapper = widgetFromOpaque(gtkRenderView(
            ZStack(alignment: .top) {
                Color.gray
                Text("Fill")
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        ))
        let base = try unwrapFirstChild(of: wrapper)
        let overlay = try unwrapNextSibling(of: base)

        allocate(widget: wrapper, size: ViewSize(width: 320, height: 280))

        XCTAssertEqual(gtkWidgetTypeName(wrapper), "GtkOverlay")
        XCTAssertGreaterThan(
            allocatedSize(of: overlay).height,
            240,
            "An explicit SwiftUI maxHeight frame should still fill a ZStack overlay vertically."
        )
    }

    func testEmptyBranchModifiersCollapseBeforeFlexibleFrame() throws {
        try requireGTK()

        let absent = Optional<Text>.none
        let wrapper = widgetFromOpaque(gtkRenderView(
            absent
                .buttonStyle(.bordered)
                .background(Color.red)
                .cornerRadius(8)
                .foregroundStyle(Color.gray)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.blue, lineWidth: 1)
                )
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        ))

        XCTAssertEqual(measuredSize(of: wrapper).width, 0, accuracy: 0.01)
        XCTAssertEqual(measuredSize(of: wrapper).height, 0, accuracy: 0.01)
        XCTAssertEqual(gtk_widget_get_hexpand(wrapper), 0)
        XCTAssertEqual(gtk_widget_get_vexpand(wrapper), 0)
        XCTAssertEqual(gtk_widget_get_can_target(wrapper), 0)
    }

    func testZStackDropsEmptyFlexibleOverlayBranch() throws {
        try requireGTK()

        let absent = Optional<Text>.none
        let wrapper = widgetFromOpaque(gtkRenderView(
            ZStack(alignment: .top) {
                Text("Timeline")
                absent
                    .buttonStyle(.bordered)
                    .background(Color.red)
                    .cornerRadius(8)
                    .foregroundStyle(Color.gray)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.blue, lineWidth: 1)
                    )
                    .padding(8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        ))

        var labels: [UnsafeMutablePointer<GtkWidget>] = []
        gtkCollectLabels(in: wrapper, into: &labels)
        XCTAssertEqual(
            labels.map { String(cString: gtk_label_get_text(OpaquePointer($0))) },
            ["Timeline"]
        )

        let firstChild = try unwrapFirstChild(of: wrapper)
        XCTAssertNil(
            gtk_widget_get_next_sibling(firstChild),
            "The absent overlay branch must not be materialized as a second ZStack child."
        )
    }

    func testListSkipsStatefulRowsWhoseBodyIsCurrentlyEmpty() throws {
        try requireGTK()

        let wrapper = widgetFromOpaque(gtkRenderView(
            List {
                GTKEmptyStatefulRowProbe()
                Text("Visible row")
            }
            .frame(width: 360, height: 180)
        ))

        let window = presentGTKWidget(wrapper)
        defer {
            gtk_window_destroy(windowPointer(window))
            drainGTKMainContext(maxIterations: 100)
        }
        allocate(widget: wrapper, size: ViewSize(width: 360, height: 180))
        drainGTKMainContext(maxIterations: 100)

        var labels: [UnsafeMutablePointer<GtkWidget>] = []
        gtkCollectLabels(in: wrapper, into: &labels)
        XCTAssertEqual(
            labels.map { String(cString: gtk_label_get_text(OpaquePointer($0))) },
            ["Visible row"]
        )
        XCTAssertEqual(
            gtkCountDescendants(ofType: "GtkListBoxRow", in: wrapper),
            1,
            "Stateful EmptyView rows should be skipped instead of materializing blank timeline rows."
        )
    }

    func testListHonorsOptionalExplicitFrameHeightThroughLifecycleWrappers() throws {
        try requireGTK()

        var appeared = false
        let wrapper = widgetFromOpaque(gtkRenderView(
            List {
                GTKOnePixelListAnchor()
                    .frame(height: 1)
                    .onAppear { appeared = true }
                    .onDisappear {}
                Text("Visible row")
            }
            .environment(\.defaultMinListRowHeight, 1)
            .frame(width: 360, height: 180)
        ))

        let window = presentGTKWidget(wrapper)
        defer {
            gtk_window_destroy(windowPointer(window))
            drainGTKMainContext(maxIterations: 100)
        }
        allocate(widget: wrapper, size: ViewSize(width: 360, height: 180))
        drainGTKMainContext(maxIterations: 100)

        let firstRow = try unwrapFirstDescendant(ofType: "GtkListBoxRow", in: wrapper)
        let firstRowSize = allocatedSize(of: firstRow)
        XCTAssertLessThanOrEqual(
            firstRowSize.height,
            4,
            "A one-pixel framed List anchor row should not fall back to the complex-row minimum height."
        )

        let visibleLabel = try unwrapFirstDescendant(ofType: "GtkLabel", in: wrapper)
        let labelOrigin = translatedChildOrigin(child: visibleLabel, in: wrapper)
        XCTAssertLessThan(
            labelOrigin.y,
            80,
            "The visible row should remain near the top instead of being pushed down by an expanded hidden anchor."
        )
        XCTAssertTrue(appeared)
    }

    func testListDefaultMinRowHeightControlsCompactComplexRows() throws {
        try requireGTK()

        let wrapper = widgetFromOpaque(gtkRenderView(
            List {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Explore Fixture").font(.headline)
                    Text("@explorer").font(.subheadline)
                }
            }
            .environment(\.defaultMinListRowHeight, 1)
            .frame(width: 360, height: 180)
        ))

        let window = presentGTKWidget(wrapper)
        defer {
            gtk_window_destroy(windowPointer(window))
            drainGTKMainContext(maxIterations: 100)
        }
        allocate(widget: wrapper, size: ViewSize(width: 360, height: 180))
        drainGTKMainContext(maxIterations: 100)

        let row = try unwrapFirstDescendant(ofType: "GtkListBoxRow", in: wrapper)
        let rowSize = allocatedSize(of: row)
        XCTAssertLessThan(
            rowSize.height,
            80,
            "Compact multi-label List rows must respect defaultMinListRowHeight instead of using the status-row estimate as a hard minimum."
        )
        XCTAssertGreaterThan(
            rowSize.height,
            20,
            "The compact row should still allocate enough natural height for its labels."
        )
    }

    func testHorizontalScrollViewListRowUsesContentHeight() throws {
        try requireGTK()

        let wrapper = widgetFromOpaque(gtkRenderView(
            List {
                ScrollView(.horizontal) {
                    HStack {
                        Button("News") {}
                        Button("Trending Posts") {}
                        Button("Suggested Users") {}
                        Button("Trending Tags") {}
                    }
                    .padding(16)
                }
                .listRowInsets(.init())
                .listRowSeparator(.hidden)

                Text("Visible section")
            }
            .frame(width: 360, height: 180)
        ))

        let window = presentGTKWidget(wrapper)
        defer {
            gtk_window_destroy(windowPointer(window))
            drainGTKMainContext(maxIterations: 100)
        }
        allocate(widget: wrapper, size: ViewSize(width: 360, height: 180))
        drainGTKMainContext(maxIterations: 100)

        let firstRow = try unwrapFirstDescendant(ofType: "GtkListBoxRow", in: wrapper)
        let firstRowSize = allocatedSize(of: firstRow)
        XCTAssertLessThan(
            firstRowSize.height,
            100,
            "A horizontal-only ScrollView row should fit its content height, not expand to the vertical viewport."
        )

        var labels: [UnsafeMutablePointer<GtkWidget>] = []
        gtkCollectLabels(in: wrapper, into: &labels)
        let visibleSection = try XCTUnwrap(labels.first { label in
            String(cString: gtk_label_get_text(OpaquePointer(label))) == "Visible section"
        })
        let sectionOrigin = translatedChildOrigin(child: visibleSection, in: wrapper)
        XCTAssertLessThan(
            sectionOrigin.y,
            150,
            "Rows following a horizontal ScrollView should remain visible near the top of the List."
        )
    }

    func testShortListRowsRemainTopPackedInViewport() throws {
        try requireGTK()

        let wrapper = widgetFromOpaque(gtkRenderView(
            List {
                Text("Top row")
                Text("Second row")
            }
            .frame(width: 360, height: 320)
        ))

        let window = presentGTKWidget(wrapper)
        defer {
            gtk_window_destroy(windowPointer(window))
            drainGTKMainContext(maxIterations: 100)
        }
        allocate(widget: wrapper, size: ViewSize(width: 360, height: 320))
        drainGTKMainContext(maxIterations: 100)

        var labels: [UnsafeMutablePointer<GtkWidget>] = []
        gtkCollectLabels(in: wrapper, into: &labels)
        let topRow = try XCTUnwrap(labels.first { label in
            String(cString: gtk_label_get_text(OpaquePointer(label))) == "Top row"
        })
        let topRowOrigin = translatedChildOrigin(child: topRow, in: wrapper)
        XCTAssertLessThan(
            topRowOrigin.y,
            80,
            "A short List should pack rows from the top of the scroll viewport, not center them vertically."
        )
    }

    func testSearchableListContentFillsBelowSearchField() throws {
        try requireGTK()

        var searchText = ""
        let wrapper = widgetFromOpaque(gtkRenderView(
            List {
                Text("Top result")
                Text("Second result")
            }
            .searchable(text: Binding(get: { searchText }, set: { searchText = $0 }))
            .frame(width: 360, height: 360)
        ))

        let window = presentGTKWidget(wrapper)
        defer {
            gtk_window_destroy(windowPointer(window))
            drainGTKMainContext(maxIterations: 100)
        }
        allocate(widget: wrapper, size: ViewSize(width: 360, height: 360))
        drainGTKMainContext(maxIterations: 100)

        var labels: [UnsafeMutablePointer<GtkWidget>] = []
        gtkCollectLabels(in: wrapper, into: &labels)
        let topResult = try XCTUnwrap(labels.first { label in
            String(cString: gtk_label_get_text(OpaquePointer(label))) == "Top result"
        })
        let topResultOrigin = translatedChildOrigin(child: topResult, in: wrapper)
        XCTAssertLessThan(
            topResultOrigin.y,
            130,
            "Searchable content should fill the area below the search field; the first row must not be vertically centered."
        )
    }

    func testListRowsExposeNestedTapGesturesAsVisualTapTargets() throws {
        try requireGTK()

        let wrapper = widgetFromOpaque(gtkRenderView(
            List {
                VStack(alignment: .leading) {
                    Text("Nested media tap")
                        .frame(width: 160, height: 90)
                        .background(Color.blue)
                        .onTapGesture {}
                }
                .frame(width: 280, height: 140, alignment: .topLeading)
                .onTapGesture {}
            }
            .frame(width: 320, height: 220)
        ))

        let window = presentGTKWidget(wrapper)
        defer {
            gtk_window_destroy(windowPointer(window))
            drainGTKMainContext(maxIterations: 100)
        }
        allocate(widget: wrapper, size: ViewSize(width: 320, height: 220))
        drainGTKMainContext(maxIterations: 100)

        let label = try unwrapFirstDescendant(ofType: "GtkLabel", in: wrapper)
        let labelOrigin = translatedChildOrigin(child: label, in: wrapper)
        let labelSize = allocatedSize(of: label)
        let hitX = labelOrigin.x + max(1, labelSize.width / 2)
        let hitY = labelOrigin.y + max(1, labelSize.height / 2)

        XCTAssertTrue(
            gtkTestWidgetTreeContainsVisualTapActionAtRootPoint(
                wrapper,
                root: wrapper,
                x: hitX,
                y: hitY
            ),
            "A nested onTapGesture inside a List row must be treated as a visual tap target so the row fallback does not steal the click."
        )
        XCTAssertTrue(
            gtkTestPreferredTapActionMatchesWidgetTapData(
                label,
                root: wrapper,
                x: hitX,
                y: hitY
            ),
            "When parent and child onTapGesture wrappers overlap, GTK dispatch should prefer the child tap action at the clicked media pixel."
        )
    }

    func testHorizontalLazyStackPagerUsesOuterScrollerAndFillsViewportHeight() throws {
        try requireGTK()

        let wrapper = widgetFromOpaque(gtkRenderView(
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack([1]) { _ in
                    Text("Media")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        ))

        let window = presentGTKWidget(wrapper)
        defer {
            gtk_window_destroy(windowPointer(window))
            drainGTKMainContext(maxIterations: 100)
        }
        allocate(widget: wrapper, size: ViewSize(width: 560, height: 360))
        drainGTKMainContext(maxIterations: 100)

        XCTAssertEqual(
            gtkCountDescendants(ofType: "GtkScrolledWindow", in: wrapper),
            1,
            "A LazyHStack inside a horizontal ScrollView should render as layout content, not as a nested scroller."
        )

        let label = try unwrapFirstDescendant(ofType: "GtkLabel", in: wrapper)
        let labelSize = allocatedSize(of: label)
        let labelOrigin = translatedChildOrigin(child: label, in: wrapper)

        XCTAssertGreaterThan(labelSize.width, 20)
        XCTAssertGreaterThan(labelSize.height, 10)
        XCTAssertGreaterThan(labelOrigin.y, 120)
        XCTAssertLessThan(labelOrigin.y, 240)
    }

    func testBuilderLazyHStackFlattensForEachChildrenHorizontally() throws {
        try requireGTK()

        let wrapper = widgetFromOpaque(gtkRenderView(
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack {
                    ForEach(0..<3, id: \.self) { index in
                        Text("Item \(index)")
                            .frame(width: 72, height: 40)
                    }
                }
            }
            .frame(width: 260, height: 56)
        ))

        let window = presentGTKWidget(wrapper)
        defer {
            gtk_window_destroy(windowPointer(window))
            drainGTKMainContext(maxIterations: 100)
        }
        allocate(widget: wrapper, size: ViewSize(width: 260, height: 56))
        drainGTKMainContext(maxIterations: 100)

        var labels: [UnsafeMutablePointer<GtkWidget>] = []
        gtkCollectLabels(in: wrapper, into: &labels)
        let itemLabels = labels.filter {
            String(cString: gtk_label_get_text(OpaquePointer($0))).hasPrefix("Item ")
        }
        XCTAssertEqual(itemLabels.count, 3)

        let origins = itemLabels.map { translatedChildOrigin(child: $0, in: wrapper) }
        XCTAssertLessThan(origins[0].x, origins[1].x)
        XCTAssertLessThan(origins[1].x, origins[2].x)
        XCTAssertEqual(origins[0].y, origins[1].y, accuracy: 1)
        XCTAssertEqual(origins[1].y, origins[2].y, accuracy: 1)
    }

    func testGridSharedLayoutWrapsRowsUsingSharedPlacements() throws {
        try requireGTK()

        let wrapper = widgetFromOpaque(gtkRenderView(
            Grid(columns: 2, spacing: 5) {
                Text("WWWWWW")
                Text("I")
                Text("I")
            }
        ))
        let first = try unwrapFirstChild(of: wrapper)
        let second = try unwrapNextSibling(of: first)
        let third = try unwrapNextSibling(of: second)

        let wrapperSize = measuredSize(of: wrapper)
        allocate(widget: wrapper, size: wrapperSize)

        let firstSize = allocatedSize(of: first)
        let secondSize = allocatedSize(of: second)
        let firstOrigin = translatedChildOrigin(child: first, in: wrapper)
        let secondOrigin = translatedChildOrigin(child: second, in: wrapper)
        let thirdOrigin = translatedChildOrigin(child: third, in: wrapper)

        XCTAssertEqual(gtkWidgetTypeName(wrapper), "GtkFixed")
        XCTAssertEqual(firstOrigin.x, 0, accuracy: 0.01)
        XCTAssertEqual(firstOrigin.y, 0, accuracy: 0.01)
        XCTAssertEqual(secondOrigin.x, firstSize.width + 5, accuracy: 0.01)
        XCTAssertEqual(secondOrigin.y, 0, accuracy: 0.01)
        XCTAssertEqual(thirdOrigin.x, 0, accuracy: 0.01)
        XCTAssertEqual(thirdOrigin.y, max(firstSize.height, secondSize.height) + 5, accuracy: 0.01)
    }

    func testExplicitGridSharedLayoutAppliesHomogeneousSpanPlacements() throws {
        try requireGTK()

        let wrapper = widgetFromOpaque(gtkRenderView(
            Grid(horizontalSpacing: 4, verticalSpacing: 5) {
                GridRow {
                    Text("WWWWWW").gridCellColumns(2)
                    Text("I")
                }
                GridRow {
                    Text("I")
                    Text("I")
                    Text("I")
                }
            }
        ))
        let first = try unwrapFirstChild(of: wrapper)
        let second = try unwrapNextSibling(of: first)
        let third = try unwrapNextSibling(of: second)
        let fourth = try unwrapNextSibling(of: third)
        let fifth = try unwrapNextSibling(of: fourth)

        let wrapperSize = measuredSize(of: wrapper)
        allocate(widget: wrapper, size: wrapperSize)

        let firstSize = allocatedSize(of: first)
        let thirdSize = allocatedSize(of: third)
        let firstOrigin = translatedChildOrigin(child: first, in: wrapper)
        let secondOrigin = translatedChildOrigin(child: second, in: wrapper)
        let thirdOrigin = translatedChildOrigin(child: third, in: wrapper)
        let fourthOrigin = translatedChildOrigin(child: fourth, in: wrapper)
        let fifthOrigin = translatedChildOrigin(child: fifth, in: wrapper)

        XCTAssertEqual(gtkWidgetTypeName(wrapper), "GtkFixed")
        XCTAssertEqual(firstOrigin.x, 0, accuracy: 0.01)
        XCTAssertEqual(firstOrigin.y, 0, accuracy: 0.01)
        XCTAssertEqual(secondOrigin.y, 0, accuracy: 0.01)
        XCTAssertEqual(thirdOrigin.x, 0, accuracy: 0.01)
        XCTAssertEqual(fourthOrigin.x, thirdSize.width + 4, accuracy: 0.01)
        XCTAssertEqual(secondOrigin.x, fifthOrigin.x, accuracy: 0.01)
        XCTAssertEqual(firstSize.width, fifthOrigin.x - 4, accuracy: 0.01)
        XCTAssertEqual(thirdOrigin.y, max(firstSize.height, allocatedSize(of: second).height) + 5, accuracy: 0.01)
    }

    // MARK: - Descriptor mutation hooks

    func testTextMutationHookChangesLabelContent() throws {
        try requireGTK()

        // Render initial text and capture slot
        let label = widgetFromOpaque(gtkRenderView(Text("Old")))
        XCTAssertEqual(gtkHostedNodeKind(of: label), .text)

        let slotID = gtkNativeSlotID(for: label)

        // Mutate via hook helper
        let success = gtkSetTextContent(slotID: slotID, text: "New")
        XCTAssertTrue(success)

        // Verify the label text changed
        let cStr = gtk_label_get_text(OpaquePointer(label))!
        XCTAssertEqual(String(cString: cStr), "New")
    }

    func testColorMutationHookChangesBackground() throws {
        try requireGTK()

        // Render initial color and capture slot
        let box = widgetFromOpaque(gtkRenderView(Color.red))
        XCTAssertEqual(gtkHostedNodeKind(of: box), .color)

        let slotID = gtkNativeSlotID(for: box)

        // Mutate via hook helper
        let newColor = GTK4ColorDescriptor(red: 0, green: 1, blue: 0, opacity: 1)
        let success = gtkSetColorFill(slotID: slotID, color: newColor)
        XCTAssertTrue(success)

        // Verify the CSS provider was installed (widget should have the class)
        let className = "gtk-swift-color-\(slotID)"
        XCTAssertTrue(gtk_widget_has_css_class(box, className) != 0)
    }

    func testTextMutationFailsWithInvalidSlot() throws {
        try requireGTK()
        let success = gtkSetTextContent(slotID: 0, text: "Nope")
        XCTAssertFalse(success)
    }

    // MARK: - Host-level mutation path tests

    func testHostTextMutationSkipsRebuild() throws {
        try requireGTK()

        // Create a ViewHost with a describable text body
        var textContent = "Old"
        let host = GTKViewHost(buildBody: {
            gtkRenderView(Text(textContent))
        })
        host.describeBody = {
            gtkDescribeView(Text(textContent))
        }

        // Initial build
        let previousHost = GTKViewHost.getCurrentRebuilding()
        GTKViewHost.setCurrentRebuilding(host)
        let widget = host.buildBodyWithTracking()
        GTKViewHost.setCurrentRebuilding(previousHost)

        let child = widgetFromOpaque(widget)
        gtk_box_append(boxPointer(host.container), child)

        // Capture initial descriptor state (simulating what rebuild does after full build)
        let descriptor = gtkDescribeView(Text(textContent))
        let identified = gtkIdentifyDescriptorTree(descriptor)
        host.lastRetainedDescriptor = gtkRetainDescriptorTree(identified)
        var executor = gtkMakeExecutorTree(from: identified)
        executor = gtkCaptureSupportedNativeSlots(from: child, descriptorRoot: identified, executorRoot: executor)
        host.retainedExecutor = executor

        // Capture the label widget pointer
        let label = gtk_widget_get_first_child(host.container)!
        let labelBefore = UnsafeRawPointer(label)

        // Change state and rebuild
        textContent = "New"
        host.rebuild()

        // Verify: same widget (no destroy/recreate), updated content
        let labelAfter = gtk_widget_get_first_child(host.container)!
        XCTAssertEqual(UnsafeRawPointer(labelAfter), labelBefore, "Widget should be same (in-place mutation)")
        let cStr = gtk_label_get_text(OpaquePointer(labelAfter))!
        XCTAssertEqual(String(cString: cStr), "New")
    }

    func testHostColorMutationSkipsRebuild() throws {
        try requireGTK()

        var currentColor = Color.red
        let host = GTKViewHost(buildBody: {
            gtkRenderView(currentColor)
        })
        host.describeBody = {
            gtkDescribeView(currentColor)
        }

        let previousHost = GTKViewHost.getCurrentRebuilding()
        GTKViewHost.setCurrentRebuilding(host)
        let widget = host.buildBodyWithTracking()
        GTKViewHost.setCurrentRebuilding(previousHost)

        let child = widgetFromOpaque(widget)
        gtk_box_append(boxPointer(host.container), child)

        let descriptor = gtkDescribeView(currentColor)
        let identified = gtkIdentifyDescriptorTree(descriptor)
        host.lastRetainedDescriptor = gtkRetainDescriptorTree(identified)
        var executor = gtkMakeExecutorTree(from: identified)
        executor = gtkCaptureSupportedNativeSlots(from: child, descriptorRoot: identified, executorRoot: executor)
        host.retainedExecutor = executor

        let boxBefore = UnsafeRawPointer(gtk_widget_get_first_child(host.container)!)

        currentColor = Color.green
        host.rebuild()

        let boxAfter = gtk_widget_get_first_child(host.container)!
        XCTAssertEqual(UnsafeRawPointer(boxAfter), boxBefore, "Widget should be same (in-place color mutation)")
    }

    func testHostStructuralChangeTriggersFullRebuild() throws {
        try requireGTK()

        // Create a ViewHost that can switch between Text and Color
        var showText = true
        let host = GTKViewHost(buildBody: {
            if showText {
                return gtkRenderView(Text("Hello"))
            } else {
                return gtkRenderView(Color.red)
            }
        })
        host.describeBody = {
            if showText {
                return gtkDescribeView(Text("Hello"))
            } else {
                return gtkDescribeView(Color.red)
            }
        }

        // Initial build
        let previousHost = GTKViewHost.getCurrentRebuilding()
        GTKViewHost.setCurrentRebuilding(host)
        let widget = host.buildBodyWithTracking()
        GTKViewHost.setCurrentRebuilding(previousHost)

        let child = widgetFromOpaque(widget)
        gtk_box_append(boxPointer(host.container), child)

        // Capture descriptor state
        let descriptor = gtkDescribeView(Text("Hello"))
        let identified = gtkIdentifyDescriptorTree(descriptor)
        host.lastRetainedDescriptor = gtkRetainDescriptorTree(identified)
        var executor = gtkMakeExecutorTree(from: identified)
        executor = gtkCaptureSupportedNativeSlots(from: child, descriptorRoot: identified, executorRoot: executor)
        host.retainedExecutor = executor

        let labelBefore = UnsafeRawPointer(gtk_widget_get_first_child(host.container)!)

        // Structural change: Text → Color
        showText = false
        host.rebuild()

        // Verify: different widget (full rebuild happened)
        let childAfter = gtk_widget_get_first_child(host.container)!
        XCTAssertNotEqual(UnsafeRawPointer(childAfter), labelBefore, "Widget should be different (full rebuild)")
    }

    func testTaskStateMutationUsesRenderCapturedStateStorage() throws {
        try requireGTK()

        let widget = widgetFromOpaque(gtkRenderView(GTKTaskStateUpdateProbe()))
        let window = presentGTKWidget(widget)
        defer {
            gtk_window_destroy(windowPointer(window))
            drainGTKMainContext(maxIterations: 100)
        }
        allocate(widget: widget, size: ViewSize(width: 240, height: 80))
        drainGTKMainContext(maxIterations: 100)

        XCTAssertTrue(
            waitForGTKLabelText(in: widget, timeout: 1.0) { labels in
                labels.contains("Loaded")
            },
            ".task state writes should schedule the declaring host rebuild instead of mutating hostless descriptor storage."
        )
    }

    func testFullPipelineColorMutation() throws {
        try requireGTK()

        // Render and describe old state
        let box = widgetFromOpaque(gtkRenderView(Color.red))
        let slotID = gtkNativeSlotID(for: box)
        let className = "gtk-swift-color-\(slotID)"

        let oldDesc = gtkDescribeView(Color.red)
        let newDesc = gtkDescribeView(Color.green)
        let oldId = gtkIdentifyDescriptorTree(oldDesc)
        let newId = gtkIdentifyDescriptorTree(newDesc)
        let retained = gtkRetainDescriptorTree(oldId)
        let executor = gtkMakeExecutorTree(from: oldId, nativeSlotID: slotID)

        // Plan
        let plan = gtkPlanDescriptorTree(old: retained, new: newId)
        XCTAssertTrue(gtkCanApplyTextColorHostMutation(plan: plan))
        XCTAssertEqual(plan.updateIntent, .colorFill)

        // Execute + mutate (first mutation — creates provider)
        let action = gtkExecuteDescriptorPlan(old: executor, plan: plan)
        let result = gtkApplyHookMutation(action: action)
        XCTAssertTrue(gtkHookMutationSucceeded(result))
        XCTAssertTrue(gtk_widget_has_css_class(box, className) != 0)

        // Second mutation on same widget — reuses provider (replace-in-place)
        let blueDesc = gtkDescribeView(Color.blue)
        let blueId = gtkIdentifyDescriptorTree(blueDesc)
        let retained2 = gtkRetainDescriptorTree(newId)
        let executor2 = action.resultingNode
        let plan2 = gtkPlanDescriptorTree(old: retained2, new: blueId)
        let action2 = gtkExecuteDescriptorPlan(old: executor2, plan: plan2)
        let result2 = gtkApplyHookMutation(action: action2)
        XCTAssertTrue(gtkHookMutationSucceeded(result2))

        // Same widget, same class — provider was reused, not stacked
        XCTAssertTrue(gtk_widget_has_css_class(box, className) != 0)
    }

    func testFullPipelineTextMutation() throws {
        try requireGTK()

        // Render and describe old state
        let label = widgetFromOpaque(gtkRenderView(Text("Old")))
        let slotID = gtkNativeSlotID(for: label)

        let oldDesc = gtkDescribeView(Text("Old"))
        let newDesc = gtkDescribeView(Text("New"))
        let oldId = gtkIdentifyDescriptorTree(oldDesc)
        let newId = gtkIdentifyDescriptorTree(newDesc)
        let retained = gtkRetainDescriptorTree(oldId)
        let executor = gtkMakeExecutorTree(from: oldId, nativeSlotID: slotID)

        // Plan
        let plan = gtkPlanDescriptorTree(old: retained, new: newId)
        XCTAssertTrue(gtkCanApplyTextColorHostMutation(plan: plan))

        // Execute + mutate
        let action = gtkExecuteDescriptorPlan(old: executor, plan: plan)
        let result = gtkApplyHookMutation(action: action)
        XCTAssertTrue(gtkHookMutationSucceeded(result))

        // Verify label changed
        let cStr = gtk_label_get_text(OpaquePointer(label))!
        XCTAssertEqual(String(cString: cStr), "New")
    }

    // MARK: - Safe Area Tests

    func testIgnoresSafeAreaPassthroughRendersContent() throws {
        try requireGTK()

        let widget = widgetFromOpaque(gtkRenderView(
            Text("Hello").ignoresSafeArea()
        ))
        // Passthrough — the result should contain a label with the text
        let label = try unwrapFirstDescendant(ofType: "GtkLabel", in: widget)
        XCTAssertEqual(String(cString: gtk_label_get_text(OpaquePointer(label))), "Hello")
    }

    func testSafeAreaInsetTopCreatesVerticalBox() throws {
        try requireGTK()

        let widget = widgetFromOpaque(gtkRenderView(
            Text("Main").safeAreaInset(edge: VerticalEdge.top) {
                Text("Header")
            }
        ))
        // Should be a GtkBox with vertical orientation
        XCTAssertEqual(gtkWidgetTypeName(widget), "GtkBox")

        // First child is the inset (top = inset first), second is content
        let first = try unwrapFirstChild(of: widget)
        let second = try unwrapNextSibling(of: first)

        let firstLabel = try unwrapFirstDescendant(ofType: "GtkLabel", in: first)
        XCTAssertEqual(String(cString: gtk_label_get_text(OpaquePointer(firstLabel))), "Header")

        let secondLabel = try unwrapFirstDescendant(ofType: "GtkLabel", in: second)
        XCTAssertEqual(String(cString: gtk_label_get_text(OpaquePointer(secondLabel))), "Main")
    }

    func testSafeAreaInsetBottomCreatesVerticalBox() throws {
        try requireGTK()

        let widget = widgetFromOpaque(gtkRenderView(
            Text("Main").safeAreaInset(edge: VerticalEdge.bottom) {
                Text("Footer")
            }
        ))
        XCTAssertEqual(gtkWidgetTypeName(widget), "GtkBox")

        // Bottom: content first, then inset
        let first = try unwrapFirstChild(of: widget)
        let second = try unwrapNextSibling(of: first)

        let firstLabel = try unwrapFirstDescendant(ofType: "GtkLabel", in: first)
        XCTAssertEqual(String(cString: gtk_label_get_text(OpaquePointer(firstLabel))), "Main")

        let secondLabel = try unwrapFirstDescendant(ofType: "GtkLabel", in: second)
        XCTAssertEqual(String(cString: gtk_label_get_text(OpaquePointer(secondLabel))), "Footer")
    }

    func testSafeAreaInsetTrailingCreatesHorizontalBox() throws {
        try requireGTK()

        let widget = widgetFromOpaque(gtkRenderView(
            Text("Main").safeAreaInset(edge: HorizontalEdge.trailing) {
                Text("Side")
            }
        ))
        XCTAssertEqual(gtkWidgetTypeName(widget), "GtkBox")

        // Trailing: content first, then inset
        let first = try unwrapFirstChild(of: widget)
        let second = try unwrapNextSibling(of: first)

        let firstLabel = try unwrapFirstDescendant(ofType: "GtkLabel", in: first)
        XCTAssertEqual(String(cString: gtk_label_get_text(OpaquePointer(firstLabel))), "Main")

        let secondLabel = try unwrapFirstDescendant(ofType: "GtkLabel", in: second)
        XCTAssertEqual(String(cString: gtk_label_get_text(OpaquePointer(secondLabel))), "Side")
    }

    func testSafeAreaInsetTopDescriptorOrderMatchesWidgetOrder() throws {
        try requireGTK()

        // Build a view with safeAreaInset(edge: .top) wrapping a Text
        var textContent = "Old"
        let host = GTKViewHost(buildBody: {
            gtkRenderView(Text(textContent).safeAreaInset(edge: VerticalEdge.top) {
                Text("Header")
            })
        })
        host.describeBody = {
            gtkDescribeView(Text(textContent).safeAreaInset(edge: VerticalEdge.top) {
                Text("Header")
            })
        }

        // Initial build
        let previousHost = GTKViewHost.getCurrentRebuilding()
        GTKViewHost.setCurrentRebuilding(host)
        let widget = host.buildBodyWithTracking()
        GTKViewHost.setCurrentRebuilding(previousHost)

        let child = widgetFromOpaque(widget)
        gtk_box_append(boxPointer(host.container), child)

        // Capture descriptor state
        let descriptor = gtkDescribeView(Text(textContent).safeAreaInset(edge: VerticalEdge.top) {
            Text("Header")
        })
        let identified = gtkIdentifyDescriptorTree(descriptor)
        host.lastRetainedDescriptor = gtkRetainDescriptorTree(identified)
        var executor = gtkMakeExecutorTree(from: identified)
        executor = gtkCaptureSupportedNativeSlots(from: child, descriptorRoot: identified, executorRoot: executor)
        host.retainedExecutor = executor

        // The box has two children: [Header(inset), Old(content)]
        // Find the content label (second child for .top inset)
        let insetLabel = gtk_widget_get_first_child(child)!
        let contentLabel = gtk_widget_get_next_sibling(insetLabel)!
        let contentBefore = UnsafeRawPointer(contentLabel)

        // Change state and rebuild
        textContent = "New"
        host.rebuild()

        // Verify in-place mutation: same widget pointer, updated text
        let insetLabelAfter = gtk_widget_get_first_child(gtk_widget_get_first_child(host.container)!)!
        let contentLabelAfter = gtk_widget_get_next_sibling(insetLabelAfter)!
        XCTAssertEqual(UnsafeRawPointer(contentLabelAfter), contentBefore,
                       "Content widget should be same (in-place mutation, not teardown/rebuild)")
        let cStr = gtk_label_get_text(OpaquePointer(contentLabelAfter))!
        XCTAssertEqual(String(cString: cStr), "New")
    }

    func testSafeAreaInsetLeadingDescriptorOrderMatchesWidgetOrder() throws {
        try requireGTK()

        var textContent = "Old"
        let host = GTKViewHost(buildBody: {
            gtkRenderView(Text(textContent).safeAreaInset(edge: HorizontalEdge.leading) {
                Text("Side")
            })
        })
        host.describeBody = {
            gtkDescribeView(Text(textContent).safeAreaInset(edge: HorizontalEdge.leading) {
                Text("Side")
            })
        }

        let previousHost = GTKViewHost.getCurrentRebuilding()
        GTKViewHost.setCurrentRebuilding(host)
        let widget = host.buildBodyWithTracking()
        GTKViewHost.setCurrentRebuilding(previousHost)

        let child = widgetFromOpaque(widget)
        gtk_box_append(boxPointer(host.container), child)

        let descriptor = gtkDescribeView(Text(textContent).safeAreaInset(edge: HorizontalEdge.leading) {
            Text("Side")
        })
        let identified = gtkIdentifyDescriptorTree(descriptor)
        host.lastRetainedDescriptor = gtkRetainDescriptorTree(identified)
        var executor = gtkMakeExecutorTree(from: identified)
        executor = gtkCaptureSupportedNativeSlots(from: child, descriptorRoot: identified, executorRoot: executor)
        host.retainedExecutor = executor

        // Leading: [inset, content] — content is the second child
        let insetLabel = gtk_widget_get_first_child(child)!
        let contentLabel = gtk_widget_get_next_sibling(insetLabel)!
        let contentBefore = UnsafeRawPointer(contentLabel)

        textContent = "New"
        host.rebuild()

        let insetLabelAfter = gtk_widget_get_first_child(gtk_widget_get_first_child(host.container)!)!
        let contentLabelAfter = gtk_widget_get_next_sibling(insetLabelAfter)!
        XCTAssertEqual(UnsafeRawPointer(contentLabelAfter), contentBefore,
                       "Content widget should be same (in-place mutation, not teardown/rebuild)")
        let cStr = gtk_label_get_text(OpaquePointer(contentLabelAfter))!
        XCTAssertEqual(String(cString: cStr), "New")
    }

    func testSafeAreaInsetWithSpacing() throws {
        try requireGTK()

        let widget = widgetFromOpaque(gtkRenderView(
            Text("Main").safeAreaInset(edge: VerticalEdge.top, spacing: 12) {
                Text("Header")
            }
        ))
        XCTAssertEqual(gtkWidgetTypeName(widget), "GtkBox")

        // Verify the box has spacing=12
        let boxSpacing = gtk_box_get_spacing(boxPointer(widget))
        XCTAssertEqual(boxSpacing, 12)
    }

    // MARK: - Searchable Tests

    private func unwrapSearchSurface(in widget: UnsafeMutablePointer<GtkWidget>) throws -> UnsafeMutablePointer<GtkWidget> {
        let surface = try unwrapFirstChild(of: widget)
        XCTAssertEqual(gtkWidgetTypeName(surface), "GtkBox")
        _ = try unwrapFirstDescendant(ofType: "GtkSearchEntry", in: surface)
        return surface
    }

    private func unwrapSearchEntry(in widget: UnsafeMutablePointer<GtkWidget>) throws -> UnsafeMutablePointer<GtkWidget> {
        try unwrapFirstDescendant(ofType: "GtkSearchEntry", in: try unwrapSearchSurface(in: widget))
    }

    private func unwrapSiblingAfterSearchSurface(in widget: UnsafeMutablePointer<GtkWidget>) throws -> UnsafeMutablePointer<GtkWidget> {
        try unwrapNextSibling(of: try unwrapSearchSurface(in: widget))
    }

    func testSearchableRendersSearchEntryAboveContent() throws {
        try requireGTK()

        var searchText = ""
        let widget = widgetFromOpaque(gtkRenderView(
            Text("Content").searchable(text: Binding(get: { searchText }, set: { searchText = $0 }))
        ))
        XCTAssertEqual(gtkWidgetTypeName(widget), "GtkBox")

        // First child is a search surface wrapper; the native entry lives inside
        // it so root hit testing uses the painted search-row geometry.
        let first = try unwrapSearchSurface(in: widget)
        let entry = try unwrapFirstDescendant(ofType: "GtkSearchEntry", in: first)

        let second = try unwrapNextSibling(of: first)
        XCTAssertEqual(
            gtk_swift_search_entry_get_key_capture_widget(entry),
            widget,
            "Searchable should capture wrapper/content key events into the search entry"
        )
        XCTAssertNotEqual(
            gtk_widget_get_can_target(widget),
            0,
            "Searchable wrapper should accept pointer presses so it can focus the search entry"
        )
        let label = try unwrapFirstDescendant(ofType: "GtkLabel", in: second)
        XCTAssertEqual(String(cString: gtk_label_get_text(OpaquePointer(label))), "Content")
    }

    func testSearchableWithPlacementRendersWithoutCrash() throws {
        try requireGTK()

        var searchText = ""
        // Non-default placement should still render (advisory in Batch A)
        let widget = widgetFromOpaque(gtkRenderView(
            Text("Content").searchable(
                text: Binding(get: { searchText }, set: { searchText = $0 }),
                placement: .toolbar
            )
        ))
        XCTAssertEqual(gtkWidgetTypeName(widget), "GtkBox")

        _ = try unwrapSearchEntry(in: widget)
    }

    func testSearchableIsPresentedFalseHidesEntry() throws {
        try requireGTK()

        var searchText = ""
        var presented = false
        let widget = widgetFromOpaque(gtkRenderView(
            Text("Content").searchable(
                text: Binding(get: { searchText }, set: { searchText = $0 }),
                isPresented: Binding(get: { presented }, set: { presented = $0 })
            )
        ))

        let surface = try unwrapSearchSurface(in: widget)
        let entry = try unwrapFirstDescendant(ofType: "GtkSearchEntry", in: surface)
        XCTAssertEqual(gtk_widget_get_visible(entry), 0, "Entry should be hidden when isPresented is false")
        XCTAssertEqual(gtk_widget_get_visible(surface), 0, "Search surface should be hidden when isPresented is false")
    }

    func testSearchableNavigationBarDrawerAlwaysKeepsChromeVisibleWhenNotPresented() throws {
        try requireGTK()

        enum Scope: String, CaseIterable {
            case all
            case people
        }

        var searchText = ""
        var presented = false
        var selectedScope = Scope.all
        let widget = widgetFromOpaque(gtkRenderView(
            Text("Content")
                .searchable(
                    text: Binding(get: { searchText }, set: { searchText = $0 }),
                    isPresented: Binding(get: { presented }, set: { presented = $0 }),
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Search"
                )
                .searchScopes(Binding(get: { selectedScope }, set: { selectedScope = $0 }),
                              scopes: Scope.allCases) { scope in
                    Text(scope.rawValue)
                }
        ))

        let surface = try unwrapSearchSurface(in: widget)
        let entry = try unwrapFirstDescendant(ofType: "GtkSearchEntry", in: surface)
        XCTAssertNotEqual(
            gtk_widget_get_visible(entry),
            0,
            "Navigation drawer search with displayMode .always must remain visible when isPresented is false"
        )
        XCTAssertNotEqual(
            gtk_widget_get_focusable(entry),
            0,
            "Visible searchable chrome should be focusable so a click can start text entry"
        )

        let scopeRow = try unwrapNextSibling(of: surface)
        XCTAssertEqual(gtkWidgetTypeName(scopeRow), "GtkBox")
        XCTAssertNotEqual(
            gtk_widget_get_visible(scopeRow),
            0,
            "Search scopes should remain visible with navigation drawer displayMode .always"
        )
    }

    func testSearchableEntryChangedSignalUpdatesBinding() throws {
        try requireGTK()

        var searchText = ""
        let widget = widgetFromOpaque(gtkRenderView(
            Text("Content").searchable(
                text: Binding(get: { searchText }, set: { searchText = $0 }),
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search"
            )
        ))

        let entry = try unwrapSearchEntry(in: widget)
        gtk_swift_editable_set_text(entry, "quill")
        gtkFlushPendingTextBindingUpdate()

        XCTAssertEqual(searchText, "quill")
    }

    func testSearchableIsPresentedTrueShowsEntry() throws {
        try requireGTK()

        var searchText = ""
        var presented = true
        let widget = widgetFromOpaque(gtkRenderView(
            Text("Content").searchable(
                text: Binding(get: { searchText }, set: { searchText = $0 }),
                isPresented: Binding(get: { presented }, set: { presented = $0 })
            )
        ))

        let entry = try unwrapSearchEntry(in: widget)
        // Default visibility is true (GTK shows widgets by default)
        XCTAssertNotEqual(gtk_widget_get_visible(entry), 0, "Entry should be visible when isPresented is true")
    }

    func testSearchableExternalTextChangeTriggersDescriptorUpdate() throws {
        try requireGTK()

        var searchText = "old"
        let binding = Binding(get: { searchText }, set: { searchText = $0 })

        let host = GTKViewHost(buildBody: {
            gtkRenderView(Text("Content").searchable(text: binding))
        })
        host.describeBody = {
            gtkDescribeView(Text("Content").searchable(text: binding))
        }

        let previousHost = GTKViewHost.getCurrentRebuilding()
        GTKViewHost.setCurrentRebuilding(host)
        let widget = host.buildBodyWithTracking()
        GTKViewHost.setCurrentRebuilding(previousHost)

        let child = widgetFromOpaque(widget)
        gtk_box_append(boxPointer(host.container), child)

        let descriptor = gtkDescribeView(Text("Content").searchable(text: binding))
        let identified = gtkIdentifyDescriptorTree(descriptor)
        host.lastRetainedDescriptor = gtkRetainDescriptorTree(identified)
        var executor = gtkMakeExecutorTree(from: identified)
        executor = gtkCaptureSupportedNativeSlots(from: child, descriptorRoot: identified, executorRoot: executor)
        host.retainedExecutor = executor

        // Verify initial text descriptor includes "old"
        let oldDesc = gtkDescribeView(Text("Content").searchable(text: binding))

        // Change external text
        searchText = "new"
        let newDesc = gtkDescribeView(Text("Content").searchable(text: binding))

        // Descriptors should differ because text changed
        XCTAssertNotEqual(oldDesc, newDesc,
                          "Descriptor should change when bound text changes")

        // Verify the plan detects an update, not a reuse
        let oldId = gtkIdentifyDescriptorTree(oldDesc)
        let newId = gtkIdentifyDescriptorTree(newDesc)
        let retained = gtkRetainDescriptorTree(oldId)
        let plan = gtkPlanDescriptorTree(old: retained, new: newId)
        XCTAssertNotEqual(plan.kind, .reuse,
                          "Plan should not be .reuse when text changes")
    }

    // MARK: - Searchable Token Tests

    func testSearchableWithTokensRendersTokenRow() throws {
        try requireGTK()

        struct Tag: Identifiable { let id: String; let name: String }
        var searchText = ""
        var tags = [Tag(id: "a", name: "Alpha"), Tag(id: "b", name: "Beta")]
        let widget = widgetFromOpaque(gtkRenderView(
            Text("Content").searchable(
                text: Binding(get: { searchText }, set: { searchText = $0 }),
                tokens: Binding(get: { tags }, set: { tags = $0 })
            ) { tag in
                Text(tag.name)
            }
        ))
        XCTAssertEqual(gtkWidgetTypeName(widget), "GtkBox")

        // First child: search surface, second: token row, third: content
        let surface = try unwrapSearchSurface(in: widget)
        let tokenRow = try unwrapNextSibling(of: surface)
        XCTAssertEqual(gtkWidgetTypeName(tokenRow), "GtkBox")
        // Token row should have 2 labels
        let firstLabel = try unwrapFirstChild(of: tokenRow)
        XCTAssertEqual(String(cString: gtk_label_get_text(OpaquePointer(firstLabel))), "Alpha")
        let secondLabel = try unwrapNextSibling(of: firstLabel)
        XCTAssertEqual(String(cString: gtk_label_get_text(OpaquePointer(secondLabel))), "Beta")
    }

    func testSearchableWithEmptyTokensOmitsTokenRow() throws {
        try requireGTK()

        var searchText = ""
        struct Tag: Identifiable { let id: String; let name: String }
        var tags: [Tag] = []
        let widget = widgetFromOpaque(gtkRenderView(
            Text("Content").searchable(
                text: Binding(get: { searchText }, set: { searchText = $0 }),
                tokens: Binding(get: { tags }, set: { tags = $0 })
            ) { tag in
                Text(tag.name)
            }
        ))

        // With no tokens: search surface then content directly, no token row
        let content = try unwrapSiblingAfterSearchSurface(in: widget)
        let label = try unwrapFirstDescendant(ofType: "GtkLabel", in: content)
        XCTAssertEqual(String(cString: gtk_label_get_text(OpaquePointer(label))), "Content")
    }

    func testSearchableTokenDescriptorDetectsTokenChange() throws {
        try requireGTK()

        struct Tag: Identifiable { let id: String; let name: String }
        var searchText = ""
        var tags = [Tag(id: "a", name: "Alpha")]
        let binding = Binding(get: { searchText }, set: { searchText = $0 })
        let tagsBinding = Binding(get: { tags }, set: { tags = $0 })

        let oldDesc = gtkDescribeView(
            Text("X").searchable(text: binding, tokens: tagsBinding) { t in Text(t.name) }
        )

        tags = [Tag(id: "a", name: "Alpha"), Tag(id: "b", name: "Beta")]
        let newDesc = gtkDescribeView(
            Text("X").searchable(text: binding, tokens: tagsBinding) { t in Text(t.name) }
        )

        XCTAssertNotEqual(oldDesc, newDesc, "Descriptor should differ when tokens change")
    }

    // MARK: - Search Suggestion Tests

    func testSearchSuggestionsRenderButtonRows() throws {
        try requireGTK()

        var searchText = ""
        let widget = widgetFromOpaque(gtkRenderView(
            Text("Content")
                .searchable(text: Binding(get: { searchText }, set: { searchText = $0 }))
                .searchSuggestions {
                    Text("Apple")
                    Text("Banana")
                }
        ))
        XCTAssertEqual(gtkWidgetTypeName(widget), "GtkBox")

        // Layout: search surface, suggestion box, content
        let surface = try unwrapSearchSurface(in: widget)
        let suggestionBox = try unwrapNextSibling(of: surface)
        XCTAssertEqual(gtkWidgetTypeName(suggestionBox), "GtkBox")
        // Suggestion box has 2 buttons
        let firstBtn = try unwrapFirstChild(of: suggestionBox)
        XCTAssertEqual(gtkWidgetTypeName(firstBtn), "GtkButton")
        let secondBtn = try unwrapNextSibling(of: firstBtn)
        XCTAssertEqual(gtkWidgetTypeName(secondBtn), "GtkButton")
    }

    func testSearchSuggestionsEmptyOmitsBox() throws {
        try requireGTK()

        var searchText = ""
        let widget = widgetFromOpaque(gtkRenderView(
            Text("Content")
                .searchable(text: Binding(get: { searchText }, set: { searchText = $0 }))
                .searchSuggestions { }
        ))
        // With no suggestions: search surface then content, no suggestion box
        let content = try unwrapSiblingAfterSearchSurface(in: widget)
        let label = try unwrapFirstDescendant(ofType: "GtkLabel", in: content)
        XCTAssertEqual(String(cString: gtk_label_get_text(OpaquePointer(label))), "Content")
    }

    func testSearchSuggestionDescriptorDetectsChange() throws {
        try requireGTK()

        var searchText = ""
        let binding = Binding(get: { searchText }, set: { searchText = $0 })

        let oldDesc = gtkDescribeView(
            Text("X")
                .searchable(text: binding)
                .searchSuggestions { Text("A") }
        )
        let newDesc = gtkDescribeView(
            Text("X")
                .searchable(text: binding)
                .searchSuggestions { Text("A"); Text("B") }
        )

        XCTAssertNotEqual(oldDesc, newDesc, "Descriptor should differ when suggestions change")
    }

    func testSearchSuggestionsForRendersFilteredRows() throws {
        try requireGTK()

        var searchText = "an"
        let allSuggestions = [
            SearchSuggestionValue(id: "1", label: "Apple", completion: "Apple"),
            SearchSuggestionValue(id: "2", label: "Banana", completion: "Banana"),
            SearchSuggestionValue(id: "3", label: "Orange", completion: "Orange"),
        ]
        let widget = widgetFromOpaque(gtkRenderView(
            Text("Content")
                .searchable(text: Binding(get: { searchText }, set: { searchText = $0 }))
                .searchSuggestions(allSuggestions, for: searchText)
        ))

        // Core filters case-insensitively with .contains — "an" matches "Banana" and "Orange"
        let surface = try unwrapSearchSurface(in: widget)
        let suggestionBox = try unwrapNextSibling(of: surface)
        XCTAssertEqual(gtkWidgetTypeName(suggestionBox), "GtkBox")

        // Should have 2 buttons (Banana, Orange), not 3 — Apple excluded
        let firstBtn = try unwrapFirstChild(of: suggestionBox)
        XCTAssertEqual(gtkWidgetTypeName(firstBtn), "GtkButton")
        let firstLabel = try unwrapFirstDescendant(ofType: "GtkLabel", in: firstBtn)
        XCTAssertEqual(String(cString: gtk_label_get_text(OpaquePointer(firstLabel))), "Banana")

        let secondBtn = try unwrapNextSibling(of: firstBtn)
        XCTAssertEqual(gtkWidgetTypeName(secondBtn), "GtkButton")
        let secondLabel = try unwrapFirstDescendant(ofType: "GtkLabel", in: secondBtn)
        XCTAssertEqual(String(cString: gtk_label_get_text(OpaquePointer(secondLabel))), "Orange")

        XCTAssertNil(gtk_widget_get_next_sibling(secondBtn), "Apple should be excluded by filter")
    }

    func testSearchableDismissedHidesSuggestions() throws {
        try requireGTK()

        var searchText = ""
        var presented = false
        let widget = widgetFromOpaque(gtkRenderView(
            Text("Content")
                .searchable(
                    text: Binding(get: { searchText }, set: { searchText = $0 }),
                    isPresented: Binding(get: { presented }, set: { presented = $0 })
                )
                .searchSuggestions {
                    Text("Hint")
                }
        ))

        // Search surface should be hidden
        let surface = try unwrapSearchSurface(in: widget)
        let entry = try unwrapFirstDescendant(ofType: "GtkSearchEntry", in: surface)
        XCTAssertEqual(gtk_widget_get_visible(entry), 0, "Entry should be hidden when dismissed")
        XCTAssertEqual(gtk_widget_get_visible(surface), 0, "Search surface should be hidden when dismissed")

        // Suggestion box should be hidden
        let suggestionBox = try unwrapNextSibling(of: surface)
        XCTAssertEqual(gtk_widget_get_visible(suggestionBox), 0, "Suggestion box should be hidden when dismissed")
    }

    // MARK: - Search Scope Tests

    func testSearchScopesRenderToggleButtons() throws {
        try requireGTK()

        var searchText = ""
        var selection = "all"
        let widget = widgetFromOpaque(gtkRenderView(
            Text("Content")
                .searchable(text: Binding(get: { searchText }, set: { searchText = $0 }))
                .searchScopes(
                    Binding(get: { selection }, set: { selection = $0 }),
                    scopes: ["all", "docs", "code"]
                ) { scope in
                    Text(scope)
                }
        ))
        XCTAssertEqual(gtkWidgetTypeName(widget), "GtkBox")

        // Layout: search surface, scope row, content
        let surface = try unwrapSearchSurface(in: widget)
        let scopeRow = try unwrapNextSibling(of: surface)
        XCTAssertEqual(gtkWidgetTypeName(scopeRow), "GtkBox")
        // Scope row has 3 toggle buttons
        let firstBtn = try unwrapFirstChild(of: scopeRow)
        XCTAssertEqual(gtkWidgetTypeName(firstBtn), "GtkToggleButton")
        let secondBtn = try unwrapNextSibling(of: firstBtn)
        XCTAssertEqual(gtkWidgetTypeName(secondBtn), "GtkToggleButton")
        let thirdBtn = try unwrapNextSibling(of: secondBtn)
        XCTAssertEqual(gtkWidgetTypeName(thirdBtn), "GtkToggleButton")
    }

    func testSegmentedPickerDoesNotFireCallbackDuringRender() throws {
        try requireGTK()

        var changedIndex: Int?
        var callbackCount = 0

        let widget = widgetFromOpaque(gtkRenderView(
            Picker(
                "Mode",
                selection: 0,
                options: ["Snapshot", "Compare", "Sync"],
                onChanged: { index in
                    changedIndex = index
                    callbackCount += 1
                }
            )
            .pickerStyle(.segmented)
            .labelsHidden()
        ))

        XCTAssertEqual(callbackCount, 0)
        XCTAssertNil(changedIndex)

        let firstButton = try unwrapFirstChild(of: widget)
        let secondButton = try unwrapNextSibling(of: firstButton)
        gtk_swift_toggle_button_set_active(secondButton, 1)

        XCTAssertEqual(callbackCount, 1)
        XCTAssertEqual(changedIndex, 1)
    }

    func testSearchScopeDescriptorDetectsSelectionChange() throws {
        try requireGTK()

        var searchText = ""
        var selection = "all"
        let textBinding = Binding(get: { searchText }, set: { searchText = $0 })
        let selBinding = Binding(get: { selection }, set: { selection = $0 })

        let oldDesc = gtkDescribeView(
            Text("X")
                .searchable(text: textBinding)
                .searchScopes(selBinding, scopes: ["all", "docs"]) { s in Text(s) }
        )

        selection = "docs"
        let newDesc = gtkDescribeView(
            Text("X")
                .searchable(text: textBinding)
                .searchScopes(selBinding, scopes: ["all", "docs"]) { s in Text(s) }
        )

        XCTAssertNotEqual(oldDesc, newDesc, "Descriptor should differ when scope selection changes")
    }

    // MARK: - Safe Area Padding Tests

    func testSafeAreaPaddingAllEdgesNilLengthUsesSyntheticDefault() throws {
        try requireGTK()

        // safeAreaPadding() with nil length should use synthetic default 16
        let desc = gtkDescribeView(Text("Hi").safeAreaPadding())
        guard case .safeAreaPadding(let props) = desc.props else {
            XCTFail("Expected .safeAreaPadding descriptor props")
            return
        }
        XCTAssertEqual(props.top, 16)
        XCTAssertEqual(props.bottom, 16)
        XCTAssertEqual(props.leading, 16)
        XCTAssertEqual(props.trailing, 16)
    }

    func testSafeAreaPaddingExplicitLength() throws {
        try requireGTK()

        let desc = gtkDescribeView(Text("Hi").safeAreaPadding(24))
        guard case .safeAreaPadding(let props) = desc.props else {
            XCTFail("Expected .safeAreaPadding descriptor props")
            return
        }
        XCTAssertEqual(props.top, 24)
        XCTAssertEqual(props.bottom, 24)
        XCTAssertEqual(props.leading, 24)
        XCTAssertEqual(props.trailing, 24)
    }

    func testSafeAreaPaddingSelectedEdges() throws {
        try requireGTK()

        let desc = gtkDescribeView(Text("Hi").safeAreaPadding([.top, .trailing], 10))
        guard case .safeAreaPadding(let props) = desc.props else {
            XCTFail("Expected .safeAreaPadding descriptor props")
            return
        }
        XCTAssertEqual(props.top, 10)
        XCTAssertEqual(props.bottom, 0)
        XCTAssertEqual(props.leading, 0)
        XCTAssertEqual(props.trailing, 10)
    }

    func testSafeAreaPaddingRenders() throws {
        try requireGTK()

        let widget = widgetFromOpaque(gtkRenderView(
            Text("Content").safeAreaPadding(8)
        ))
        XCTAssertEqual(gtkWidgetTypeName(widget), "GtkBox")

        let child = try unwrapFirstChild(of: widget)
        let label = try unwrapFirstDescendant(ofType: "GtkLabel", in: child)
        XCTAssertEqual(String(cString: gtk_label_get_text(OpaquePointer(label))), "Content")
    }

    func testSafeAreaPaddingDescriptorDetectsLengthChange() throws {
        try requireGTK()

        let oldDesc = gtkDescribeView(Text("Hi").safeAreaPadding(8))
        let newDesc = gtkDescribeView(Text("Hi").safeAreaPadding(20))

        XCTAssertNotEqual(oldDesc, newDesc, "Descriptor should differ when length changes")

        let oldId = gtkIdentifyDescriptorTree(oldDesc)
        let newId = gtkIdentifyDescriptorTree(newDesc)
        let retained = gtkRetainDescriptorTree(oldId)
        let plan = gtkPlanDescriptorTree(old: retained, new: newId)
        XCTAssertNotEqual(plan.kind, .reuse, "Plan should not be .reuse when padding changes")
    }

    func testSafeAreaPaddingNegativeLengthClampsToZero() throws {
        try requireGTK()

        let desc = gtkDescribeView(Text("Hi").safeAreaPadding(-5))
        guard case .safeAreaPadding(let props) = desc.props else {
            XCTFail("Expected .safeAreaPadding descriptor props")
            return
        }
        XCTAssertEqual(props.top, 0)
        XCTAssertEqual(props.bottom, 0)
        XCTAssertEqual(props.leading, 0)
        XCTAssertEqual(props.trailing, 0)
    }

    // MARK: - Presentation Tests

    func testSheetWithOnDismissRendersContent() throws {
        try requireGTK()

        var presented = false
        let widget = widgetFromOpaque(gtkRenderView(
            Text("Base").sheet(isPresented: Binding(get: { presented }, set: { presented = $0 }),
                               onDismiss: {}) {
                Text("Sheet")
            }
        ))
        // When not presented, should just render the base content
        let label = try unwrapFirstDescendant(ofType: "GtkLabel", in: widget)
        XCTAssertEqual(String(cString: gtk_label_get_text(OpaquePointer(label))), "Base")
    }

    func testSheetWithOnDismissPresentedRendersContent() throws {
        try requireGTK()

        var presented = true
        let widget = widgetFromOpaque(gtkRenderView(
            Text("Base").sheet(isPresented: Binding(get: { presented }, set: { presented = $0 }),
                               onDismiss: {}) {
                Text("Sheet")
            }
        ))
        // Content widget is always returned (sheet is presented via g_idle_add)
        let label = try unwrapFirstDescendant(ofType: "GtkLabel", in: widget)
        XCTAssertEqual(String(cString: gtk_label_get_text(OpaquePointer(label))), "Base")
    }

    func testItemSheetNilItemRendersContent() throws {
        try requireGTK()

        struct TestItem: Identifiable { let id: Int; let name: String }
        var item: TestItem? = nil
        let widget = widgetFromOpaque(gtkRenderView(
            Text("Base").sheet(
                item: Binding(get: { item }, set: { item = $0 })
            ) { i in
                Text(i.name)
            }
        ))
        let label = try unwrapFirstDescendant(ofType: "GtkLabel", in: widget)
        XCTAssertEqual(String(cString: gtk_label_get_text(OpaquePointer(label))), "Base")
    }

    func testItemSheetNonNilItemRendersContent() throws {
        try requireGTK()

        struct TestItem: Identifiable { let id: Int; let name: String }
        var item: TestItem? = TestItem(id: 1, name: "Hello")
        let widget = widgetFromOpaque(gtkRenderView(
            Text("Base").sheet(
                item: Binding(get: { item }, set: { item = $0 })
            ) { i in
                Text(i.name)
            }
        ))
        // Content widget is returned; sheet presented via g_idle_add
        let label = try unwrapFirstDescendant(ofType: "GtkLabel", in: widget)
        XCTAssertEqual(String(cString: gtk_label_get_text(OpaquePointer(label))), "Base")
    }

    func testItemSheetReplacesOnIdentityChange() throws {
        try requireGTK()

        struct TestItem: Identifiable { let id: Int; let name: String }
        var item: TestItem? = TestItem(id: 1, name: "First")
        let itemBinding = Binding(get: { item }, set: { item = $0 })

        // Use a GTKViewHost so we can rebuild and observe anchor state
        let host = GTKViewHost(buildBody: {
            gtkRenderView(Text("Base").sheet(item: itemBinding) { i in Text(i.name) })
        })

        let previousHost = GTKViewHost.getCurrentRebuilding()
        GTKViewHost.setCurrentRebuilding(host)
        let widget = host.buildBodyWithTracking()
        GTKViewHost.setCurrentRebuilding(previousHost)

        let child = widgetFromOpaque(widget)
        gtk_box_append(boxPointer(host.container), child)

        let anchor = host.container
        let gobject = UnsafeMutableRawPointer(anchor).assumingMemoryBound(to: GObject.self)

        // After first render with item id=1, active flag and item-id should be set
        XCTAssertNotNil(g_object_get_data(gobject, "swift-sheet-active"),
                        "Sheet should be marked active after presenting item 1")
        let firstIdHash = Int(bitPattern: g_object_get_data(gobject, "swift-sheet-item-id"))
        XCTAssertEqual(firstIdHash, 1.hashValue, "Stored identity should match item 1")

        // Simulate the deferred g_idle_add having created a sheet window.
        // In headless GTK the idle callback never runs, so we place a dummy
        // window on the anchor to exercise the dismiss-and-replace branch.
        let dummyDialog = gtk_window_new()!
        g_object_set_data(gobject, "swift-sheet-window", gpointer(windowPointer(dummyDialog)))

        // Change to item with different identity
        item = TestItem(id: 2, name: "Second")

        // Rebuild — should detect identity change, dismiss old window, present new
        GTKViewHost.setCurrentRebuilding(host)
        _ = host.buildBodyWithTracking()
        GTKViewHost.setCurrentRebuilding(previousHost)

        // After rebuild, active flag should still be set (new sheet) but item-id should change
        XCTAssertNotNil(g_object_get_data(gobject, "swift-sheet-active"),
                        "Sheet should still be active after replacing with item 2")
        let secondIdHash = Int(bitPattern: g_object_get_data(gobject, "swift-sheet-item-id"))
        XCTAssertEqual(secondIdHash, 2.hashValue, "Stored identity should match item 2")
        XCTAssertNotEqual(firstIdHash, secondIdHash,
                          "Identity should have changed from item 1 to item 2")

        // The old swift-sheet-window should have been cleared by the replacement
        // branch before scheduling the new presentation (new window not yet created
        // since g_idle_add is deferred). Verify window ref was cleared.
        XCTAssertNil(g_object_get_data(gobject, "swift-sheet-window"),
                     "Old sheet window should have been cleared during replacement")
    }

    func testAlertWithActionsAndMessageRendersContent() throws {
        try requireGTK()

        var presented = false
        let widget = widgetFromOpaque(gtkRenderView(
            Text("Base").alert("Title",
                               isPresented: Binding(get: { presented }, set: { presented = $0 }),
                               actions: [AlertButton("OK")],
                               message: "Details")
        ))
        let label = try unwrapFirstDescendant(ofType: "GtkLabel", in: widget)
        XCTAssertEqual(String(cString: gtk_label_get_text(OpaquePointer(label))), "Base")
    }

    func testAlertErrorBasedPresentedRendersContent() throws {
        try requireGTK()

        struct TestError: LocalizedError {
            var errorDescription: String? { "Something failed" }
            var failureReason: String? { "Bad input" }
        }

        var presented = true
        let error: TestError? = TestError()
        let widget = widgetFromOpaque(gtkRenderView(
            Text("Base").alert(
                isPresented: Binding(get: { presented }, set: { presented = $0 }),
                error: error
            )
        ))
        // Error-based alert with isPresented=true and non-nil error takes the
        // presenting branch (alert scheduled via g_idle_add); content still renders
        let label = try unwrapFirstDescendant(ofType: "GtkLabel", in: widget)
        XCTAssertEqual(String(cString: gtk_label_get_text(OpaquePointer(label))), "Base")
    }

    func testAlertErrorNilSuppressesPresentation() throws {
        try requireGTK()

        struct TestError: LocalizedError {
            var errorDescription: String? { "Oops" }
        }

        var presented = true
        let error: TestError? = nil
        let widget = widgetFromOpaque(gtkRenderView(
            Text("Base").alert(
                isPresented: Binding(get: { presented }, set: { presented = $0 }),
                error: error
            )
        ))
        // With nil error, effective isPresented is false — no alert should attempt presentation
        let label = try unwrapFirstDescendant(ofType: "GtkLabel", in: widget)
        XCTAssertEqual(String(cString: gtk_label_get_text(OpaquePointer(label))), "Base")
    }

    // MARK: - Confirmation Dialog Batch B Tests

    // Smoke tests: verify new overloads render without crash and return base content.
    // Actual dialog title/message rendering happens in deferred g_idle_add and is
    // not observable in headless GTK tests.

    func testConfirmationDialogWithTitleVisibilitySmoke() throws {
        try requireGTK()

        var presented = true
        let widget = widgetFromOpaque(gtkRenderView(
            Text("Base").confirmationDialog(
                "Delete?",
                isPresented: Binding(get: { presented }, set: { presented = $0 }),
                titleVisibility: .visible,
                actions: [AlertButton("Delete", role: .destructive)]
            )
        ))
        let label = try unwrapFirstDescendant(ofType: "GtkLabel", in: widget)
        XCTAssertEqual(String(cString: gtk_label_get_text(OpaquePointer(label))), "Base")
    }

    func testConfirmationDialogWithHiddenTitleSmoke() throws {
        try requireGTK()

        var presented = true
        let widget = widgetFromOpaque(gtkRenderView(
            Text("Base").confirmationDialog(
                "Hidden Title",
                isPresented: Binding(get: { presented }, set: { presented = $0 }),
                titleVisibility: .hidden,
                actions: [AlertButton("OK")]
            )
        ))
        let label = try unwrapFirstDescendant(ofType: "GtkLabel", in: widget)
        XCTAssertEqual(String(cString: gtk_label_get_text(OpaquePointer(label))), "Base")
    }

    func testConfirmationDialogWithMessageSmoke() throws {
        try requireGTK()

        var presented = true
        let widget = widgetFromOpaque(gtkRenderView(
            Text("Base").confirmationDialog(
                "Confirm",
                isPresented: Binding(get: { presented }, set: { presented = $0 }),
                titleVisibility: .automatic,
                actions: [AlertButton("Yes"), AlertButton("No")],
                message: "Are you sure?"
            )
        ))
        let label = try unwrapFirstDescendant(ofType: "GtkLabel", in: widget)
        XCTAssertEqual(String(cString: gtk_label_get_text(OpaquePointer(label))), "Base")
    }

    func testDismissalConfirmationDialogSmoke() throws {
        try requireGTK()

        var presented = true
        let widget = widgetFromOpaque(gtkRenderView(
            Text("Base").dismissalConfirmationDialog(
                "Discard changes?",
                shouldPresent: Binding(get: { presented }, set: { presented = $0 }),
                actions: [
                    AlertButton("Discard", role: .destructive),
                    AlertButton("Keep Editing", role: .cancel)
                ]
            )
        ))
        let label = try unwrapFirstDescendant(ofType: "GtkLabel", in: widget)
        XCTAssertEqual(String(cString: gtk_label_get_text(OpaquePointer(label))), "Base")
    }

    func testSheetWithDismissalInterceptionRendersContent() throws {
        try requireGTK()

        var presented = true
        var shouldConfirm = false
        // Sheet content carries dismissalConfirmationDialog
        let sheetContent = Text("Edit").dismissalConfirmationDialog(
            "Discard?",
            shouldPresent: Binding(get: { shouldConfirm }, set: { shouldConfirm = $0 }),
            actions: [AlertButton("Discard", role: .destructive)]
        )
        let widget = widgetFromOpaque(gtkRenderView(
            Text("Base").sheet(
                isPresented: Binding(get: { presented }, set: { presented = $0 })
            ) { sheetContent }
        ))
        // Base content renders normally; sheet is deferred
        let label = try unwrapFirstDescendant(ofType: "GtkLabel", in: widget)
        XCTAssertEqual(String(cString: gtk_label_get_text(OpaquePointer(label))), "Base")
    }

    // MARK: - Toolbar Tests

    func testToolbarMultiItemExtractsAllItems() throws {
        try requireGTK()

        let view = Text("Content").toolbar {
            ToolbarItem(placement: .leading) { Text("A") }
            ToolbarItem(placement: .trailing) { Text("B") }
            ToolbarItem(placement: .primaryAction) { Text("C") }
        }

        let items = gtkExtractToolbarItems(from: view)
        XCTAssertEqual(items.count, 3, "Should extract 3 toolbar items")
        XCTAssertEqual(items[0].placement, .leading)
        XCTAssertEqual(items[1].placement, .trailing)
        XCTAssertEqual(items[2].placement, .primaryAction)
    }

    func testToolbarWithIdExtractsItems() throws {
        try requireGTK()

        let view = Text("Content").toolbar(id: "my-toolbar") {
            ToolbarItem(placement: .leading) { Text("X") }
        }

        let items = gtkExtractToolbarItems(from: view)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].placement, .leading)
    }

    func testMetadataExtractionDoesNotEnterOpaqueBoundary() throws {
        try requireGTK()

        final class EvaluationCounter {
            var value = 0
        }

        struct Boundary<Content: View>: View, _ViewMetadataExtractionBoundary {
            let counter: EvaluationCounter
            let content: Content

            var body: some View {
                counter.value += 1
                return content
            }
        }

        let counter = EvaluationCounter()
        let boundary = Boundary(
            counter: counter,
            content: Text("Native content")
                .navigationTitle("Hidden title")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) { Text("Hidden action") }
                }
                .toolbar(.hidden, for: .navigationBar)
        )

        XCTAssertEqual(gtkExtractTitle(from: boundary), "")
        XCTAssertTrue(gtkExtractToolbarItems(from: boundary).isEmpty)
        XCTAssertNil(gtkExtractToolbarConfiguration(from: boundary))
        XCTAssertEqual(counter.value, 0, "Metadata extraction must not evaluate a boundary body")
    }

    func testMetadataOutsideOpaqueBoundaryStillExtracts() throws {
        try requireGTK()

        struct Boundary: View, _ViewMetadataExtractionBoundary {
            var body: some View { Text("Native content") }
        }

        let view = Boundary()
            .navigationTitle("Visible title")
            .toolbar {
                ToolbarItem(placement: .primaryAction) { Text("Visible action") }
            }
            .toolbar(.hidden, for: .navigationBar)

        XCTAssertEqual(gtkExtractTitle(from: view), "Visible title")
        XCTAssertEqual(gtkExtractToolbarItems(from: view).count, 1)
        XCTAssertEqual(gtkExtractToolbarConfiguration(from: view)?.visibility, .hidden)
    }

    func testDescriptorExtractionDoesNotEnterOpaqueBoundary() throws {
        try requireGTK()

        final class EvaluationCounter {
            var value = 0
        }

        struct Boundary: View, _ViewMetadataExtractionBoundary {
            let counter: EvaluationCounter

            var body: some View {
                counter.value += 1
                return Text("Native content")
            }
        }

        let counter = EvaluationCounter()
        let descriptor = gtkDescribeView(Boundary(counter: counter))

        XCTAssertEqual(counter.value, 0, "Descriptor extraction must not evaluate a boundary body")
        XCTAssertEqual(descriptor.kind, .composite)
        XCTAssertTrue(descriptor.children.isEmpty)
    }

    func testToolbarRendersContentPassthrough() throws {
        try requireGTK()

        let widget = widgetFromOpaque(gtkRenderView(
            Text("Main").toolbar {
                ToolbarItem(placement: .trailing) { Text("Action") }
            }
        ))
        // ToolbarView renders content; items extracted by NavigationStack
        let label = try unwrapFirstDescendant(ofType: "GtkLabel", in: widget)
        XCTAssertEqual(String(cString: gtk_label_get_text(OpaquePointer(label))), "Main")
    }

    func testNavigationStackSyncsTypedBoundPathChanges() throws {
        try requireGTK()

        var path: [String] = []
        let widget = widgetFromOpaque(gtkRenderView(
            NavigationStack(
                path: Binding<[String]>(
                    get: { path },
                    set: { path = $0 }
                )
            ) {
                Text("Root")
                    .navigationDestination(for: String.self) { value in
                        Text("Detail \(value)")
                    }
            }
        ))

        XCTAssertEqual(gtkTestNavigationEntryCount(in: widget), 1)

        path = ["1003"]
        XCTAssertEqual(
            gtkTestSyncNavigationPath(in: widget),
            2,
            "Programmatic NavigationStack(path:) mutations should push the registered destination."
        )
        let pushedName = gtk_stack_get_visible_child_name(OpaquePointer(widget))
            .map { String(cString: $0) }
        XCTAssertNotEqual(pushedName, "nav-root")

        path = []
        XCTAssertEqual(
            gtkTestSyncNavigationPath(in: widget),
            1,
            "Programmatic NavigationStack(path:) removals should pop back to the root entry."
        )
        let rootName = gtk_stack_get_visible_child_name(OpaquePointer(widget))
            .map { String(cString: $0) }
        XCTAssertEqual(rootName, "nav-root")
    }

    func testNavigationDestinationIsPresentedPushesAndClearsBindingOnPop() throws {
        try requireGTK()

        var isPresented = true
        let widget = widgetFromOpaque(gtkRenderView(
            NavigationStack {
                Text("Root")
                    .navigationDestination(
                        isPresented: Binding<Bool>(
                            get: { isPresented },
                            set: { isPresented = $0 }
                        )
                    ) {
                        Text("Presented Destination")
                    }
            }
        ))

        XCTAssertEqual(
            gtkTestNavigationEntryCount(in: widget),
            2,
            "navigationDestination(isPresented:) should push when its binding is true."
        )
        guard let visibleChild = gtk_stack_get_visible_child(OpaquePointer(widget)) else {
            XCTFail("Expected a visible navigation stack child")
            return
        }
        XCTAssertTrue(
            gtkLabelTexts(in: visibleChild).contains("Presented Destination"),
            "Expected presented destination to become visible, got: \(gtkLabelTexts(in: visibleChild))"
        )

        XCTAssertEqual(gtkTestPopNavigation(in: widget), 1)
        XCTAssertFalse(
            isPresented,
            "Popping a navigationDestination(isPresented:) route should clear the source binding."
        )
    }

    func testNavigationDestinationIsPresentedPushesAfterStateMutationInChildHost() throws {
        try requireGTK()

        let widget = widgetFromOpaque(gtkRenderView(
            NavigationStack {
                GTKPresentedNavigationStateProbeView()
            }
        ))

        XCTAssertEqual(
            gtkTestNavigationEntryCount(in: widget),
            1,
            "The presented destination starts inactive."
        )

        var buttons: [UnsafeMutablePointer<GtkWidget>] = []
        gtkCollectButtons(in: widget, into: &buttons)
        guard let showButton = buttons.first(where: { gtkLabelTexts(in: $0).contains("Show Presented") }) else {
            XCTFail("Expected a button that mutates the child host's @State.")
            return
        }

        XCTAssertTrue(gtkTestActivateButton(showButton))
        XCTAssertTrue(
            waitForGTKLabelText(in: widget, timeout: 1.0) { labels in
                labels.contains("Presented After State")
            },
            "A child ViewHost state mutation should restore the NavigationStack context and push the destination."
        )
        XCTAssertEqual(
            gtkTestNavigationEntryCount(in: widget),
            2,
            "navigationDestination(isPresented:) should push after its source binding changes."
        )
    }

    func testNavigationDestinationIsPresentedDismissActionPopsRouteAndClearsBinding() throws {
        try requireGTK()

        var isPresented = true
        let widget = widgetFromOpaque(gtkRenderView(
            NavigationStack {
                Text("Root")
                    .navigationDestination(
                        isPresented: Binding<Bool>(
                            get: { isPresented },
                            set: { isPresented = $0 }
                        )
                    ) {
                        GTKPresentedNavigationDismissDestination()
                    }
            }
        ))

        XCTAssertEqual(
            gtkTestNavigationEntryCount(in: widget),
            2,
            "The presented destination starts pushed."
        )

        var buttons: [UnsafeMutablePointer<GtkWidget>] = []
        gtkCollectButtons(in: widget, into: &buttons)
        guard let dismissButton = buttons.first(where: { gtkLabelTexts(in: $0).contains("Dismiss Destination") }) else {
            XCTFail("Expected the destination button that calls dismiss().")
            return
        }

        XCTAssertTrue(gtkTestActivateButton(dismissButton))
        let popped = waitForGTKLabelText(in: widget, timeout: 1.0) { labels in
            labels.contains("Root") && !labels.contains("Dismiss Destination")
        }
        XCTAssertTrue(popped, "dismiss() from a navigation destination should pop back to root.")
        XCTAssertEqual(
            gtkTestNavigationEntryCount(in: widget),
            1,
            "dismiss() from a navigation destination should remove the pushed route."
        )
        XCTAssertFalse(
            isPresented,
            "dismiss() should clear the navigationDestination(isPresented:) binding through the normal pop path."
        )
    }

    func testNavigationDestinationIsPresentedPushesAfterPickerSelectionMutation() throws {
        try requireGTK()

        let widget = widgetFromOpaque(gtkRenderView(
            NavigationStack {
                GTKPresentedNavigationPickerProbeView()
            }
        ))

        XCTAssertEqual(
            gtkTestNavigationEntryCount(in: widget),
            1,
            "The picker-driven presented destination starts inactive."
        )

        guard let dropdown = gtkFirstDescendant(ofType: "GtkDropDown", in: widget) else {
            XCTFail(
                "Expected picker probe to render a GtkDropDown. Tree:\n\(gtkSnapshotTree(root: widget).debugDescription())"
            )
            return
        }
        gtk_drop_down_set_selected(OpaquePointer(dropdown), guint(1))

        XCTAssertTrue(
            waitForGTKLabelText(in: widget, timeout: 1.0) { labels in
                labels.contains("Picker Presented Destination")
            },
            "A Picker binding setter should be able to toggle navigationDestination(isPresented:)."
        )
        XCTAssertEqual(
            gtkTestNavigationEntryCount(in: widget),
            2,
            "navigationDestination(isPresented:) should push after a Picker selection mutates its source binding."
        )
    }

    func testNavigationStackSyncsTypedBoundPathDestinationContentFromSwitchBuilder() throws {
        try requireGTK()

        enum Route: Hashable {
            case tags
            case accounts
        }

        var path: [Route] = []
        let widget = widgetFromOpaque(gtkRenderView(
            NavigationStack(
                path: Binding<[Route]>(
                    get: { path },
                    set: { path = $0 }
                )
            ) {
                Text("Root")
                    .navigationDestination(for: Route.self) { route in
                        switch route {
                        case .tags:
                            Text("Tags Destination")
                        case .accounts:
                            Text("Accounts Destination")
                        }
                    }
            }
        ))

        path = [.accounts]
        XCTAssertEqual(gtkTestSyncNavigationPath(in: widget), 2)

        guard let visibleChild = gtk_stack_get_visible_child(OpaquePointer(widget)) else {
            XCTFail("Expected a visible navigation stack child")
            return
        }

        let labels = gtkLabelTexts(in: visibleChild)
        XCTAssertTrue(
            labels.contains("Accounts Destination"),
            "Expected pushed accounts destination label, got: \(labels)"
        )
        XCTAssertFalse(
            labels.contains("Tags Destination"),
            "Inactive switch branch should not render, got: \(labels)"
        )
        XCTAssertFalse(
            labels.contains("Root"),
            "Root label should not remain in the visible pushed child, got: \(labels)"
        )
    }

    func testNavigationStackProgrammaticTypedPathRunsDestinationOnAppear() throws {
        try requireGTK()

        var path: [String] = []
        let counter = GTKTaskRunCounter()
        let widget = widgetFromOpaque(gtkRenderView(
            NavigationStack(
                path: Binding<[String]>(
                    get: { path },
                    set: { path = $0 }
                )
            ) {
                Text("Root")
                    .navigationDestination(for: String.self) { value in
                        GTKBoundNavigationOnAppearProbeView(value: value, counter: counter)
                    }
            }
        ))
        let window = presentGTKWidget(widget)
        defer {
            gtk_window_destroy(windowPointer(window))
            drainGTKMainContext(maxIterations: 100)
        }

        XCTAssertEqual(counter.value, 0)
        path = ["posts"]
        XCTAssertEqual(gtkTestSyncNavigationPath(in: widget), 2)
        XCTAssertTrue(
            counter.waitForCount(1, timeout: 1.0),
            "Programmatic NavigationStack(path:) pushes should fire destination onAppear after the destination becomes visible."
        )
        XCTAssertTrue(
            waitForGTKLabelText(in: widget, timeout: 1.0) { labels in
                labels.contains("Appeared posts")
            },
            "Destination onAppear state update should repaint the visible navigation page, got: \(gtkLabelTexts(in: widget))"
        )
    }

    func testNavigationStackProgrammaticTypedPathObservesDestinationStateObservableObject() throws {
        try requireGTK()

        var path: [String] = []
        let counter = GTKTaskRunCounter()
        let widget = widgetFromOpaque(gtkRenderView(
            NavigationStack(
                path: Binding<[String]>(
                    get: { path },
                    set: { path = $0 }
                )
            ) {
                Text("Root")
                    .navigationDestination(for: String.self) { value in
                        GTKBoundNavigationObservableProbeView(value: value, counter: counter)
                    }
            }
        ))
        let window = presentGTKWidget(widget)
        defer {
            gtk_window_destroy(windowPointer(window))
            drainGTKMainContext(maxIterations: 100)
        }

        XCTAssertEqual(counter.value, 0)
        path = ["posts"]
        XCTAssertEqual(gtkTestSyncNavigationPath(in: widget), 2)
        XCTAssertTrue(
            counter.waitForCount(1, timeout: 1.0),
            "Programmatic NavigationStack(path:) pushes should fire destination onAppear for @State observable models."
        )
        XCTAssertTrue(
            waitForGTKLabelText(in: widget, timeout: 1.0) { labels in
                labels.contains("Loaded posts")
            },
            "Destination @State ObservableObject changes should repaint the visible navigation page, got: \(gtkLabelTexts(in: widget))"
        )
    }

    func testNavigationStackBoundPathDestinationStateSurvivesParentRebuild() throws {
        try requireGTK()

        var path: [String] = ["accounts"]
        let counter = GTKTaskRunCounter()

        gtkBeginStateIdentityPass()
        let firstStack = widgetFromOpaque(gtkRenderView(
            NavigationStack(
                path: Binding<[String]>(
                    get: { path },
                    set: { path = $0 }
                )
            ) {
                GTKBoundNavigationRootContentProbeView(includePrefix: false, counter: counter)
            }
        ))
        let firstWindow = presentGTKWidget(firstStack)
        defer {
            gtk_window_destroy(windowPointer(firstWindow))
            drainGTKMainContext(maxIterations: 100)
        }
        XCTAssertEqual(gtkWidgetTypeName(firstStack), "GtkStack")

        var buttons: [UnsafeMutablePointer<GtkWidget>] = []
        gtkCollectButtons(in: firstStack, into: &buttons)
        let loadButton = try XCTUnwrap(buttons.first, "Expected the destination to render a Load button.")
        XCTAssertTrue(gtkTestActivateButton(loadButton))
        drainGTKMainContext(maxIterations: 100)
        XCTAssertEqual(counter.value, 1)
        XCTAssertTrue(
            waitForGTKLabelText(in: firstStack, timeout: 1.0) { labels in
                labels.contains("Loaded accounts")
            },
            "Expected destination button to publish its loaded state, got: \(gtkLabelTexts(in: firstStack))"
        )

        gtkBeginStateIdentityPass()
        let secondStack = widgetFromOpaque(gtkRenderView(
            NavigationStack(
                path: Binding<[String]>(
                    get: { path },
                    set: { path = $0 }
                )
            ) {
                GTKBoundNavigationRootContentProbeView(includePrefix: true, counter: counter)
            }
        ))
        let secondWindow = presentGTKWidget(secondStack)
        defer {
            gtk_window_destroy(windowPointer(secondWindow))
            drainGTKMainContext(maxIterations: 100)
        }
        XCTAssertEqual(gtkWidgetTypeName(secondStack), "GtkStack")

        XCTAssertTrue(
            waitForGTKLabelText(in: secondStack, timeout: 1.0) { labels in
                labels.contains("Loaded accounts")
            },
            "Root rebuild should preserve pushed destination state, got: \(gtkLabelTexts(in: secondStack))"
        )
        XCTAssertEqual(
            counter.value,
            1,
            "Destination @State should not reset when the NavigationStack root structure changes."
        )
    }

    // MARK: - Toolbar Batch B Tests

    func testToolbarConfigurationViewRendersContent() throws {
        try requireGTK()

        let widget = widgetFromOpaque(gtkRenderView(
            Text("Content").toolbar(.hidden, for: .navigationBar)
        ))
        let label = try unwrapFirstDescendant(ofType: "GtkLabel", in: widget)
        XCTAssertEqual(String(cString: gtk_label_get_text(OpaquePointer(label))), "Content")
    }

    func testToolbarConfigurationExtractsHiddenVisibility() throws {
        try requireGTK()

        let view = Text("X").toolbar(.hidden, for: .navigationBar)
        let config = gtkExtractToolbarConfiguration(from: view)
        XCTAssertNotNil(config)
        XCTAssertEqual(config?.visibility, .hidden)
        XCTAssertEqual(config?.visibilityTarget, .navigationBar)
    }

    func testToolbarConfigurationRemovesPlacement() throws {
        try requireGTK()

        let view = Text("X")
            .toolbar {
                ToolbarItem(placement: .leading) { Text("A") }
                ToolbarItem(placement: .trailing) { Text("B") }
            }
            .toolbar(removing: .leading)

        let items = gtkExtractToolbarItems(from: view)
        let config = gtkExtractToolbarConfiguration(from: view)
        let (filtered, hidden) = gtkApplyToolbarConfiguration(items: items, configuration: config)

        XCTAssertFalse(hidden)
        XCTAssertEqual(filtered.count, 1, "Leading item should be removed")
        XCTAssertEqual(filtered[0].placement, .trailing)
    }

    func testToolbarHiddenForBottomBarDoesNotAffectGTK() throws {
        try requireGTK()

        let items = [
            AnyToolbarItem(ToolbarItem(placement: .leading) { Text("A") }),
        ]
        let config = ToolbarConfiguration(visibility: .hidden, visibilityTarget: .bottomBar)
        let (filtered, hidden) = gtkApplyToolbarConfiguration(items: items, configuration: config)
        XCTAssertFalse(hidden, "Hidden for .bottomBar should not suppress GTK navigation-bar toolbar")
        XCTAssertEqual(filtered.count, 1)
    }

    func testToolbarHiddenVisibilityFiltersAllItems() throws {
        try requireGTK()

        let items = [
            AnyToolbarItem(ToolbarItem(placement: .leading) { Text("A") }),
            AnyToolbarItem(ToolbarItem(placement: .trailing) { Text("B") }),
        ]
        let config = ToolbarConfiguration(visibility: .hidden, visibilityTarget: .navigationBar)
        let (_, hidden) = gtkApplyToolbarConfiguration(items: items, configuration: config)
        XCTAssertTrue(hidden, "Hidden visibility should suppress toolbar")
    }

    func testToolbarHiddenVisibilityWorksWhenAppliedAfterItems() throws {
        try requireGTK()

        let view = Text("X")
            .toolbar {
                ToolbarItem(placement: .trailing) { Text("A") }
            }
            .toolbar(.hidden, for: .navigationBar)

        let items = gtkExtractToolbarItems(from: view)
        let config = gtkExtractToolbarConfiguration(from: view)
        let (_, hidden) = gtkApplyToolbarConfiguration(items: items, configuration: config)

        XCTAssertTrue(hidden, "Hidden visibility should apply when configuration wraps toolbar items")
    }

    func testToolbarHiddenVisibilityWorksWhenAppliedBeforeItems() throws {
        try requireGTK()

        let view = Text("X")
            .toolbar(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .trailing) { Text("A") }
            }

        let items = gtkExtractToolbarItems(from: view)
        let config = gtkExtractToolbarConfiguration(from: view)
        let (_, hidden) = gtkApplyToolbarConfiguration(items: items, configuration: config)

        XCTAssertTrue(hidden, "Hidden visibility should apply when toolbar items wrap configuration")
    }

    func testToolbarMixedVisibilityAndRemovalChainPreservesBothSettings() throws {
        try requireGTK()

        let view = Text("X")
            .toolbar(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .leading) { Text("A") }
                ToolbarItem(placement: .trailing) { Text("B") }
            }
            .toolbar(removing: .leading)

        let items = gtkExtractToolbarItems(from: view)
        let config = gtkExtractToolbarConfiguration(from: view)
        let (filtered, hidden) = gtkApplyToolbarConfiguration(items: items, configuration: config)

        XCTAssertTrue(hidden, "Hidden visibility should survive the mixed chain")
        XCTAssertEqual(config?.removedPlacements, [.leading], "Removed placements should survive the mixed chain")
        XCTAssertEqual(filtered.count, 1, "Leading item should still be removed in the mixed chain")
        XCTAssertEqual(filtered[0].placement, .trailing)
    }

    // MARK: - ViewThatFits Tests

    func testViewThatFitsRendersAsGtkStack() throws {
        try requireGTK()

        let widget = widgetFromOpaque(gtkRenderView(
            ViewThatFits {
                Text("Wide layout with lots of text")
                Text("Compact")
            }
        ))
        XCTAssertEqual(gtkWidgetTypeName(widget), "GtkStack",
                       "ViewThatFits should render as a GtkStack")
    }

    func testViewThatFitsShowsFirstChildInitially() throws {
        try requireGTK()

        let widget = widgetFromOpaque(gtkRenderView(
            ViewThatFits {
                Text("First")
                Text("Second")
                Text("Third")
            }
        ))
        // Initial visible child should be vtf-0
        let visibleName = gtk_stack_get_visible_child_name(OpaquePointer(widget))
        XCTAssertNotNil(visibleName)
        if let name = visibleName {
            XCTAssertEqual(String(cString: name), "vtf-0",
                           "Should show first child initially")
        }
    }

    func testViewThatFitsEmptyContentRendersEmptyStack() throws {
        try requireGTK()

        let widget = widgetFromOpaque(gtkRenderView(
            ViewThatFits { }
        ))
        XCTAssertEqual(gtkWidgetTypeName(widget), "GtkStack")
        // No children — should not crash
        XCTAssertNil(gtk_widget_get_first_child(widget))
    }

    func testViewThatFitsSingleChildRendersIt() throws {
        try requireGTK()

        let widget = widgetFromOpaque(gtkRenderView(
            ViewThatFits {
                Text("Only child")
            }
        ))
        XCTAssertEqual(gtkWidgetTypeName(widget), "GtkStack")
        let label = try unwrapFirstDescendant(ofType: "GtkLabel", in: widget)
        XCTAssertEqual(String(cString: gtk_label_get_text(OpaquePointer(label))), "Only child")
    }

    // MARK: - Disabled Tests

    func testDisabledButtonIsSensitiveFalse() throws {
        try requireGTK()

        let widget = widgetFromOpaque(gtkRenderView(
            Button("Tap") {}.disabled(true)
        ))
        XCTAssertEqual(gtk_widget_get_sensitive(widget), 0,
                       "Disabled button should have sensitivity = false")
    }

    func testEnabledButtonIsSensitiveTrue() throws {
        try requireGTK()

        let widget = widgetFromOpaque(gtkRenderView(
            Button("Tap") {}.disabled(false)
        ))
        XCTAssertNotEqual(gtk_widget_get_sensitive(widget), 0,
                          "Enabled button should have sensitivity = true")
    }

    func testNestedDisabledCannotReEnable() throws {
        try requireGTK()

        // Parent disabled(true) wraps child disabled(false) — should still be disabled
        let widget = widgetFromOpaque(gtkRenderView(
            Button("Tap") {}.disabled(false).disabled(true)
        ))
        XCTAssertEqual(gtk_widget_get_sensitive(widget), 0,
                       "Ancestor disabled(true) should not be undone by child disabled(false)")
    }

    func testDisabledTextFieldIsSensitiveFalse() throws {
        try requireGTK()

        var text = ""
        let widget = widgetFromOpaque(gtkRenderView(
            TextField("Name", text: Binding(get: { text }, set: { text = $0 })).disabled(true)
        ))
        XCTAssertEqual(gtk_widget_get_sensitive(widget), 0,
                       "Disabled text field should have sensitivity = false")
    }

    // MARK: - Image.resizable()

    func testFileImageRendersAsGtkPicture() throws {
        try requireGTK()

        let widget = widgetFromOpaque(gtkRenderView(
            Image(filePath: "/tmp/does-not-exist.jpg")
        ))
        XCTAssertEqual(gtkWidgetTypeName(widget), "GtkPicture",
                       "Image(filePath:) should render as GtkPicture, not GtkImage")
    }

    func testFileImageNonResizableHasNoExpandFlags() throws {
        try requireGTK()

        let widget = widgetFromOpaque(gtkRenderView(
            Image(filePath: "/tmp/does-not-exist.jpg")
        ))
        XCTAssertEqual(gtk_widget_get_hexpand(widget), 0,
                       "Non-resizable image should not advertise horizontal expansion")
        XCTAssertEqual(gtk_widget_get_vexpand(widget), 0,
                       "Non-resizable image should not advertise vertical expansion")
    }

    func testFileImageResizableAdvertisesFillBehavior() throws {
        try requireGTK()

        let widget = widgetFromOpaque(gtkRenderView(
            Image(filePath: "/tmp/does-not-exist.jpg").resizable()
        ))
        XCTAssertEqual(gtkWidgetTypeName(widget), "GtkPicture",
                       "Resizable image should also render as GtkPicture")
        XCTAssertEqual(gtk_widget_get_hexpand(widget), 1,
                       "Resizable image must set hexpand so FrameView stretches it")
        XCTAssertEqual(gtk_widget_get_vexpand(widget), 1,
                       "Resizable image must set vexpand so FrameView stretches it")
        XCTAssertEqual(gtk_widget_get_halign(widget), GTK_ALIGN_FILL,
                       "Resizable image must use FILL alignment horizontally")
        XCTAssertEqual(gtk_widget_get_valign(widget), GTK_ALIGN_FILL,
                       "Resizable image must use FILL alignment vertically")
    }

    // MARK: - Deferred callback environment binding

    func testBindActionToCurrentEnvironmentCapturesAndRestores() async throws {
        try requireGTK()

        let model = GTKDelayedEnvModel()
        let completed = expectation(description: "Bound action completed")
        var env = getCurrentEnvironment()
        env.setObject(model)

        let previousEnv = getCurrentEnvironment()
        setCurrentEnvironment(env)
        let bound = bindActionToCurrentEnvironment {
            model.count += 1
            completed.fulfill()
        }
        setCurrentEnvironment(previousEnv)

        // The closure should still access the captured environment even though
        // the current environment no longer contains the model.
        bound()
        await fulfillment(of: [completed], timeout: 1)
        XCTAssertEqual(model.count, 1,
                       "Bound callback should execute with the captured render-time environment")
    }

    func testBindActionToCurrentEnvironmentGenericCapturesAndRestores() async throws {
        try requireGTK()

        let model = GTKDelayedEnvModel()
        let completed = expectation(description: "Generic bound action completed")
        var env = getCurrentEnvironment()
        env.setObject(model)

        let previousEnv = getCurrentEnvironment()
        setCurrentEnvironment(env)
        let bound: (Int) -> Void = bindActionToCurrentEnvironment { value in
            model.count += value
            completed.fulfill()
        }
        setCurrentEnvironment(previousEnv)

        bound(5)
        await fulfillment(of: [completed], timeout: 1)
        XCTAssertEqual(model.count, 5,
                       "Generic bound callback should execute with the captured environment")
    }

    @MainActor
    func testBoundActionReleasesMainActorStateInsideSwiftTask() async throws {
        try requireGTK()

        let completed = expectation(description: "Main-actor state released")
        let bound = bindActionToCurrentEnvironment {
            XCTAssertNotNil(
                withUnsafeCurrentTask { $0 },
                "Native callbacks must enter a Swift task before opening task-local scopes."
            )
            var models = [GTKMainActorDeinitProbe()]
            models.removeAll()
            completed.fulfill()
        }

        bound()
        await fulfillment(of: [completed], timeout: 1)
    }

    func testBoundActionPropagatesEnvironmentIntoChildTask() async throws {
        try requireGTK()

        let model = GTKDelayedEnvModel()
        var environment = getCurrentEnvironment()
        environment.setObject(model)

        let completed = expectation(description: "Child task inherited callback environment")
        let previousEnvironment = getCurrentEnvironment()
        setCurrentEnvironment(environment)
        let property = Environment(GTKDelayedEnvModel.self)
        let bound = bindActionToCurrentEnvironment {
            Task {
                await Task.yield()
                XCTAssertTrue(property.wrappedValue === model)
                property.wrappedValue.count += 1
                completed.fulfill()
            }
        }
        setCurrentEnvironment(previousEnvironment)

        bound()
        await fulfillment(of: [completed], timeout: 1)
        XCTAssertEqual(model.count, 1)
    }

    func testContextMenuUnparentsPopoverBeforeAnchorFinalization() throws {
        try requireGTK()

        let widget = widgetFromOpaque(gtkRenderView(
            Button("Account") {}
                .contextMenu {
                    Button("Switch") {}
                }
        ))
        let popover = try unwrapFirstDescendant(
            ofType: "GtkPopoverMenu",
            in: widget
        )
        XCTAssertEqual(gtk_widget_get_parent(popover), widget)

        g_object_ref(gpointer(popover))
        let window = presentGTKWidget(widget)
        gtk_window_destroy(windowPointer(window))
        drainGTKMainContext(maxIterations: 100)

        XCTAssertNil(
            gtk_widget_get_parent(popover),
            "Context-menu popovers must be detached before a plain GTK anchor is finalized."
        )
        g_object_unref(gpointer(popover))
    }

    func testDetachedContextMenuPopoverLivesUntilAnchorFinalization() throws {
        try requireGTK()

        let widget = widgetFromOpaque(gtkRenderView(
            Button("Account") {}
                .contextMenu {
                    Button("Switch") {}
                }
        ))
        let popover = try unwrapFirstDescendant(
            ofType: "GtkPopoverMenu",
            in: widget
        )
        let window = presentGTKWidget(widget)

        gtk_widget_unparent(popover)
        XCTAssertNil(gtk_widget_get_parent(popover))
        XCTAssertNotEqual(
            gtk_swift_is_widget(popover),
            0,
            "The anchor's signal closure must keep a detached popover alive until teardown."
        )

        gtk_window_destroy(windowPointer(window))
        drainGTKMainContext(maxIterations: 100)
    }

    func testButtonRendersWithEnvironmentBinding() throws {
        try requireGTK()

        let model = GTKDelayedEnvModel()
        let widget = widgetFromOpaque(gtkRenderView(
            GTKDelayedEnvButtonView().environment(model)
        ))
        XCTAssertNotNil(widget,
                        "Button view with .environment(model) should render a widget")
    }

    func testDescriptorPassAppliesEnvironmentObservableModifier() throws {
        try requireGTK()

        let model = GTKDelayedEnvModel()
        model.count = 7

        let descriptor = gtkDescribeView(
            GTKDelayedEnvDescriptorTextView().environment(model)
        )

        XCTAssertTrue(
            gtkDescriptorContainsText(descriptor, "count 7"),
            "Descriptor passes must apply .environment(object) before describing descendants"
        )
    }

    func testOnAppearRendersWithEnvironmentBinding() throws {
        try requireGTK()

        let model = GTKDelayedEnvModel()
        let widget = widgetFromOpaque(gtkRenderView(
            GTKDelayedEnvOnAppearView().environment(model)
        ))
        XCTAssertNotNil(widget,
                        "onAppear view with .environment(model) should render a widget")
    }

    func testOnDisappearRendersWithEnvironmentBinding() throws {
        try requireGTK()

        let model = GTKDelayedEnvModel()
        let widget = widgetFromOpaque(gtkRenderView(
            GTKDelayedEnvOnDisappearView().environment(model)
        ))
        XCTAssertNotNil(widget,
                        "onDisappear view with .environment(model) should render a widget")
    }

    func testTaskRunsOnceAcrossUnrelatedStateRebuilds() throws {
        try requireGTK()

        let tick = State(wrappedValue: 0)
        let counter = GTKTaskRunCounter()

        let widget = widgetFromOpaque(gtkRenderView(
            GTKTaskOnceProbeView(tick: tick, counter: counter)
        ))
        let window = presentGTKWidget(widget)
        defer {
            gtk_window_destroy(windowPointer(window))
            drainGTKMainContext(maxIterations: 100)
        }
        XCTAssertNotNil(widget)
        XCTAssertTrue(counter.waitForCount(1, timeout: 1.0),
                      "Initial .task should run")

        for value in 1...5 {
            tick.storage.setValue(value)
            drainGTKMainContext()
        }

        Thread.sleep(forTimeInterval: 0.1)
        drainGTKMainContext()

        XCTAssertEqual(counter.value, 1,
                       ".task should not re-run for unrelated rebuilds of the same descriptor identity")
    }

    func testTaskRunsOnceAcrossFullTeardownRebuilds() throws {
        try requireGTK()

        let tick = State(wrappedValue: 0)
        let counter = GTKTaskRunCounter()

        let widget = widgetFromOpaque(gtkRenderView(
            GTKTaskFullRebuildProbeView(tick: tick, counter: counter)
        ))
        let window = presentGTKWidget(widget)
        defer {
            gtk_window_destroy(windowPointer(window))
            drainGTKMainContext(maxIterations: 100)
        }
        XCTAssertNotNil(widget)
        XCTAssertTrue(counter.waitForCount(1, timeout: 1.0),
                      "Initial .task should run")

        for value in 1...5 {
            tick.storage.setValue(value)
            drainGTKMainContext(maxIterations: 100)
        }

        Thread.sleep(forTimeInterval: 0.1)
        drainGTKMainContext(maxIterations: 100)

        XCTAssertEqual(counter.value, 1,
                       ".task should not re-run when a stable task view's child subtree is torn down and rebuilt")
    }

    func testDetachedPresentedHostDefersStateRebuildUntilRemount() throws {
        try requireGTK()

        let value = State(wrappedValue: 0)
        let widget = widgetFromOpaque(gtkRenderView(
            GTKDetachedRebuildProbeView(value: value)
        ))
        let window = presentGTKWidget(widget)
        g_object_ref(gpointer(widget))
        defer {
            gtk_window_destroy(windowPointer(window))
            g_object_unref(gpointer(widget))
            drainGTKMainContext(maxIterations: 100)
        }

        XCTAssertTrue(gtkLabelTexts(in: widget).contains("value 0"))

        gtk_window_set_child(windowPointer(window), nil)
        drainGTKMainContext(maxIterations: 100)
        value.storage.setValue(1)
        drainGTKMainContext(maxIterations: 100)

        XCTAssertTrue(
            gtkLabelTexts(in: widget).contains("value 0"),
            "A previously presented host must not rebuild an obsolete subtree while detached"
        )

        gtk_window_set_child(windowPointer(window), widget)
        XCTAssertTrue(
            waitForGTKLabelText(in: widget, timeout: 1.0) { $0.contains("value 1") },
            "The deferred state rebuild must run after the host is rooted again"
        )
    }

    func testTaskInsideTabViewRunsFromHostDescriptorLifecycle() throws {
        try requireGTK()

        let counter = GTKTaskRunCounter()

        let widget = widgetFromOpaque(gtkRenderView(
            GTKTabTaskProbeView(counter: counter)
        ))
        let window = presentGTKWidget(widget)
        defer {
            gtk_window_destroy(windowPointer(window))
            drainGTKMainContext(maxIterations: 100)
        }
        XCTAssertNotNil(widget)
        XCTAssertTrue(counter.waitForCount(1, timeout: 1.0),
                      ".task inside a TabView child should be collected by the host descriptor lifecycle")
    }

    func testStackedStandaloneTasksOnSameWidgetBothRun() throws {
        try requireGTK()

        let counter = GTKTaskRunCounter()

        let widget = widgetFromOpaque(gtkRenderView(
            Text("stacked")
                .task {
                    counter.increment()
                }
                .task {
                    counter.increment()
                }
        ))
        let window = presentGTKWidget(widget)
        defer {
            gtk_window_destroy(windowPointer(window))
            drainGTKMainContext(maxIterations: 100)
        }
        XCTAssertNotNil(widget)
        XCTAssertTrue(counter.waitForCount(2, timeout: 1.0),
                      "Stacked standalone .task modifiers should both run even when they attach to the same GTK widget")
    }

    func testOnAppearRunsOnceAcrossUnrelatedStateRebuilds() throws {
        try requireGTK()

        let tick = State(wrappedValue: 0)
        let counter = GTKTaskRunCounter()

        let widget = widgetFromOpaque(gtkRenderView(
            GTKOnAppearOnceProbeView(tick: tick, counter: counter)
        ))
        let window = presentGTKWidget(widget)
        defer {
            gtk_window_destroy(windowPointer(window))
            drainGTKMainContext(maxIterations: 100)
        }
        XCTAssertTrue(counter.waitForCount(1, timeout: 1.0),
                      "Initial onAppear should run")

        for value in 1...5 {
            tick.storage.setValue(value)
            drainGTKMainContext(maxIterations: 100)
        }

        XCTAssertEqual(counter.value, 1,
                       "onAppear should not re-run for unrelated rebuilds of the same descriptor identity")
    }

    func testReactiveGTKRenderableLeavesNestedOnAppearWithEnclosingHost() throws {
        try requireGTK()

        let counter = GTKTaskRunCounter()
        let widget = widgetFromOpaque(gtkRenderWindowRootView(
            GTKReactiveRenderableOnAppearProbe(counter: counter)
        ))
        let window = presentGTKWidget(widget)
        defer {
            gtk_window_destroy(windowPointer(window))
            drainGTKMainContext(maxIterations: 100)
        }

        XCTAssertTrue(
            counter.waitForCount(1, timeout: 1.0),
            "A reactive GTKRenderable is rendered inline, so its nested onAppear must be owned by the enclosing host"
        )
        drainGTKMainContext(maxIterations: 100)
        XCTAssertEqual(counter.value, 1)
    }

    func testOnAppearSurvivesParentHostFullRemountWhenStateIdentityMatches() throws {
        try requireGTK()

        let tick = State(wrappedValue: 0)
        let counter = GTKTaskRunCounter()

        let widget = widgetFromOpaque(gtkRenderView(
            GTKParentRemountOnAppearProbeView(tick: tick, counter: counter)
        ))
        let window = presentGTKWidget(widget)
        defer {
            gtk_window_destroy(windowPointer(window))
            drainGTKMainContext(maxIterations: 100)
        }
        XCTAssertTrue(counter.waitForCount(1, timeout: 1.0),
                      "Initial child onAppear should run")

        for value in 1...5 {
            tick.storage.setValue(value)
            drainGTKMainContext(maxIterations: 100)
        }

        XCTAssertEqual(counter.value, 1,
                       "Child onAppear should not re-run when a parent full rebuild remounts the same state identity")
    }

    func testWindowRootStatefulDescendantKeepsIdentityInsideStatelessWrapper() throws {
        try requireGTK()

        let tick = State(wrappedValue: 0)
        let counter = GTKTaskRunCounter()

        let widget = widgetFromOpaque(gtkRenderWindowRootView(
            GTKStatelessRootProbeView {
                GTKParentRemountOnAppearProbeView(tick: tick, counter: counter)
            }
        ))
        let window = presentGTKWidget(widget)
        defer {
            gtk_window_destroy(windowPointer(window))
            drainGTKMainContext(maxIterations: 100)
        }
        XCTAssertTrue(counter.waitForCount(1, timeout: 1.0),
                      "Initial descendant onAppear should run")

        for value in 1...5 {
            tick.storage.setValue(value)
            drainGTKMainContext(maxIterations: 100)
        }

        XCTAssertEqual(
            counter.value,
            1,
            "A stateful descendant created inside a stateless window-root wrapper must keep the same identity on rebuild"
        )
    }

    func testWindowRootNestedTaskRunsOnceInsideStatelessWrapper() throws {
        try requireGTK()

        let tick = State(wrappedValue: 0)
        let counter = GTKTaskRunCounter()

        let widget = widgetFromOpaque(gtkRenderWindowRootView(
            GTKStatelessRootProbeView {
                GTKParentRemountTaskProbeView(tick: tick, counter: counter)
            }
        ))
        let window = presentGTKWidget(widget)
        defer {
            gtk_window_destroy(windowPointer(window))
            drainGTKMainContext(maxIterations: 100)
        }
        XCTAssertTrue(counter.waitForCount(1, timeout: 1.0),
                      "Initial descendant task should run")

        for value in 1...5 {
            tick.storage.setValue(value)
            drainGTKMainContext(maxIterations: 100)
        }
        Thread.sleep(forTimeInterval: 0.1)
        drainGTKMainContext(maxIterations: 100)

        XCTAssertEqual(
            counter.value,
            1,
            "A nested task must be owned by its stateful host and survive parent remounts"
        )
    }

    func testStatefulListRowOwnsNestedOnAppearLifecycle() throws {
        try requireGTK()

        let counter = GTKTaskRunCounter()
        let widget = widgetFromOpaque(gtkRenderView(
            List {
                GTKListRowOnAppearProbeView(counter: counter)
            }
        ))
        let window = presentGTKWidget(widget)
        defer {
            gtk_window_destroy(windowPointer(window))
            drainGTKMainContext(maxIterations: 100)
        }

        XCTAssertTrue(
            counter.waitForCount(1, timeout: 1.0),
            "A stateful list-row host must collect the onAppear declared in its own body"
        )
        drainGTKMainContext(maxIterations: 100)
        XCTAssertEqual(counter.value, 1)
    }

    func testOnAppearRunsAgainAfterConditionalReinsert() throws {
        try requireGTK()

        let show = State(wrappedValue: true)
        let counter = GTKTaskRunCounter()

        let widget = widgetFromOpaque(gtkRenderView(
            GTKConditionalOnAppearProbeView(show: show, counter: counter)
        ))
        let window = presentGTKWidget(widget)
        defer {
            gtk_window_destroy(windowPointer(window))
            drainGTKMainContext(maxIterations: 100)
        }
        XCTAssertTrue(counter.waitForCount(1, timeout: 1.0),
                      "Initial conditional onAppear should run")

        show.storage.setValue(false)
        drainGTKMainContext(maxIterations: 100)
        XCTAssertEqual(counter.value, 1,
                       "Removing the view should not fire onAppear")

        show.storage.setValue(true)
        drainGTKMainContext(maxIterations: 100)
        XCTAssertTrue(counter.waitForCount(2, timeout: 1.0),
                      "Reinserting the view should fire onAppear again")
    }

    func testOnAppearInsideCustomViewModifierRunsWhenMapped() throws {
        try requireGTK()

        let counter = GTKTaskRunCounter()

        let widget = widgetFromOpaque(gtkRenderView(
            Text("modified")
                .modifier(GTKOnAppearModifier(counter: counter))
        ))
        let window = presentGTKWidget(widget)
        defer {
            gtk_window_destroy(windowPointer(window))
            drainGTKMainContext(maxIterations: 100)
        }

        XCTAssertTrue(
            counter.waitForCount(1, timeout: 1.0),
            "onAppear emitted from a custom ViewModifier should run when the modified widget maps."
        )
    }

    func testOnAppearModifierObservableMutationRepaintsStyledDescendant() throws {
        try requireGTK()

        let theme = GTKThemeBootstrapModel()
        let widget = widgetFromOpaque(gtkRenderView(
            GTKThemeBootstrapProbeView(theme: State(wrappedValue: theme))
        ))
        let window = presentGTKWidget(widget)
        defer {
            gtk_window_destroy(windowPointer(window))
            drainGTKMainContext(maxIterations: 100)
        }

        drainGTKMainContext(maxIterations: 100)
        XCTAssertEqual(theme.tintColor, GTKThemeBootstrapModel.iceCubePurple)

        XCTAssertTrue(
            waitForGTKLabelMarkup(in: widget, timeout: 1.0) { markup in
                markup.contains("foreground=\"#BB3BE2\"")
            },
            "A custom onAppear modifier mutating a shared ObservableObject should repaint descendant foreground markup; final labels: \(gtkDebugLabelMarkups(in: widget))"
        )
    }

    func testCustomButtonStyleDescriptorChangesWhenCapturedStateChanges() throws {
        try requireGTK()

        let off = gtkDescribeView(
            Button("Toggle") {}
                .buttonStyle(GTKStatefulDescriptorButtonStyle(isOn: false, tintColor: .blue))
        )
        let on = gtkDescribeView(
            Button("Toggle") {}
                .buttonStyle(GTKStatefulDescriptorButtonStyle(isOn: true, tintColor: .blue))
        )

        XCTAssertNotEqual(off, on,
                          "Custom ButtonStyle captured state must invalidate the GTK descriptor so styled controls rebuild")
    }

    func testTapGestureRendersWithEnvironmentBinding() throws {
        try requireGTK()

        let model = GTKDelayedEnvModel()
        let widget = widgetFromOpaque(gtkRenderView(
            GTKDelayedEnvTapGestureView().environment(model)
        ))
        XCTAssertNotNil(widget,
                        "onTapGesture view with .environment(model) should render a widget")
    }

    func testTapGestureUsesTargetableWrapperAroundContent() throws {
        try requireGTK()

        let widget = widgetFromOpaque(gtkRenderView(
            Text("Tap").onTapGesture {}
        ))
        let child = try unwrapFirstChild(of: widget)

        XCTAssertEqual(gtkWidgetTypeName(widget), "GtkBox")
        XCTAssertEqual(gtk_widget_get_can_target(widget), 1)
        XCTAssertEqual(gtkWidgetTypeName(child), "GtkLabel")
    }

    func testLongPressGestureRendersWithEnvironmentBinding() throws {
        try requireGTK()

        let model = GTKDelayedEnvModel()
        let widget = widgetFromOpaque(gtkRenderView(
            GTKDelayedEnvLongPressView().environment(model)
        ))
        XCTAssertNotNil(widget,
                        "onLongPressGesture view with .environment(model) should render a widget")
    }

    func testDragGestureRendersWithEnvironmentBinding() throws {
        try requireGTK()

        let model = GTKDelayedEnvModel()
        let widget = widgetFromOpaque(gtkRenderView(
            GTKDelayedEnvDragView().environment(model)
        ))
        XCTAssertNotNil(widget,
                        "onDrag view with .environment(model) should render a widget")
    }

    func testDisclosureGroupRendersWithEnvironmentBinding() throws {
        try requireGTK()

        let model = GTKDelayedEnvModel()
        let widget = widgetFromOpaque(gtkRenderView(
            GTKDelayedEnvDisclosureGroupView().environment(model)
        ))
        XCTAssertNotNil(widget,
                        "DisclosureGroup with .environment(model) should render a widget")
    }

    func testMenuRendersWithEnvironmentBinding() throws {
        try requireGTK()

        let model = GTKDelayedEnvModel()
        let widget = widgetFromOpaque(gtkRenderView(
            GTKDelayedEnvMenuView().environment(model)
        ))
        XCTAssertNotNil(widget,
                        "Menu with .environment(model) should render a widget")
    }

    func testGeometryReaderDeferredRenderPreservesEnvironmentBinding() throws {
        try requireGTK()

        let model = GTKDelayedEnvModel()
        model.count = 7
        let wrapper = widgetFromOpaque(gtkRenderView(
            GeometryReader { _ in
                GTKDelayedEnvDescriptorTextView()
            }
            .environment(model)
        ))
        let window = presentGTKWidget(wrapper)
        defer {
            gtk_window_destroy(windowPointer(window))
            drainGTKMainContext(maxIterations: 100)
        }
        allocate(widget: wrapper, size: ViewSize(width: 240, height: 80))
        drainGTKMainContext(maxIterations: 100)

        var labels: [UnsafeMutablePointer<GtkWidget>] = []
        gtkCollectLabels(in: wrapper, into: &labels)
        XCTAssertTrue(
            labels.contains { label in
                String(cString: gtk_label_get_text(OpaquePointer(label))) == "count 7"
            },
            "Deferred GeometryReader content must render with its captured environment objects."
        )
    }

    // MARK: - Layout parity regressions

    func testVStackDefaultSpacingIsZero() throws {
        try requireGTK()

        let wrapper = widgetFromOpaque(gtkRenderView(
            VStack {
                Text("A")
                Text("B")
            }
        ))
        let wrapperSize = measuredSize(of: wrapper)
        allocate(widget: wrapper, size: wrapperSize)

        let first = try unwrapFirstChild(of: wrapper)
        let second = try unwrapNextSibling(of: first)
        let firstSize = allocatedSize(of: first)
        let secondOrigin = translatedChildOrigin(child: second, in: wrapper)

        XCTAssertEqual(
            secondOrigin.y,
            firstSize.height,
            accuracy: 0.01,
            "Default VStack spacing must collapse to 0 to match macOS SwiftUI for text siblings."
        )
    }

    func testFixedWidthFrameAroundColorStaysFixedInHStack() throws {
        try requireGTK()

        let wrapper = widgetFromOpaque(gtkRenderView(
            HStack {
                Color.red.frame(width: 50, height: 20)
                Text("End")
            }
        ))
        allocate(widget: wrapper, size: ViewSize(width: 400, height: 40))

        let first = try unwrapFirstChild(of: wrapper)
        let firstSize = allocatedSize(of: first)

        XCTAssertEqual(
            firstSize.width,
            50,
            accuracy: 0.01,
            "Color inside a fixed-width frame must not bleed hexpand into the HStack."
        )
    }

    func testFlexibleWidthFixedHeightResizableImageMeasuresToFrameHeight() throws {
        try requireGTK()

        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("screenshots/linux/showcase-LayoutStress.png")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: fixture.path),
            "Expected image fixture at \(fixture.path)."
        )

        let wrapper = widgetFromOpaque(gtkRenderView(
            Image(filePath: fixture.path)
                .resizable()
                .scaledToFill()
                .frame(height: 100)
                .frame(maxWidth: .infinity)
                .clipped()
        ))

        var heightMin: Int32 = 0
        var heightNat: Int32 = 0
        gtk_swift_widget_measure(wrapper, GTK_ORIENTATION_VERTICAL, 600, &heightMin, &heightNat)

        XCTAssertEqual(heightMin, 100, accuracy: 1)
        XCTAssertEqual(
            heightNat,
            100,
            accuracy: 1,
            "A fixed-height flexible-width image frame must not let the bitmap's natural height inflate List/Form rows."
        )
    }

    func testFrameMinHeightCenteringHelpersAreMarked() throws {
        try requireGTK()

        let wrapper = widgetFromOpaque(gtkRenderView(
            Text("Centered").frame(maxWidth: .infinity, minHeight: 120)
        ))
        let markerCount = gtkCountLayoutHelpers(in: wrapper)

        XCTAssertGreaterThan(
            markerCount,
            0,
            "FrameView vertical centering must mark its synthetic spacers so layout parity capture excludes them."
        )
    }

    func testDecoratedComposerTextFieldFillsAvailableWidth() throws {
        try requireGTK()

        let wrapper = widgetFromOpaque(gtkRenderView(
            HStack(spacing: 20) {
                ZStack(alignment: .trailing) {
                    TextField("Message", text: .constant(""))
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .clipped()
                        .padding(.trailing, 80)

                    HStack {
                        Text("mic")
                        Text("send")
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .overlay(
                RoundedRectangle(cornerRadius: 28)
                    .strokeBorder(Color.gray, style: StrokeStyle(lineWidth: 1))
            )
        ))

        gtk_widget_set_hexpand(wrapper, 1)
        gtk_widget_set_halign(wrapper, GTK_ALIGN_FILL)
        allocate(widget: wrapper, size: ViewSize(width: 1_200, height: 88))

        let entry = try unwrapFirstDescendant(ofType: "GtkEntry", in: wrapper)
        let entrySize = allocatedSize(of: entry)
        XCTAssertGreaterThan(
            entrySize.width,
            900,
            "A SwiftUI-style decorated chat composer must keep the text field wide after padding, clipping, and overlay wrappers."
        )
    }

    func testMiddleTruncationFrameRendersScrolledWindowWithSingleLabel() throws {
        try requireGTK()

        let wrapper = widgetFromOpaque(gtkRenderView(
            Text("/home/kyoshikawa/Documents/projects/sync/very/long/path")
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 100)
        ))
        let scrolled = try unwrapFirstDescendant(ofType: "GtkScrolledWindow", in: wrapper)

        var labels: [UnsafeMutablePointer<GtkWidget>] = []
        gtkCollectLabels(in: scrolled, into: &labels)

        XCTAssertEqual(
            labels.count,
            1,
            "Middle-truncated text clipped by a fixed-width frame must render a single label inside the scroll clip."
        )
    }

    // MARK: - LayoutStress regressions (2026-04-17)

    /// Two VStacks wrapped in `.frame(maxWidth: .infinity)` inside an HStack
    /// must split the available width evenly — the LayoutStress "dashboard
    /// cards" pattern.
    func testTwoInfinityFramesInHStackSplitWidthEvenly() throws {
        try requireGTK()

        let wrapper = widgetFromOpaque(gtkRenderView(
            HStack(spacing: 12) {
                Text("A")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)

                Text("B")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
        ))
        gtk_widget_set_halign(wrapper, GTK_ALIGN_FILL)
        gtk_widget_set_hexpand(wrapper, 1)
        allocate(widget: wrapper, size: ViewSize(width: 400, height: 80))

        let first = try unwrapFirstChild(of: wrapper)
        let second = try unwrapNextSibling(of: first)
        let firstSize = allocatedSize(of: first)
        let secondSize = allocatedSize(of: second)

        // Expected: (400 - 12 gap) / 2 ≈ 194 each.
        XCTAssertEqual(firstSize.width, 194, accuracy: 3,
                       "First card should take half the HStack width.")
        XCTAssertEqual(secondSize.width, 194, accuracy: 3,
                       "Second card should take half the HStack width.")
    }

    /// A fixed-width frame wrapping `HStack { Text; Spacer; Text }` must
    /// allocate both Text children's natural widths — the LayoutStress
    /// "sidebar item" pattern.
    func testFixedWidthFrameAllocatesBothTextsInInternalHStack() throws {
        try requireGTK()

        // Mirrors the LayoutStress sidebarItem layout: fixed-width outer
        // VStack containing an HStack { Text; Spacer; Text } wrapped in
        // padding + background.
        let wrapper = widgetFromOpaque(gtkRenderView(
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Inbox")
                    Spacer()
                    Text("12")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.clear)
            }
            .frame(width: 140)
        ))
        gtk_widget_set_halign(wrapper, GTK_ALIGN_FILL)
        gtk_widget_set_hexpand(wrapper, 1)
        allocate(widget: wrapper, size: ViewSize(width: 140, height: 40))

        // Walk descendants, collect Text labels (excluding Spacer-marked ones).
        var allLabels: [UnsafeMutablePointer<GtkWidget>] = []
        gtkCollectLabels(in: wrapper, into: &allLabels)
        let textLabels = allLabels.filter { w in
            let g = UnsafeMutableRawPointer(w).assumingMemoryBound(to: GObject.self)
            return g_object_get_data(g, gtkSwiftSpacerMarker) == nil
        }

        XCTAssertEqual(textLabels.count, 2,
                       "Both 'Inbox' and '12' labels must appear.")
        for label in textLabels {
            let size = allocatedSize(of: label)
            XCTAssertGreaterThan(size.width, 0,
                                 "Label must receive non-zero width inside a fixed-width HStack parent.")
        }
    }

    func testConversationBubbleLineLimitNilWinsSpaceBeforeTrailingSpacer() throws {
        try requireGTK()

        let message = "Conversation fixture: Alice sent a direct message that should render in a Linux Messages detail bubble."
        let wrapper = widgetFromOpaque(gtkRenderView(
            HStack(alignment: .bottom, spacing: 8) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(message)
                        .lineLimit(nil)
                        .padding(6)
                }
                .background(Color.gray)
                .cornerRadius(8)
                .padding(.trailing, 24)

                Spacer()
            }
            .frame(width: 520)
        ))

        gtk_widget_set_halign(wrapper, GTK_ALIGN_FILL)
        gtk_widget_set_hexpand(wrapper, 1)
        allocate(widget: wrapper, size: ViewSize(width: 520, height: 96))

        var labels: [UnsafeMutablePointer<GtkWidget>] = []
        gtkCollectLabels(in: wrapper, into: &labels)
        let messageLabel = try XCTUnwrap(labels.first { label in
            String(cString: gtk_label_get_text(OpaquePointer(label))) == message
        })
        let labelSize = allocatedSize(of: messageLabel)
        XCTAssertGreaterThan(
            labelSize.width,
            300,
            "A multiline message label before a trailing Spacer should receive the available bubble width instead of collapsing to a couple of characters."
        )
    }

    func testStatusActionRowKeepsLeadingActionsInsideAllocatedRow() throws {
        try requireGTK()

        let wrapper = widgetFromOpaque(gtkRenderView(
            VStack(alignment: .leading, spacing: 8) {
                Text("Here's to the #crazy ones. The misfits. The rebels. The troublemakers.")
                    .lineLimit(nil)
                HStack {
                    statusActionProbeButton("reply", count: "34")
                    statusActionProbeButton("boost", count: "10")
                    statusActionProbeButton("favorite", count: "8")
                    HStack {
                        statusActionProbeButton("share", count: nil)
                        Spacer()
                    }
                    Text("menu").padding(.vertical, 6).padding(.horizontal, 8)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        ))

        gtk_widget_set_hexpand(wrapper, 1)
        gtk_widget_set_halign(wrapper, GTK_ALIGN_FILL)
        allocate(widget: wrapper, size: ViewSize(width: 560, height: 130))

        var labels: [UnsafeMutablePointer<GtkWidget>] = []
        gtkCollectLabels(in: wrapper, into: &labels)
        guard let reply = labels.first(where: { label in
            String(cString: gtk_label_get_text(OpaquePointer(label))) == "reply"
        }) else {
            XCTFail("Expected action row to render the reply action.")
            return
        }

        let replyOrigin = translatedChildOrigin(child: reply, in: wrapper)
        XCTAssertLessThan(
            replyOrigin.x,
            48,
            "The first status action should stay at the leading edge, not collapse into a trailing action rail."
        )
    }

    func testOffsetStatusActionButtonsKeepVisualHitRegion() throws {
        try requireGTK()

        let wrapper = widgetFromOpaque(gtkRenderView(
            HStack {
                statusActionProbeButton("favorite", count: "8")
                Spacer()
            }
        ))

        gtk_widget_set_hexpand(wrapper, 1)
        gtk_widget_set_halign(wrapper, GTK_ALIGN_FILL)
        allocate(widget: wrapper, size: ViewSize(width: 240, height: 48))

        var buttons: [UnsafeMutablePointer<GtkWidget>] = []
        gtkCollectButtons(in: wrapper, into: &buttons)
        guard let button = buttons.first else {
            XCTFail("Expected the offset status action to render as a GtkButton.")
            return
        }

        let origin = translatedChildOrigin(child: button, in: wrapper)
        let size = allocatedSize(of: button)
        let visualX = origin.x - 4
        let visualY = origin.y + (size.height / 2)

        XCTAssertFalse(
            visualX >= origin.x && visualX < origin.x + size.width,
            "The test point must sit outside the logical GTK allocation."
        )
        XCTAssertTrue(
            gtkTestWidgetVisuallyContainsRootPoint(button, root: wrapper, x: visualX, y: visualY),
            "Offset buttons must keep their visible SwiftUI hit region, not only their untransformed GTK box."
        )
        XCTAssertTrue(
            gtkTestWidgetTreeContainsVisualButtonAtRootPoint(wrapper, root: wrapper, x: visualX, y: visualY),
            "List-row tap fallbacks must be able to identify offset button descendants and stand down."
        )
    }

    func testMenuButtonsCountAsActionableControlsForRowTapGuards() throws {
        try requireGTK()

        let menu = widgetFromOpaque(gtkRenderView(
            Menu("Actions") {
                MenuItem("Boost") {}
            }
        ))
        allocate(widget: menu, size: ViewSize(width: 96, height: 40))

        XCTAssertTrue(
            gtkTestWidgetTreeContainsVisualButtonAtRootPoint(menu, root: menu, x: 32, y: 20),
            "List-row tap fallbacks must treat GtkMenuButton descendants like normal buttons so row navigation does not steal menu clicks."
        )
    }

    func testNestedListButtonDoesNotAlsoActivateRow() throws {
        try requireGTK()

        var buttonActivations = 0
        var rowActivations: [Int] = []
        let wrapper = widgetFromOpaque(gtkRenderView(
            List {
                HStack {
                    Text("Status")
                    Button("Favorite") {
                        buttonActivations += 1
                    }
                }
                .onTapGesture {
                    rowActivations.append(1)
                }
                Text("Neighbor")
                    .onTapGesture {
                        rowActivations.append(2)
                    }
            }
        ))
        let window = presentGTKWidget(wrapper)
        defer {
            gtk_window_destroy(windowPointer(window))
            drainGTKMainContext(maxIterations: 100)
        }
        allocate(widget: wrapper, size: ViewSize(width: 320, height: 96))
        drainGTKMainContext(maxIterations: 100)

        let listBox = try unwrapFirstDescendant(ofType: "GtkListBox", in: wrapper)
        let row = try unwrapFirstDescendant(ofType: "GtkListBoxRow", in: listBox)
        let neighboringRow = try unwrapNextSibling(of: row)
        var buttons: [UnsafeMutablePointer<GtkWidget>] = []
        gtkCollectButtons(in: row, into: &buttons)
        let button = try XCTUnwrap(buttons.first)

        XCTAssertTrue(gtkTestActivateButton(button))
        gtkTestActivateListBoxRow(listBox: listBox, row: row)
        drainGTKMainContext(maxIterations: 100)

        XCTAssertEqual(buttonActivations, 1)
        XCTAssertEqual(
            rowActivations,
            [],
            "A nested Button activation must not fall through to the List row's navigation action."
        )

        gtkTestActivateListBoxRow(listBox: listBox, row: row)
        drainGTKMainContext(maxIterations: 100)
        XCTAssertEqual(
            rowActivations,
            [1],
            "Consuming a nested-control activation must not disable a later independent row activation."
        )

        Thread.sleep(forTimeInterval: 0.09)
        XCTAssertTrue(gtkTestActivateButton(button))
        gtkTestActivateListBoxRow(listBox: listBox, row: neighboringRow)
        drainGTKMainContext(maxIterations: 100)
        XCTAssertEqual(
            rowActivations,
            [1, 2],
            "A nested control in one row must never suppress immediate activation of a neighboring row."
        )
        XCTAssertEqual(buttonActivations, 2)
    }

    func testCustomStyledMenuButtonCanBeFoundByVisualHitRegion() throws {
        try requireGTK()

        let menu = widgetFromOpaque(gtkRenderView(
            Menu {
                MenuItem("Boost") {}
            } label: {
                HStack(spacing: 2) {
                    Text("boost")
                    Text("10")
                        .lineLimit(1)
                        .foregroundColor(Color.gray)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
            }
            .buttonStyle(GTKStatusActionProbeButtonStyle())
            .offset(x: -8)
        ))

        gtk_widget_set_halign(menu, GTK_ALIGN_START)
        allocate(widget: menu, size: ViewSize(width: 96, height: 40))

        let visualX = 4.0
        let visualY = 20.0
        let menuButton = gtkTestFindVisualMenuButtonAtRootPoint(menu, root: menu, x: visualX, y: visualY)

        XCTAssertNotNil(
            menuButton,
            "Custom-styled SwiftUI Menu labels must stay discoverable by visual hit region so status action menus can open instead of falling through to row navigation."
        )
        var labels: [UnsafeMutablePointer<GtkWidget>] = []
        gtkCollectLabels(in: menu, into: &labels)
        let boostLabel = labels.first {
            String(cString: gtk_label_get_text(OpaquePointer($0))) == "boost"
        }
        XCTAssertNotNil(boostLabel)
        if let boostLabel {
            let markup = String(cString: gtk_label_get_label(OpaquePointer(boostLabel)))
            XCTAssertNotEqual(gtk_label_get_use_markup(OpaquePointer(boostLabel)), 0)
            XCTAssertTrue(
                markup.contains("foreground=\"#878787\""),
                "Custom ButtonStyle foregroundColor should reach plain Text inside Menu labels; markup was \(markup)"
            )

            let owner = gtkTestMenuOwnerButton(for: boostLabel)
            XCTAssertNotNil(owner)
            if let owner {
                XCTAssertEqual(
                    UnsafeRawPointer(owner),
                    UnsafeRawPointer(menu),
                    "Rendered custom Menu label descendants should retain a semantic owner pointer to the GtkMenuButton."
                )
            }
        }
        XCTAssertTrue(
            gtkTestWidgetTreeContainsVisualButtonAtRootPoint(menu, root: menu, x: visualX, y: visualY),
            "A custom-styled Menu should also count as an actionable control for row tap guards."
        )
    }

    func testVisualMenuHitTestingSkipsInactiveNavigationPages() throws {
        try requireGTK()

        let root = gtk_overlay_new()!
        let inactivePage = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
        let activePage = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
        let inactiveMenu = widgetFromOpaque(gtkRenderView(
            Menu("Old actions") {
                MenuItem("Boost old status") {}
            }
        ))
        let activeMenu = widgetFromOpaque(gtkRenderView(
            Menu("Current actions") {
                MenuItem("Boost current status") {}
            }
        ))

        gtk_box_append(boxPointer(inactivePage), inactiveMenu)
        gtk_box_append(boxPointer(activePage), activeMenu)
        gtk_widget_set_hexpand(inactivePage, 1)
        gtk_widget_set_vexpand(inactivePage, 1)
        gtk_widget_set_hexpand(activePage, 1)
        gtk_widget_set_vexpand(activePage, 1)
        gtk_overlay_set_child(OpaquePointer(root), inactivePage)
        gtk_overlay_add_overlay(OpaquePointer(root), activePage)
        gtkTestSetNavigationPageInactive(inactivePage, true)
        allocate(widget: root, size: ViewSize(width: 160, height: 48))

        let hit = gtkTestPreferredVisualMenuButtonAtRootPoint(
            root: root,
            x: 48,
            y: 20
        )
        XCTAssertEqual(
            hit.map(UnsafeRawPointer.init),
            UnsafeRawPointer(activeMenu),
            "A hidden NavigationStack page must not steal a menu click from the visible destination."
        )

        gtk_widget_set_visible(activePage, 0)
        XCTAssertNil(
            gtkTestPreferredVisualMenuButtonAtRootPoint(root: root, x: 48, y: 20),
            "Inactive pages must not expose stale menus when no active menu occupies the point."
        )
        XCTAssertFalse(
            gtkTestWidgetTreeContainsVisualButtonAtRootPoint(root, root: root, x: 48, y: 20),
            "Inactive-page controls must not suppress row activation in the visible page."
        )
    }

    func testVisualMenuHitTestingPrefersPickedWidgetBranch() throws {
        try requireGTK()

        let root = gtk_overlay_new()!
        let staleBranch = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
        let pickedBranch = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
        let staleMenu = widgetFromOpaque(gtkRenderView(
            Menu("Stale actions") {
                MenuItem("Boost stale status") {}
            }
        ))
        let pickedMenu = widgetFromOpaque(gtkRenderView(
            Menu("Visible actions") {
                MenuItem("Boost visible status") {}
            }
        ))

        gtk_box_append(boxPointer(staleBranch), staleMenu)
        gtk_box_append(boxPointer(pickedBranch), pickedMenu)
        gtk_widget_set_hexpand(staleBranch, 1)
        gtk_widget_set_vexpand(staleBranch, 1)
        gtk_widget_set_hexpand(pickedBranch, 1)
        gtk_widget_set_vexpand(pickedBranch, 1)
        gtk_overlay_set_child(OpaquePointer(root), staleBranch)
        gtk_overlay_add_overlay(OpaquePointer(root), pickedBranch)
        allocate(widget: root, size: ViewSize(width: 160, height: 48))

        let hit = gtkTestRankedVisualMenuButtonAtRootPoint(
            searching: root,
            root: root,
            picked: pickedBranch,
            x: 48,
            y: 20
        )
        XCTAssertEqual(
            hit.map(UnsafeRawPointer.init),
            UnsafeRawPointer(pickedMenu),
            "Overlapping transformed controls must resolve to the menu nearest GTK's picked branch."
        )
    }

    func testCollapsedSplitListMenuControlUsesDetailFrameOrigin() throws {
        try requireGTK()

        let wrapper = widgetFromOpaque(gtkRenderView(
            HStack(spacing: 0) {
                Color.gray
                    .frame(width: 240)
                List {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Status row fixture")
                        Text("A split-view detail list keeps status actions near the detail frame leading edge.")
                            .lineLimit(nil)

                        HStack {
                            statusActionProbeButton("reply", count: "4")
                            Menu {
                                MenuItem("Boost") {}
                                MenuItem("Quote") {}
                            } label: {
                                HStack(spacing: 2) {
                                    Text("boost-menu")
                                    Text("8")
                                        .lineLimit(1)
                                        .foregroundColor(Color.gray)
                                }
                                .padding(.vertical, 6)
                                .padding(.horizontal, 8)
                            }
                            .buttonStyle(GTKStatusActionProbeButtonStyle())
                            .offset(x: -8)
                            statusActionProbeButton("favorite", count: "42")
                            statusActionProbeButton("share", count: nil)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: 560, height: 260)
            }
            .frame(width: 800, height: 260)
        ))

        let window = presentGTKWidget(wrapper)
        defer {
            gtkTestDismissActiveMenuOverlay()
            gtk_window_destroy(windowPointer(window))
            drainGTKMainContext(maxIterations: 100)
        }
        allocate(widget: wrapper, size: ViewSize(width: 800, height: 260))
        drainGTKMainContext(maxIterations: 100)

        var labels: [UnsafeMutablePointer<GtkWidget>] = []
        gtkCollectLabels(in: wrapper, into: &labels)
        let boostLabel = try XCTUnwrap(labels.first { label in
            String(cString: gtk_label_get_text(OpaquePointer(label))) == "boost-menu"
        })
        let origin = translatedChildOrigin(child: boostLabel, in: wrapper)
        let size = allocatedSize(of: boostLabel)
        let x = origin.x + (size.width / 2)
        let y = origin.y + (size.height / 2)

        XCTAssertGreaterThan(x, 240)
        XCTAssertLessThan(
            x,
            440,
            "The boost menu is in the detail column before the old double-counted desktop sidebar guard."
        )
        XCTAssertTrue(
            gtkTestActivateCollapsedListRowControlAtRootPoint(root: wrapper, x: x, y: y),
            "Collapsed split-list hit testing should open the custom Menu using the detail-frame origin, not skip it as leading chrome."
        )
    }

    func testRootPresentationMenuOverlayUsesStableFillLayer() throws {
        try requireGTK()

        let contentHost = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
        let window = gtk_window_new()!
        let rootContainer = gtkCreateRootPresentationContainer(
            winPtr: windowPointer(window),
            contentWidget: contentHost
        )
        gtk_window_set_child(windowPointer(window), rootContainer)
        gtk_window_present(windowPointer(window))
        defer {
            gtkTestDismissActiveMenuOverlay()
            gtk_window_destroy(windowPointer(window))
            drainGTKMainContext(maxIterations: 100)
        }
        drainGTKMainContext(maxIterations: 100)

        let wrapper = widgetFromOpaque(gtkRenderView(
            HStack(spacing: 0) {
                Color.gray
                    .frame(width: 240)
                List {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Status row fixture")
                        Text("Root-overlay menu panels must remain painted after the click schedules a host rebuild.")
                            .lineLimit(nil)

                        HStack {
                            statusActionProbeButton("reply", count: "4")
                            Menu {
                                MenuItem("Boost") {}
                                MenuItem("Quote") {}
                            } label: {
                                HStack(spacing: 2) {
                                    Text("boost-menu")
                                    Text("8")
                                        .lineLimit(1)
                                        .foregroundColor(Color.gray)
                                }
                                .padding(.vertical, 6)
                                .padding(.horizontal, 8)
                            }
                            .buttonStyle(GTKStatusActionProbeButtonStyle())
                            .offset(x: -8)
                            statusActionProbeButton("favorite", count: "42")
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: 560, height: 260)
            }
            .frame(width: 800, height: 260)
        ))

        gtk_box_append(boxPointer(contentHost), wrapper)
        allocate(widget: rootContainer, size: ViewSize(width: 800, height: 260))
        allocate(widget: wrapper, size: ViewSize(width: 800, height: 260))
        drainGTKMainContext(maxIterations: 100)

        var labels: [UnsafeMutablePointer<GtkWidget>] = []
        gtkCollectLabels(in: rootContainer, into: &labels)
        let boostLabel = try XCTUnwrap(labels.first { label in
            String(cString: gtk_label_get_text(OpaquePointer(label))) == "boost-menu"
        })
        let origin = translatedChildOrigin(child: boostLabel, in: wrapper)
        let size = allocatedSize(of: boostLabel)
        let x = origin.x + (size.width / 2)
        let y = origin.y + (size.height / 2)

        XCTAssertTrue(
            gtkTestActivateCollapsedListRowControlAtRootPoint(root: wrapper, x: x, y: y),
            "The status-row menu should open from the visual hit region inside a root presentation container."
        )
        drainGTKMainContext(maxIterations: 100)

        XCTAssertTrue(gtkTestHasActiveMenuOverlay())
        XCTAssertEqual(
            gtkTestActiveMenuOverlayLayerTypeName(),
            "GtkOverlay",
            "Root presentation menus should use a fill overlay layer so the positioned panel is allocated and repainted."
        )
        let overlayLabels = gtkLabelTexts(in: rootContainer)
        XCTAssertTrue(overlayLabels.contains("Boost"))
        XCTAssertTrue(overlayLabels.contains("Quote"))
    }

    func testRootPresentationMenuOverlayConvertsWindowPointsIntoContentCoordinates() throws {
        try requireGTK()

        var boostActivations = 0
        var quoteActivations = 0
        let contentHost = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
        let window = gtk_window_new()!
        let titlebar = gtk_header_bar_new()!
        gtk_widget_set_size_request(titlebar, -1, 48)
        gtk_window_set_titlebar(windowPointer(window), titlebar)
        let rootContainer = gtkCreateRootPresentationContainer(
            winPtr: windowPointer(window),
            contentWidget: contentHost
        )
        gtk_window_set_child(windowPointer(window), rootContainer)
        gtk_window_present(windowPointer(window))
        defer {
            gtkTestDismissActiveMenuOverlay()
            gtk_window_destroy(windowPointer(window))
            drainGTKMainContext(maxIterations: 100)
        }

        let menu = widgetFromOpaque(gtkRenderView(
            Menu {
                MenuItem("Boost") { boostActivations += 1 }
                MenuItem("Quote") { quoteActivations += 1 }
            } label: {
                Text("boost-menu")
            }
        ))
        gtk_box_append(boxPointer(contentHost), menu)
        allocate(widget: rootContainer, size: ViewSize(width: 420, height: 260))
        drainGTKMainContext(maxIterations: 100)

        XCTAssertTrue(gtkTestOpenMenuButton(menu))
        drainGTKMainContext(maxIterations: 100)
        let frame = try XCTUnwrap(gtkTestActiveMenuOverlayPanelFrameInRoot())
        let root = try XCTUnwrap(gtk_swift_widget_root_widget(menu))
        var menuX = 0.0
        var menuY = 0.0
        XCTAssertNotEqual(
            gtk_swift_widget_compute_point(menu, root, 0, 0, &menuX, &menuY),
            0
        )
        let menuSize = allocatedSize(of: menu)

        XCTAssertEqual(frame.x, menuX, accuracy: 2)
        XCTAssertEqual(
            frame.y,
            menuY + menuSize.height + 4,
            accuracy: 2,
            "A root-overlay menu anchor must be converted from window coordinates into the content overlay exactly once."
        )

        XCTAssertTrue(
            gtkTestActivateActiveMenuOverlayAtRootPoint(
                x: frame.x + (frame.width / 2),
                y: frame.y + 24
            )
        )
        XCTAssertEqual(boostActivations, 1)
        XCTAssertEqual(quoteActivations, 0)
    }

    func testCollapsedSplitListMenuControlUsesClickedListWhenMultipleListsAreMapped() throws {
        try requireGTK()

        var leftActivations = 0
        var rightActivations = 0

        func row(label: String, action: @escaping () -> Void) -> some View {
            VStack(alignment: .leading, spacing: 10) {
                Text("\(label) status row")
                Text("Multiple mapped lists must not leak cached action controls across columns.")
                    .lineLimit(nil)

                HStack {
                    statusActionProbeButton("reply", count: "4")
                    Button(action: action) {
                        HStack(spacing: 2) {
                            Text(label)
                            Text("8")
                                .lineLimit(1)
                                .foregroundColor(Color.gray)
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                    }
                    .buttonStyle(GTKStatusActionProbeButtonStyle())
                    .offset(x: -8)
                    statusActionProbeButton("favorite", count: "42")
                    statusActionProbeButton("share", count: nil)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }

        let wrapper = widgetFromOpaque(gtkRenderView(
            HStack(spacing: 0) {
                List {
                    row(label: "left-action") { leftActivations += 1 }
                }
                .frame(width: 240, height: 260)

                List {
                    row(label: "right-action") { rightActivations += 1 }
                }
                .frame(width: 560, height: 260)
            }
            .frame(width: 800, height: 260)
        ))

        let window = presentGTKWidget(wrapper)
        defer {
            gtkTestDismissActiveMenuOverlay()
            gtk_window_destroy(windowPointer(window))
            drainGTKMainContext(maxIterations: 100)
        }
        allocate(widget: wrapper, size: ViewSize(width: 800, height: 260))
        drainGTKMainContext(maxIterations: 100)

        var labels: [UnsafeMutablePointer<GtkWidget>] = []
        gtkCollectLabels(in: wrapper, into: &labels)
        let rightMenuLabel = try XCTUnwrap(labels.first { label in
            String(cString: gtk_label_get_text(OpaquePointer(label))) == "right-action"
        })
        let origin = translatedChildOrigin(child: rightMenuLabel, in: wrapper)
        let size = allocatedSize(of: rightMenuLabel)
        let x = origin.x + (size.width / 2)
        let y = origin.y + (size.height / 2)

        XCTAssertTrue(
            gtkTestActivateCollapsedListRowControlAtRootPoint(root: wrapper, x: x, y: y),
            "Collapsed split-list hit testing should activate the control in the clicked list."
        )
        drainGTKMainContext(maxIterations: 100)
        XCTAssertEqual(rightActivations, 1)
        XCTAssertEqual(leftActivations, 0)
    }

    func testCollapsedSplitListWideTextControlsUseNaturalHitWidth() throws {
        try requireGTK()

        var tagsActivations = 0

        let wrapper = widgetFromOpaque(gtkRenderView(
            HStack(spacing: 0) {
                Color.gray
                    .frame(width: 240)

                List {
                    HStack(spacing: 8) {
                        Button("News") {}
                        Button("Trending Posts") {}
                        Button("Suggested Users") {}
                        Button("Trending Tags") { tagsActivations += 1 }
                    }
                    .buttonStyle(.bordered)
                    .padding(16)
                }
                .frame(width: 560, height: 160)
            }
            .frame(width: 800, height: 160)
        ))

        let window = presentGTKWidget(wrapper)
        defer {
            gtk_window_destroy(windowPointer(window))
            drainGTKMainContext(maxIterations: 100)
        }
        allocate(widget: wrapper, size: ViewSize(width: 800, height: 160))
        drainGTKMainContext(maxIterations: 100)

        var labels: [UnsafeMutablePointer<GtkWidget>] = []
        gtkCollectLabels(in: wrapper, into: &labels)
        let tagsLabel = try XCTUnwrap(labels.first { label in
            String(cString: gtk_label_get_text(OpaquePointer(label))) == "Trending Tags"
        })
        let origin = translatedChildOrigin(child: tagsLabel, in: wrapper)
        let size = allocatedSize(of: tagsLabel)
        let x = origin.x + (size.width / 2)
        let y = origin.y + (size.height / 2)

        XCTAssertTrue(
            gtkTestActivateCollapsedListRowControlAtRootPoint(root: wrapper, x: x, y: y),
            "Collapsed split-list hit testing should use natural widths for wide text buttons such as IceCubes Explore quick-access controls."
        )
        drainGTKMainContext(maxIterations: 100)

        XCTAssertEqual(tagsActivations, 1)
    }

    func testHiddenButtonsDoNotBlockRowTapGuards() throws {
        try requireGTK()

        let wrapper = widgetFromOpaque(gtkRenderView(
            HStack {
                Button("Hidden") {}
                    .hidden()
                Spacer()
            }
        ))
        allocate(widget: wrapper, size: ViewSize(width: 96, height: 40))

        var buttons: [UnsafeMutablePointer<GtkWidget>] = []
        gtkCollectButtons(in: wrapper, into: &buttons)
        guard let button = buttons.first else {
            XCTFail("Expected hidden SwiftUI button to keep its GTK subtree for layout.")
            return
        }
        let origin = translatedChildOrigin(child: button, in: wrapper)
        let size = allocatedSize(of: button)
        let hitX = origin.x + (size.width / 2)
        let hitY = origin.y + (size.height / 2)

        XCTAssertFalse(
            gtkTestWidgetTreeContainsVisualButtonAtRootPoint(wrapper, root: wrapper, x: hitX, y: hitY),
            "Hidden or absent button branches must not prevent list-row fallback taps from reaching the row."
        )
    }

    func testNarrowMutationRefreshesReusedButtonAction() throws {
        try requireGTK()

        let selectedID = State(wrappedValue: 1001)
        let recorder = GTKButtonActionRecorder()
        let wrapper = widgetFromOpaque(gtkRenderView(
            GTKMutableButtonActionProbeView(selectedID: selectedID, recorder: recorder)
        ))
        let window = presentGTKWidget(wrapper)
        defer {
            gtk_window_destroy(windowPointer(window))
            drainGTKMainContext(maxIterations: 100)
        }
        allocate(widget: wrapper, size: ViewSize(width: 240, height: 80))
        drainGTKMainContext(maxIterations: 100)

        var buttons: [UnsafeMutablePointer<GtkWidget>] = []
        gtkCollectButtons(in: wrapper, into: &buttons)
        let button = try XCTUnwrap(buttons.first, "Expected the probe view to render a GtkButton.")
        selectedID.storage.setValue(1003)
        drainGTKMainContext(maxIterations: 100)

        XCTAssertTrue(gtkTestActivateButton(button))
        drainGTKMainContext(maxIterations: 100)

        XCTAssertEqual(
            recorder.values,
            [1003],
            "A reused GtkButton must fire the current model-bound Swift action, not the closure captured at first render."
        )
    }

    func testNarrowMutationRefreshesReusedMenuAction() throws {
        try requireGTK()

        let selectedID = State(wrappedValue: 1001)
        let recorder = GTKButtonActionRecorder()
        let wrapper = widgetFromOpaque(gtkRenderView(
            GTKMutableMenuActionProbeView(selectedID: selectedID, recorder: recorder)
        ))
        let window = presentGTKWidget(wrapper)
        defer {
            gtk_window_destroy(windowPointer(window))
            drainGTKMainContext(maxIterations: 100)
        }
        allocate(widget: wrapper, size: ViewSize(width: 240, height: 80))
        drainGTKMainContext(maxIterations: 100)

        var menuButtons: [UnsafeMutablePointer<GtkWidget>] = []
        gtkCollectMenuButtons(in: wrapper, into: &menuButtons)
        let menuButton = try XCTUnwrap(
            menuButtons.first,
            "Expected the probe view to render a GtkMenuButton."
        )
        selectedID.storage.setValue(1003)
        drainGTKMainContext(maxIterations: 100)

        XCTAssertTrue(gtkTestActivateMenuItem(menuButton, index: 0))

        XCTAssertEqual(
            recorder.values,
            [1003],
            "A reused GtkMenuButton must fire the current model-bound Swift action, not the closure captured at first render."
        )
    }

    func testRebuiltMenuActionRetainsSiblingScopedEnvironmentObject() throws {
        try requireGTK()

        let firstRevision = State(wrappedValue: 0)
        let secondRevision = State(wrappedValue: 0)
        let recorder = GTKButtonActionRecorder()
        let firstModel = GTKScopedEnvironmentMenuModel(id: 1003, recorder: recorder)
        let secondModel = GTKScopedEnvironmentMenuModel(id: 1001, recorder: recorder)
        let wrapper = widgetFromOpaque(gtkRenderView(
            VStack {
                GTKScopedEnvironmentMenuProbeView(revision: firstRevision)
                    .environment(firstModel)
                GTKScopedEnvironmentMenuProbeView(revision: secondRevision)
                    .environment(secondModel)
            }
        ))
        let window = presentGTKWidget(wrapper)
        defer {
            gtk_window_destroy(windowPointer(window))
            drainGTKMainContext(maxIterations: 100)
        }
        allocate(widget: wrapper, size: ViewSize(width: 240, height: 160))
        drainGTKMainContext(maxIterations: 100)

        firstRevision.storage.setValue(1)
        drainGTKMainContext(maxIterations: 100)

        var menuButtons: [UnsafeMutablePointer<GtkWidget>] = []
        gtkCollectMenuButtons(in: wrapper, into: &menuButtons)
        let firstMenuButton = try XCTUnwrap(
            menuButtons.first,
            "Expected the first scoped row to render a GtkMenuButton."
        )
        XCTAssertTrue(gtkTestActivateMenuItem(firstMenuButton, index: 0))

        XCTAssertEqual(
            recorder.values,
            [1003],
            "Rebuilding one row must not replace its environment object with a same-typed sibling controller."
        )
    }

    func testFormRowPrimaryActionTraversesViewBuilderChildren() throws {
        try requireGTK()

        let recorder = GTKButtonActionRecorder()
        let row = HStack {
            Text("Account")
            GTKStatefulFormRowButtonProbeView(recorder: recorder)
        }

        XCTAssertTrue(
            gtkTestActivatePrimaryTapAction(in: row),
            "A Form row must discover a Button nested behind ViewBuilder's transparent ViewList"
        )
        XCTAssertEqual(recorder.values, [42])
    }

    func testExplicitIdResetsStatefulSubviewIdentity() throws {
        try requireGTK()

        let selectedID = State(wrappedValue: 1001)
        let recorder = GTKButtonActionRecorder()
        let wrapper = widgetFromOpaque(gtkRenderView(
            GTKMutableIdentifiedStateProbeView(selectedID: selectedID, recorder: recorder)
        ))
        let window = presentGTKWidget(wrapper)
        defer {
            gtk_window_destroy(windowPointer(window))
            drainGTKMainContext(maxIterations: 100)
        }
        allocate(widget: wrapper, size: ViewSize(width: 240, height: 80))
        drainGTKMainContext(maxIterations: 100)

        selectedID.storage.setValue(1003)
        drainGTKMainContext(maxIterations: 100)

        var buttons: [UnsafeMutablePointer<GtkWidget>] = []
        gtkCollectButtons(in: wrapper, into: &buttons)
        let button = try XCTUnwrap(buttons.first, "Expected the identified probe view to render a GtkButton.")
        XCTAssertTrue(gtkTestActivateButton(button))
        drainGTKMainContext(maxIterations: 100)

        XCTAssertEqual(
            recorder.values,
            [1003],
            "A subtree wrapped in .id(newValue) must receive fresh @State storage instead of reusing the previous id's model."
        )
    }

    func testNavigationRootToolbarButtonCapturesDismissEnvironment() throws {
        try requireGTK()

        var dismissCount = 0
        let previousEnvironment = getCurrentEnvironment()
        var environment = previousEnvironment
        environment.dismiss = DismissAction {
            dismissCount += 1
        }
        setCurrentEnvironment(environment)
        let wrapper = widgetFromOpaque(gtkRenderView(GTKNavigationToolbarDismissProbeView()))
        setCurrentEnvironment(previousEnvironment)

        let wrapperObject = UnsafeMutableRawPointer(wrapper).assumingMemoryBound(to: GObject.self)
        let titlebarData = try XCTUnwrap(
            g_object_get_data(wrapperObject, "gtk-swift-window-titlebar"),
            "Expected NavigationStack to expose a GTK window titlebar."
        )
        let titlebar = titlebarData.assumingMemoryBound(to: GtkWidget.self)
        var buttons: [UnsafeMutablePointer<GtkWidget>] = []
        gtkCollectButtons(in: titlebar, into: &buttons)
        XCTAssertFalse(buttons.isEmpty, "Expected NavigationStack toolbar to render at least one GtkButton.")

        for button in buttons where dismissCount == 0 {
            guard gtkTestActivateButton(button) else { continue }
            drainGTKMainContext(maxIterations: 100)
        }

        XCTAssertEqual(
            dismissCount,
            1,
            "Root toolbar button actions must capture the active dismiss environment for deferred GTK callbacks."
        )
    }

    func testDestroyedNavigationContextIgnoresDeferredToolbarRefresh() throws {
        try requireGTK()

        let parent = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
        let stack = widgetFromOpaque(gtkRenderView(
            NavigationStack {
                Text("Root")
                    .navigationTitle("Before")
            }
        ))
        gtk_box_append(boxPointer(parent), stack)
        let window = presentGTKWidget(parent)
        defer {
            gtk_window_destroy(windowPointer(window))
            drainGTKMainContext(maxIterations: 100)
        }
        let context = try XCTUnwrap(gtkTestNavigationContext(in: stack))

        XCTAssertTrue(context.nativeWidgetTreeIsAlive)
        gtk_box_remove(boxPointer(parent), stack)
        drainGTKMainContext(maxIterations: 100)

        XCTAssertFalse(context.nativeWidgetTreeIsAlive)
        context.replaceCurrentToolbar(
            with: GTKNavigationToolbarSnapshot(
                title: "After",
                toolbarItems: [],
                hidden: false
            )
        )
        XCTAssertTrue(context.entries.isEmpty)

        let previousContext = getCurrentNavigationContext()
        setCurrentNavigationContext(context)
        XCTAssertFalse(
            getCurrentNavigationContext() === context,
            "Captured environments must not return a navigation context after its native stack is destroyed."
        )
        setCurrentNavigationContext(previousContext)
    }

    func testItemSheetRootOverlayDismissRemovesPresentedLayer() throws {
        try requireGTK()

        let contentHost = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
        let window = gtk_window_new()!
        let rootContainer = gtkCreateRootPresentationContainer(
            winPtr: windowPointer(window),
            contentWidget: contentHost
        )
        gtk_window_set_child(windowPointer(window), rootContainer)
        gtk_window_present(windowPointer(window))
        defer {
            gtk_window_destroy(windowPointer(window))
            drainGTKMainContext(maxIterations: 100)
        }
        drainGTKMainContext(maxIterations: 100)

        var onDismissCount = 0
        let wrapper = widgetFromOpaque(gtkRenderView(
            GTKItemSheetRootOverlayDismissProbeView {
                onDismissCount += 1
            }
        ))
        gtk_box_append(boxPointer(contentHost), wrapper)
        drainGTKMainContext(maxIterations: 100)

        XCTAssertTrue(
            gtkLabelTexts(in: rootContainer).contains("Sheet Content"),
            "The item sheet should render into the root presentation overlay."
        )

        var buttons: [UnsafeMutablePointer<GtkWidget>] = []
        gtkCollectButtons(in: rootContainer, into: &buttons)
        let dismissButton = try XCTUnwrap(
            buttons.first,
            "Expected a dismiss button inside the root-overlay sheet."
        )
        XCTAssertTrue(gtkTestActivateButton(dismissButton))
        drainGTKMainContext(maxIterations: 100)

        XCTAssertEqual(onDismissCount, 1)
        XCTAssertFalse(
            gtkLabelTexts(in: rootContainer).contains("Sheet Content"),
            "A programmatic sheet dismiss must unparent the root-overlay layer without waiting for a parent rebuild."
        )
    }

    func testItemSheetRootOverlayDismissAfterAwaitRemovesPresentedLayer() async throws {
        try requireGTK()

        let contentHost = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
        let window = gtk_window_new()!
        let rootContainer = gtkCreateRootPresentationContainer(
            winPtr: windowPointer(window),
            contentWidget: contentHost
        )
        gtk_window_set_child(windowPointer(window), rootContainer)
        gtk_window_present(windowPointer(window))
        defer {
            gtk_window_destroy(windowPointer(window))
            drainGTKMainContext(maxIterations: 100)
        }
        drainGTKMainContext(maxIterations: 100)

        var onDismissCount = 0
        let wrapper = widgetFromOpaque(gtkRenderView(
            GTKItemSheetRootOverlayDismissProbeView(dismissAfterYield: true) {
                onDismissCount += 1
            }
        ))
        gtk_box_append(boxPointer(contentHost), wrapper)
        drainGTKMainContext(maxIterations: 100)

        var buttons: [UnsafeMutablePointer<GtkWidget>] = []
        gtkCollectButtons(in: rootContainer, into: &buttons)
        let dismissButton = try XCTUnwrap(
            buttons.first,
            "Expected a dismiss button inside the asynchronous root-overlay sheet."
        )
        XCTAssertTrue(gtkTestActivateButton(dismissButton))

        for _ in 0..<100 where onDismissCount == 0 {
            await Task.yield()
            drainGTKMainContext(maxIterations: 10)
        }

        XCTAssertEqual(onDismissCount, 1)
        XCTAssertFalse(
            gtkLabelTexts(in: rootContainer).contains("Sheet Content"),
            "A sheet-scoped dismiss action must survive an awaited task."
        )
    }

    func testRootOverlaySheetNavigationStackUsesInlineSheetChrome() throws {
        try requireGTK()

        let contentHost = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
        let window = gtk_window_new()!
        let rootContainer = gtkCreateRootPresentationContainer(
            winPtr: windowPointer(window),
            contentWidget: contentHost
        )
        gtk_window_set_child(windowPointer(window), rootContainer)
        gtk_window_present(windowPointer(window))
        defer {
            gtk_window_destroy(windowPointer(window))
            drainGTKMainContext(maxIterations: 100)
        }
        drainGTKMainContext(maxIterations: 100)

        let wrapper = widgetFromOpaque(gtkRenderView(GTKSheetNavigationChromeProbeView()))
        gtk_box_append(boxPointer(contentHost), wrapper)
        drainGTKMainContext(maxIterations: 100)

        let labels = gtkLabelTexts(in: rootContainer)
        XCTAssertTrue(
            labels.contains("Sheet Title"),
            "A NavigationStack inside a sheet should render an inline sheet title, got: \(labels)"
        )
        XCTAssertTrue(
            labels.contains("Cancel"),
            "A NavigationStack inside a sheet should render leading toolbar items inline, got: \(labels)"
        )
        XCTAssertTrue(
            labels.contains("Sheet Body"),
            "Sheet body content should remain visible with inline navigation chrome, got: \(labels)"
        )
    }

    func testWindowRootHostInstallsAppStateForCapturedSheetBindings() throws {
        try requireGTK()

        let appState = GTKWindowRootAppStateProbe()
        let model = appState.model
        let storage = try XCTUnwrap(
            Mirror(reflecting: appState).children
                .compactMap { $0.value as? AnyStateStorageProvider }
                .first?.anyStorage as? StateStorage<GTKWindowRootObservableProbe>
        )

        XCTAssertNil(storage.host)

        let widget = widgetFromOpaque(gtkRenderWindowRootView(
            Text("Base").sheet(item: appState.$model.item) { item in
                Text(item.name)
            },
            appStateSource: appState
        ))
        defer {
            if gtk_widget_get_parent(widget) != nil {
                gtk_widget_unparent(widget)
            }
        }

        XCTAssertNotNil(
            storage.host,
            "WindowGroup root rendering must install @State stored on the owning App so captured app-level bindings can invalidate the sheet host."
        )

        let generation = storage.generation
        model.item = GTKWindowRootSheetItem(id: 42, name: "Media")

        XCTAssertGreaterThan(
            storage.generation,
            generation,
            "Mutating an app-level @Observable stored in @State should publish through the root window host storage."
        )
    }

    func testWindowRootReevaluatesContentProviderAfterAppObservableMutation() throws {
        try requireGTK()

        let appState = GTKWindowRootEnvironmentAppStateProbe()
        let manager = appState.manager
        let makeContent = {
            GTKWindowRootEnvironmentReaderProbe()
                .environment(manager.client)
        }
        let widget = widgetFromOpaque(gtkRenderWindowRootView(
            makeContent(),
            appStateSource: appState,
            contentProvider: makeContent
        ))
        let window = presentGTKWidget(widget)
        defer {
            gtk_window_destroy(windowPointer(window))
            drainGTKMainContext(maxIterations: 100)
        }

        XCTAssertTrue(gtkLabelTexts(in: widget).contains("client signed-out"))

        manager.client = GTKWindowRootClientProbe(name: "signed-in")
        drainGTKMainContext(maxIterations: 300)

        let labels = gtkLabelTexts(in: widget)
        XCTAssertTrue(
            labels.contains("client signed-in"),
            "A WindowGroup root rebuild must reevaluate its builder and inject the replacement object; labels: \(labels)"
        )
        XCTAssertFalse(labels.contains("client signed-out"))
    }

    func testItemSheetRootOverlayProgrammaticDismissBypassesDismissalInterception() throws {
        try requireGTK()

        let contentHost = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
        let window = gtk_window_new()!
        let rootContainer = gtkCreateRootPresentationContainer(
            winPtr: windowPointer(window),
            contentWidget: contentHost
        )
        gtk_window_set_child(windowPointer(window), rootContainer)
        gtk_window_present(windowPointer(window))
        defer {
            gtk_window_destroy(windowPointer(window))
            drainGTKMainContext(maxIterations: 100)
        }
        drainGTKMainContext(maxIterations: 100)

        var shouldConfirm = false
        var onDismissCount = 0
        let shouldConfirmBinding = Binding(
            get: { shouldConfirm },
            set: { shouldConfirm = $0 }
        )
        let wrapper = widgetFromOpaque(gtkRenderView(
            GTKItemSheetRootOverlayInterceptedDismissProbeView(
                shouldConfirm: shouldConfirmBinding
            ) {
                onDismissCount += 1
            }
        ))
        gtk_box_append(boxPointer(contentHost), wrapper)
        drainGTKMainContext(maxIterations: 100)

        XCTAssertTrue(gtkLabelTexts(in: rootContainer).contains("Guarded Sheet Content"))

        var buttons: [UnsafeMutablePointer<GtkWidget>] = []
        gtkCollectButtons(in: rootContainer, into: &buttons)
        let dismissButton = try XCTUnwrap(buttons.first)
        XCTAssertTrue(gtkTestActivateButton(dismissButton))
        drainGTKMainContext(maxIterations: 100)

        XCTAssertFalse(
            shouldConfirm,
            "Programmatic dismiss() should not trigger interactive-dismiss confirmation metadata."
        )
        XCTAssertEqual(onDismissCount, 1)
        XCTAssertFalse(gtkLabelTexts(in: rootContainer).contains("Guarded Sheet Content"))
    }

    func testListStatusLikeRowGrowsBeyondFallbackHeight() throws {
        try requireGTK()

        let wrapper = widgetFromOpaque(gtkRenderView(
            List {
                VStack(alignment: .leading, spacing: 10) {
                    Text("""
                    Here's to the crazy ones. The misfits. The rebels. The troublemakers. The round pegs in the square holes.
                    They are long enough to wrap in a timeline cell and force the row to resolve height from its allocated width.
                    """)
                    .lineLimit(nil)

                    HStack {
                        statusActionProbeButton("reply", count: "34")
                        statusActionProbeButton("boost", count: "10")
                        statusActionProbeButton("favorite", count: "8")
                        HStack {
                            statusActionProbeButton("share", count: nil)
                            Spacer()
                        }
                        Text("menu").padding(.vertical, 6).padding(.horizontal, 8)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 560, height: 260)
        ))

        gtk_widget_set_hexpand(wrapper, 1)
        gtk_widget_set_halign(wrapper, GTK_ALIGN_FILL)
        let window = presentGTKWidget(wrapper)
        defer {
            gtk_window_destroy(windowPointer(window))
            drainGTKMainContext(maxIterations: 100)
        }
        allocate(widget: wrapper, size: ViewSize(width: 560, height: 260))
        drainGTKMainContext(maxIterations: 100)

        let row = try unwrapFirstDescendant(ofType: "GtkListBoxRow", in: wrapper)
        let rowSize = allocatedSize(of: row)
        XCTAssertGreaterThan(
            rowSize.height,
            112,
            "Status-like List rows must grow beyond the complex-row fallback instead of clipping resolved content."
        )

        var labels: [UnsafeMutablePointer<GtkWidget>] = []
        gtkCollectLabels(in: row, into: &labels)
        let reply = try XCTUnwrap(labels.first { label in
            String(cString: gtk_label_get_text(OpaquePointer(label))) == "reply"
        })
        let replyOrigin = translatedChildOrigin(child: reply, in: row)
        XCTAssertLessThan(
            replyOrigin.x,
            64,
            "The first action in a status-like List row should remain at the leading edge."
        )
        XCTAssertLessThanOrEqual(
            replyOrigin.y + allocatedSize(of: reply).height,
            rowSize.height,
            "The row allocation must include the action row instead of clipping it into a trailing rail."
        )
    }

    func testStatefulStatusLikeRowsKeepActionsLeadingInList() throws {
        try requireGTK()

        let wrapper = widgetFromOpaque(gtkRenderView(
            List {
                StatefulGTKStatusRowProbe(index: 1)
                StatefulGTKStatusRowProbe(index: 2)
                StatefulGTKStatusRowProbe(index: 3)
            }
            .frame(width: 560, height: 390)
        ))

        gtk_widget_set_hexpand(wrapper, 1)
        gtk_widget_set_halign(wrapper, GTK_ALIGN_FILL)
        let window = presentGTKWidget(wrapper)
        defer {
            gtk_window_destroy(windowPointer(window))
            drainGTKMainContext(maxIterations: 100)
        }
        allocate(widget: wrapper, size: ViewSize(width: 560, height: 390))
        drainGTKMainContext(maxIterations: 100)

        var labels: [UnsafeMutablePointer<GtkWidget>] = []
        gtkCollectLabels(in: wrapper, into: &labels)
        let replyLabels = labels.filter { label in
            String(cString: gtk_label_get_text(OpaquePointer(label))).hasPrefix("reply-")
        }
        XCTAssertEqual(
            replyLabels.count,
            3,
            "Each stateful timeline row should render its leading reply action."
        )

        for reply in replyLabels {
            let origin = translatedChildOrigin(child: reply, in: wrapper)
            if ProcessInfo.processInfo.environment["QUILLUI_GTK_DEBUG_TEST_TREE"] == "1" {
                gtkDebugWidgetAncestors(reply, in: wrapper)
            }
            XCTAssertLessThan(
                origin.x,
                100,
                "Stateful status action rows should stay near the row's leading content edge, not collapse into a trailing rail."
            )
        }
    }

    func testForEachNestedStatefulStatusRowsResolveListRowHeight() throws {
        try requireGTK()

        let wrapper = widgetFromOpaque(gtkRenderView(
            List {
                ForEach([1, 2, 3], id: \.self) { index in
                    ExternalStatefulGTKStatusRowProbe(index: index)
                        .listRowInsets(.init(top: 0, leading: 16, bottom: 0, trailing: 16))
                }
            }
            .frame(width: 560, height: 390)
        ))

        gtk_widget_set_hexpand(wrapper, 1)
        gtk_widget_set_halign(wrapper, GTK_ALIGN_FILL)
        let window = presentGTKWidget(wrapper)
        defer {
            gtk_window_destroy(windowPointer(window))
            drainGTKMainContext(maxIterations: 100)
        }
        allocate(widget: wrapper, size: ViewSize(width: 560, height: 390))
        drainGTKMainContext(maxIterations: 100)

        let row = try unwrapFirstDescendant(ofType: "GtkListBoxRow", in: wrapper)
        let rowSize = allocatedSize(of: row)
        XCTAssertGreaterThan(
            rowSize.height,
            112,
            "Nested stateful rows from ForEach must resolve beyond the complex-row fallback height."
        )

        var labels: [UnsafeMutablePointer<GtkWidget>] = []
        gtkCollectLabels(in: row, into: &labels)
        let reply = try XCTUnwrap(labels.first { label in
            String(cString: gtk_label_get_text(OpaquePointer(label))) == "reply-1"
        })
        let replyOrigin = translatedChildOrigin(child: reply, in: row)
        XCTAssertLessThanOrEqual(
            replyOrigin.y + allocatedSize(of: reply).height,
            rowSize.height,
            "Resolved nested status row height must include the action row."
        )
    }

    /// NavigationSplitView sidebars must behave like fixed SwiftUI columns:
    /// long line-limited labels truncate inside the column instead of making
    /// the sidebar wider than its declared column width.
    func testNavigationSplitSidebarClipsLongLineLimitedTextToColumnWidth() throws {
        try requireGTK()

        let longTitle = String(repeating: "Auto-config test reply with one short phrase ", count: 8)
        let wrapper = widgetFromOpaque(gtkRenderView(
            NavigationSplitView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text(longTitle)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .navigationSplitViewColumnWidth(320)
            } detail: {
                Text("Detail")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        ))
        gtkConfigureRootContentToFillWindow(wrapper)
        allocate(widget: wrapper, size: ViewSize(width: 1000, height: 600))

        let sidebar = try unwrapFirstChild(of: wrapper)
        let divider = try unwrapNextSibling(of: sidebar)
        let detail = try unwrapNextSibling(of: divider)
        let sidebarSize = allocatedSize(of: sidebar)
        let detailSize = allocatedSize(of: detail)

        XCTAssertEqual(
            sidebarSize.width,
            320,
            accuracy: 4,
            "The fixed sidebar column should not expand to the long Text natural width."
        )
        XCTAssertGreaterThan(
            detailSize.width,
            600,
            "The detail pane should receive the remaining split-view width."
        )
    }

    /// A ZStack with `.frame(width: 120, height: 100)` must report exactly
    /// that allocated size — the LayoutStress "nested alignment" pattern.
    func testZStackWithFixedFrameReportsRequestedSize() throws {
        try requireGTK()

        let wrapper = widgetFromOpaque(gtkRenderView(
            ZStack {
                Color.red
                Text("TL")
                    .frame(width: 80, height: 60, alignment: .bottomTrailing)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(width: 120, height: 100)
        ))
        let wrapperSize = measuredSize(of: wrapper)
        allocate(widget: wrapper, size: wrapperSize)

        XCTAssertEqual(wrapperSize.width, 120, accuracy: 1,
                       "ZStack frame(width: 120) must measure 120 wide.")
        XCTAssertEqual(wrapperSize.height, 100, accuracy: 1,
                       "ZStack frame(height: 100) must measure 100 tall.")
    }

    /// Settings-row pattern: `HStack { Text; Spacer; Text }` inside a
    /// `VStack(alignment: .leading)` with a Color background. The trailing
    /// Text (value) must be pushed to the right edge of the allocated width,
    /// not left-clustered with the label.
    func testSettingsRowSpacerPushesValueToRightEdge() throws {
        try requireGTK()

        // Reproduce the exact LayoutStress SettingsSection: section header,
        // multiple rows with divider siblings, all under a ScrollView-
        // wrapped VStack(.leading, spacing: 16), which itself is under a
        // top-level VStack(spacing: 0) with a title bar.
        let wrapper = widgetFromOpaque(gtkRenderView(
            VStack(spacing: 0) {
                Text("Layout Stress Test")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color(red: 0.1, green: 0.1, blue: 0.1))

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("1. Settings Rows").padding(.horizontal, 16)

                        VStack(alignment: .leading, spacing: 0) {
                            Text("GENERAL")
                                .font(.caption)
                                .foregroundColor(.gray)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                            HStack {
                                Text("Username")
                                    .foregroundColor(.white)
                                Spacer()
                                Text("kaz.yoshikawa")
                                    .foregroundColor(.gray)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            Color.gray.frame(height: 0.5).padding(.leading, 16)
                            HStack {
                                Text("Email")
                                    .foregroundColor(.white)
                                Spacer()
                                Text("kaz@example.com")
                                    .foregroundColor(.gray)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                        }
                        .background(Color(red: 0.15, green: 0.15, blue: 0.15))
                    }
                    .padding(.vertical, 16)
                }
            }
            .background(Color.black)
        ))
        // Use the backend's own helper so we match the real window bring-up.
        gtkConfigureRootContentToFillWindow(wrapper)
        allocate(widget: wrapper, size: ViewSize(width: 700, height: 600))

        var allLabels: [UnsafeMutablePointer<GtkWidget>] = []
        gtkCollectLabels(in: wrapper, into: &allLabels)
        let textLabels = allLabels.filter { w in
            let g = UnsafeMutableRawPointer(w).assumingMemoryBound(to: GObject.self)
            return g_object_get_data(g, gtkSwiftSpacerMarker) == nil
        }

        // Dump every non-Spacer label with its position to see what's happening.
        for label in textLabels {
            let ptr = gtk_label_get_text(OpaquePointer(label))
            let text = ptr.map { String(cString: $0) } ?? "?"
            let origin = translatedChildOrigin(child: label, in: wrapper)
            let size = allocatedSize(of: label)
            fputs("DBG label '\(text)' at x=\(origin.x) w=\(size.width) right=\(origin.x + size.width)\n", stderr)
        }

        guard let valueLabel = textLabels.first(where: { w in
            let ptr = gtk_label_get_text(OpaquePointer(w))
            return ptr.map { String(cString: $0) } == "kaz.yoshikawa"
        }) else {
            XCTFail("Could not locate kaz.yoshikawa label")
            return
        }

        let valueOrigin = translatedChildOrigin(child: valueLabel, in: wrapper)
        let valueSize = allocatedSize(of: valueLabel)
        let valueRightEdge = valueOrigin.x + valueSize.width

        // Inner right edge = 700 (allocated) - 16 (row padding) = 684.
        XCTAssertGreaterThan(
            valueRightEdge,
            670,
            "Spacer must push the value to the right padding edge (~684), got right edge at \(valueRightEdge)."
        )
    }

    func testVerticalScrollViewLeavesFixedFooterVisibleInVStack() throws {
        try requireGTK()

        let wrapper = widgetFromOpaque(gtkRenderView(
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(0..<40) { index in
                            Text("History item \(index)")
                                .font(.system(size: 16))
                                .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()

                Divider()

                VStack(alignment: .leading, spacing: 18) {
                    Text("Completions")
                    Text("Shortcuts")
                    Text("Settings")
                }
                .frame(height: 146)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .clipped()
            }
        ))
        gtkConfigureRootContentToFillWindow(wrapper)
        allocate(widget: wrapper, size: ViewSize(width: 320, height: 600))

        var labels: [UnsafeMutablePointer<GtkWidget>] = []
        gtkCollectLabels(in: wrapper, into: &labels)
        let settingsLabel = try XCTUnwrap(labels.first { label in
            String(cString: gtk_label_get_text(OpaquePointer(label))) == "Settings"
        })
        let settingsOrigin = translatedChildOrigin(child: settingsLabel, in: wrapper)
        let settingsSize = allocatedSize(of: settingsLabel)

        XCTAssertLessThanOrEqual(
            settingsOrigin.y + settingsSize.height,
            600,
            "A vertical ScrollView above fixed footer navigation must shrink to the remaining stack height."
        )
        XCTAssertGreaterThan(
            settingsOrigin.y,
            430,
            "Footer navigation should remain pinned near the lower sidebar edge, not inline with scroll content."
        )
    }

    /// A `.frame(height: 0.5)` (sub-pixel divider) must request at least
    /// 1 device-pixel of height. Truncating via `gint()` collapses 0.5 to 0
    /// and makes the divider invisible.
    func testSubPixelHeightFrameRendersAtLeastOnePixel() throws {
        try requireGTK()

        let wrapper = widgetFromOpaque(gtkRenderView(
            Color.gray.frame(height: 0.5)
        ))

        var widthMin: Int32 = 0; var widthNat: Int32 = 0
        var heightMin: Int32 = 0; var heightNat: Int32 = 0
        gtk_swift_widget_measure(wrapper, GTK_ORIENTATION_HORIZONTAL, -1, &widthMin, &widthNat)
        gtk_swift_widget_measure(wrapper, GTK_ORIENTATION_VERTICAL, -1, &heightMin, &heightNat)

        XCTAssertGreaterThanOrEqual(
            heightMin,
            1,
            "A 0.5pt divider's minimum height must be at least 1 device pixel, got \(heightMin)."
        )
        XCTAssertGreaterThanOrEqual(
            heightNat,
            1,
            "A 0.5pt divider's natural height must be at least 1 device pixel, got \(heightNat)."
        )
    }

    /// Three ZStacks with identical `.frame(width: 120, height: 100)` placed
    /// in an HStack must all allocate the same 120×100 size — the
    /// LayoutStress "nested alignment stress" pattern. The middle box uses
    /// a VStack with different-width children, which previously caused its
    /// ZStack to measure narrower than its siblings.
    func testThreeFramedZStacksInHStackAllReportSameSize() throws {
        try requireGTK()

        let wrapper = widgetFromOpaque(gtkRenderView(
            HStack(spacing: 12) {
                ZStack {
                    Color.red
                    Text("TL")
                }
                .frame(width: 120, height: 100)

                ZStack {
                    Color.green
                    VStack(alignment: .leading, spacing: 4) {
                        Text("A")
                        Text("BB")
                        Text("CCC")
                    }
                }
                .frame(width: 120, height: 100)

                ZStack {
                    Color.blue
                    Text("BR")
                }
                .frame(width: 120, height: 100)
            }
        ))
        gtk_widget_set_halign(wrapper, GTK_ALIGN_START)
        allocate(widget: wrapper, size: ViewSize(width: 400, height: 100))

        let first = try unwrapFirstChild(of: wrapper)
        let second = try unwrapNextSibling(of: first)
        let third = try unwrapNextSibling(of: second)

        let firstSize = allocatedSize(of: first)
        let secondSize = allocatedSize(of: second)
        let thirdSize = allocatedSize(of: third)

        XCTAssertEqual(firstSize.width, 120, accuracy: 1,
                       "Red ZStack must be 120 wide.")
        XCTAssertEqual(secondSize.width, 120, accuracy: 1,
                       "Green ZStack must be 120 wide.")
        XCTAssertEqual(thirdSize.width, 120, accuracy: 1,
                       "Blue ZStack must be 120 wide.")
        XCTAssertEqual(firstSize.height, 100, accuracy: 1,
                       "Red ZStack must be 100 tall.")
        XCTAssertEqual(secondSize.height, 100, accuracy: 1,
                       "Green ZStack must be 100 tall.")
        XCTAssertEqual(thirdSize.height, 100, accuracy: 1,
                       "Blue ZStack must be 100 tall.")
    }
}

// MARK: - Deferred callback environment test fixtures

private final class GTKDelayedEnvModel {
    var count: Int = 0
}

@MainActor
private final class GTKMainActorDeinitProbe {
    let payload = NSObject()
}

private final class GTKThemeBootstrapModel: SwiftOpenUI.ObservableObject {
    static let iceCubePurple = Color(red: 187 / 255, green: 59 / 255, blue: 226 / 255)

    @SwiftOpenUI.Published var tintColor: Color = .black
}

private final class GTKTaskRunCounter: @unchecked Sendable {
    private let condition = NSCondition()
    private var count = 0

    func increment() {
        condition.lock()
        count += 1
        condition.broadcast()
        condition.unlock()
    }

    var value: Int {
        condition.lock()
        defer { condition.unlock() }
        return count
    }

    func waitForCount(_ target: Int, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        condition.lock()
        defer { condition.unlock() }

        while count < target {
            if !condition.wait(until: deadline) {
                break
            }
        }
        return count >= target
    }
}

private struct GTKPresentedNavigationStateProbeView: View {
    @State private var isPresented = false

    var body: some View {
        VStack {
            Button("Show Presented") {
                isPresented = true
            }
            Text("Root")
                .navigationDestination(isPresented: $isPresented) {
                    Text("Presented After State")
                }
        }
    }
}

private struct GTKPresentedNavigationPickerProbeView: View {
    enum Choice: String, Hashable, CaseIterable {
        case system
        case custom
    }

    @State private var choice: Choice = .system
    @State private var isPresented = false

    var body: some View {
        VStack {
            Picker(
                "Font",
                selection: Binding<Choice>(
                    get: { choice },
                    set: { newValue in
                        choice = newValue
                        if newValue == .custom {
                            isPresented = true
                        }
                    }
                )
            ) {
                Text("System").tag(Choice.system)
                Text("Custom").tag(Choice.custom)
            }
            .navigationDestination(isPresented: $isPresented) {
                Text("Picker Presented Destination")
            }
        }
    }
}

private struct GTKPresentedNavigationDismissDestination: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button("Dismiss Destination") {
            dismiss()
        }
    }
}

private func drainGTKMainContext(maxIterations: Int = 20) {
    for _ in 0..<maxIterations {
        if g_main_context_iteration(nil, 0) == 0 {
            break
        }
    }
}

private func waitForGTKLabelMarkup(
    in widget: UnsafeMutablePointer<GtkWidget>,
    timeout: TimeInterval,
    predicate: (String) -> Bool
) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
        drainGTKMainContext(maxIterations: 100)
        var labels: [UnsafeMutablePointer<GtkWidget>] = []
        gtkCollectLabels(in: widget, into: &labels)
        for label in labels {
            guard gtk_label_get_use_markup(OpaquePointer(label)) != 0 else { continue }
            let markup = String(cString: gtk_label_get_label(OpaquePointer(label)))
            if predicate(markup) {
                return true
            }
        }
        Thread.sleep(forTimeInterval: 0.001)
    } while Date() < deadline
    return false
}

private func waitForGTKLabelText(
    in widget: UnsafeMutablePointer<GtkWidget>,
    timeout: TimeInterval,
    predicate: ([String]) -> Bool
) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
        drainGTKMainContext(maxIterations: 100)
        let labels = gtkLabelTexts(in: widget)
        if predicate(labels) {
            return true
        }
        Thread.sleep(forTimeInterval: 0.001)
    } while Date() < deadline
    drainGTKMainContext(maxIterations: 100)
    return predicate(gtkLabelTexts(in: widget))
}

private func gtkDebugLabelMarkups(in widget: UnsafeMutablePointer<GtkWidget>) -> [String] {
    var labels: [UnsafeMutablePointer<GtkWidget>] = []
    gtkCollectLabels(in: widget, into: &labels)
    return labels.map { label in
        String(cString: gtk_label_get_label(OpaquePointer(label)))
    }
}

private func presentGTKWidget(
    _ widget: UnsafeMutablePointer<GtkWidget>
) -> UnsafeMutablePointer<GtkWidget> {
    let window = gtk_window_new()!
    gtk_window_set_child(windowPointer(window), widget)
    gtk_window_present(windowPointer(window))
    drainGTKMainContext(maxIterations: 100)
    return window
}

private struct GTKItemSheetRootOverlayDismissProbeItem: Identifiable {
    let id: Int
}

private struct GTKItemSheetRootOverlayDismissProbeView: View {
    @State private var item: GTKItemSheetRootOverlayDismissProbeItem?
    let dismissAfterYield: Bool
    let onDismiss: () -> Void

    init(dismissAfterYield: Bool = false, onDismiss: @escaping () -> Void) {
        _item = State(wrappedValue: GTKItemSheetRootOverlayDismissProbeItem(id: 1))
        self.dismissAfterYield = dismissAfterYield
        self.onDismiss = onDismiss
    }

    var body: some View {
        Text("Host")
            .sheet(item: $item, onDismiss: onDismiss) { _ in
                GTKItemSheetRootOverlayDismissSheet(dismissAfterYield: dismissAfterYield)
            }
    }
}

private struct GTKItemSheetRootOverlayDismissSheet: View {
    @Environment(\.dismiss) private var dismiss
    let dismissAfterYield: Bool

    var body: some View {
        VStack {
            Text("Sheet Content")
            Button("Dismiss Sheet") {
                if dismissAfterYield {
                    Task {
                        await Task.yield()
                        dismiss()
                    }
                } else {
                    dismiss()
                }
            }
        }
    }
}

private struct GTKSheetNavigationChromeProbeView: View {
    @State private var isPresented = true

    var body: some View {
        Text("Host")
            .sheet(isPresented: $isPresented) {
                NavigationStack {
                    Text("Sheet Body")
                        .navigationTitle("Sheet Title")
                        .toolbar {
                            ToolbarItem(placement: .leading) {
                                Button("Cancel") {
                                    isPresented = false
                                }
                            }
                        }
                }
            }
    }
}

private struct GTKItemSheetRootOverlayInterceptedDismissProbeView: View {
    @State private var item: GTKItemSheetRootOverlayDismissProbeItem?
    let shouldConfirm: Binding<Bool>
    let onDismiss: () -> Void

    init(shouldConfirm: Binding<Bool>, onDismiss: @escaping () -> Void) {
        _item = State(wrappedValue: GTKItemSheetRootOverlayDismissProbeItem(id: 1))
        self.shouldConfirm = shouldConfirm
        self.onDismiss = onDismiss
    }

    var body: some View {
        Text("Host")
            .sheet(item: $item, onDismiss: onDismiss) { _ in
                GTKItemSheetRootOverlayInterceptedDismissSheet(shouldConfirm: shouldConfirm)
            }
    }
}

private struct GTKItemSheetRootOverlayInterceptedDismissSheet: View {
    @Environment(\.dismiss) private var dismiss
    let shouldConfirm: Binding<Bool>

    var body: some View {
        VStack {
            Text("Guarded Sheet Content")
            Button("Dismiss Guarded Sheet") {
                dismiss()
            }
        }
        .dismissalConfirmationDialog(
            "Discard changes?",
            shouldPresent: shouldConfirm,
            actions: [AlertButton("Discard", role: .destructive)]
        )
    }
}

private struct GTKTaskOnceProbeView: View {
    @State private var tick: Int
    let counter: GTKTaskRunCounter

    init(tick: State<Int>, counter: GTKTaskRunCounter) {
        self._tick = tick
        self.counter = counter
    }

    var body: some View {
        Text("tick \(tick)")
            .frame(width: tick.isMultiple(of: 2) ? 80 : 96)
            .task {
                counter.increment()
            }
    }
}

private struct GTKTaskFullRebuildProbeView: View {
    @State private var tick: Int
    let counter: GTKTaskRunCounter

    init(tick: State<Int>, counter: GTKTaskRunCounter) {
        self._tick = tick
        self.counter = counter
    }

    var body: some View {
        VStack {
            if tick.isMultiple(of: 2) {
                Text("even \(tick)")
            } else {
                HStack {
                    Text("odd \(tick)")
                    Text("detail")
                }
            }
        }
        .task {
            counter.increment()
        }
    }
}

private struct GTKDetachedRebuildProbeView: View {
    @State private var value: Int

    init(value: State<Int>) {
        _value = value
    }

    var body: some View {
        Text("value \(value)")
    }
}

private struct GTKTabTaskProbeView: View {
    let counter: GTKTaskRunCounter

    var body: some View {
        TabView(initialTab: 1) {
            Tab("Timeline", id: "timeline") {
                Text("Timeline")
            }
            Tab("Explore", id: "explore") {
                List {
                    Text("Explore row")
                }
                .task {
                    counter.increment()
                }
            }
        }
    }
}

private struct GTKBoundNavigationRootContentProbeView: View {
    let includePrefix: Bool
    let counter: GTKTaskRunCounter

    init(includePrefix: Bool, counter: GTKTaskRunCounter) {
        self.includePrefix = includePrefix
        self.counter = counter
    }

    var body: some View {
        VStack {
            if includePrefix {
                GTKEmptyStatefulRowProbe()
                Text("Changed Root Prefix")
            }
            Text("Root")
                .navigationDestination(for: String.self) { value in
                    GTKBoundNavigationDestinationProbeView(value: value, counter: counter)
                }
        }
    }
}

private struct GTKBoundNavigationDestinationProbeView: View {
    let value: String
    let counter: GTKTaskRunCounter
    @State private var loaded = false

    var body: some View {
        VStack {
            Text(loaded ? "Loaded \(value)" : "Loading \(value)")
            Button("Load \(value)") {
                guard !loaded else { return }
                counter.increment()
                loaded = true
            }
        }
    }
}

private struct GTKBoundNavigationOnAppearProbeView: View {
    let value: String
    let counter: GTKTaskRunCounter
    @State private var appeared = false

    var body: some View {
        Text(appeared ? "Appeared \(value)" : "Waiting \(value)")
            .onAppear {
                guard !appeared else { return }
                counter.increment()
                appeared = true
            }
    }
}

private final class GTKNavigationObservableProbeModel: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()
    var text = "Retry" {
        willSet {
            objectWillChange.send()
        }
    }
}

private struct GTKBoundNavigationObservableProbeView: View {
    let value: String
    let counter: GTKTaskRunCounter
    @State private var model = GTKNavigationObservableProbeModel()

    var body: some View {
        Text(model.text)
            .onAppear {
                guard model.text != "Loaded \(value)" else { return }
                counter.increment()
                model.text = "Loaded \(value)"
            }
    }
}

private struct GTKOnAppearOnceProbeView: View {
    @State private var tick: Int
    let counter: GTKTaskRunCounter

    init(tick: State<Int>, counter: GTKTaskRunCounter) {
        self._tick = tick
        self.counter = counter
    }

    var body: some View {
        Text("tick \(tick)")
            .frame(width: tick.isMultiple(of: 2) ? 80 : 96)
            .onAppear {
                counter.increment()
            }
    }
}

private struct GTKReactiveRenderableOnAppearProbe: View, GTKRenderable {
    @State private var marker = false
    let counter: GTKTaskRunCounter

    var body: some View {
        Text(marker ? "ready" : "waiting")
            .onAppear {
                marker = true
                counter.increment()
            }
    }

    @MainActor
    func gtkCreateWidget() -> OpaquePointer {
        gtkRenderView(body)
    }
}

private struct GTKListRowOnAppearProbeView: View {
    @State private var didAppear = false
    let counter: GTKTaskRunCounter

    var body: some View {
        Text(didAppear ? "appeared" : "waiting")
            .onAppear {
                guard !didAppear else { return }
                didAppear = true
                counter.increment()
            }
    }
}

private struct GTKConditionalOnAppearProbeView: View {
    @State private var show: Bool
    let counter: GTKTaskRunCounter

    init(show: State<Bool>, counter: GTKTaskRunCounter) {
        self._show = show
        self.counter = counter
    }

    var body: some View {
        VStack {
            if show {
                Text("appearing")
                    .onAppear {
                        counter.increment()
                    }
            }
            Text("stable")
        }
    }
}

private struct GTKParentRemountOnAppearProbeView: View {
    @State private var tick: Int
    let counter: GTKTaskRunCounter

    init(tick: State<Int>, counter: GTKTaskRunCounter) {
        self._tick = tick
        self.counter = counter
    }

    var body: some View {
        VStack {
            GTKChildRemountedOnAppearProbeView(counter: counter)
            if tick.isMultiple(of: 2) {
                Text("even \(tick)")
            } else {
                HStack {
                    Text("odd \(tick)")
                    Text("detail")
                }
            }
        }
    }
}

private struct GTKStatelessRootProbeView<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
    }
}

private struct GTKParentRemountTaskProbeView: View {
    @State private var tick: Int
    let counter: GTKTaskRunCounter

    init(tick: State<Int>, counter: GTKTaskRunCounter) {
        self._tick = tick
        self.counter = counter
    }

    var body: some View {
        VStack {
            GTKChildRemountedTaskProbeView(counter: counter)
            if tick.isMultiple(of: 2) {
                Text("even task \(tick)")
            } else {
                HStack {
                    Text("odd task \(tick)")
                    Text("detail")
                }
            }
        }
    }
}

private struct GTKChildRemountedTaskProbeView: View {
    @State private var loaded = false
    let counter: GTKTaskRunCounter

    var body: some View {
        Text(loaded ? "task loaded" : "task loading")
            .task {
                counter.increment()
                loaded = true
            }
    }
}

private struct GTKChildRemountedOnAppearProbeView: View {
    @State private var loaded = false
    let counter: GTKTaskRunCounter

    var body: some View {
        Text(loaded ? "loaded" : "loading")
            .onAppear {
                counter.increment()
                loaded = true
            }
    }
}

private struct GTKOnAppearModifier: ViewModifier {
    let counter: GTKTaskRunCounter

    func body(content: Content) -> some View {
        content.onAppear {
            counter.increment()
        }
    }
}

private struct GTKThemeBootstrapProbeView: View {
    @State private var theme: GTKThemeBootstrapModel

    init(theme: State<GTKThemeBootstrapModel>) {
        self._theme = theme
    }

    var body: some View {
        let color = theme.tintColor
        Text("Boost")
            .foregroundColor(color)
            .modifier(GTKThemeBootstrapModifier(theme: theme))
    }
}

private struct GTKThemeBootstrapModifier: ViewModifier {
    let theme: GTKThemeBootstrapModel

    func body(content: Content) -> some View {
        content.onAppear {
            theme.tintColor = GTKThemeBootstrapModel.iceCubePurple
        }
    }
}

private struct GTKStatefulDescriptorButtonStyle: ButtonStyle {
    let isOn: Bool
    let tintColor: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(isOn ? tintColor : .secondary)
    }
}

private struct GTKDelayedEnvButtonView: View {
    @Environment(GTKDelayedEnvModel.self) var model

    var body: some View {
        Button("Increment") { model.count += 1 }
    }
}

private struct GTKDelayedEnvDescriptorTextView: View {
    @Environment(GTKDelayedEnvModel.self) var model

    var body: some View {
        Text("count \(model.count)")
    }
}

private struct GTKDelayedEnvOnAppearView: View {
    @Environment(GTKDelayedEnvModel.self) var model

    var body: some View {
        Text("appear").onAppear { model.count += 1 }
    }
}

private struct GTKDelayedEnvOnDisappearView: View {
    @Environment(GTKDelayedEnvModel.self) var model

    var body: some View {
        Text("disappear").onDisappear { model.count += 1 }
    }
}

private struct GTKDelayedEnvTapGestureView: View {
    @Environment(GTKDelayedEnvModel.self) var model

    var body: some View {
        Text("Tap").onTapGesture { model.count += 1 }
    }
}

private struct GTKDelayedEnvLongPressView: View {
    @Environment(GTKDelayedEnvModel.self) var model

    var body: some View {
        Text("Hold").onLongPressGesture(minimumDuration: 0) { model.count += 1 }
    }
}

private struct GTKDelayedEnvDragView: View {
    @Environment(GTKDelayedEnvModel.self) var model

    var body: some View {
        Text("Drag").onDrag(onChanged: { _ in model.count += 1 }, onEnded: { _ in model.count += 1 })
    }
}

private struct GTKDelayedEnvDisclosureGroupView: View {
    @Environment(GTKDelayedEnvModel.self) var model

    var body: some View {
        DisclosureGroup(
            "Toggle",
            isExpanded: Binding(
                get: { false },
                set: { _ in model.count += 1 }
            )
        ) {
            Text("Hidden")
        }
    }
}

private struct GTKDelayedEnvMenuView: View {
    @Environment(GTKDelayedEnvModel.self) var model

    var body: some View {
        Menu("Actions") {
            MenuItem("Increment") { model.count += 1 }
        }
    }
}

private struct GTKNavigationToolbarDismissProbeView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Text("Root")
                .toolbar {
                    ToolbarItem(placement: .trailing) {
                        Button("Close") {
                            dismiss()
                        }
                    }
                }
        }
    }
}

private struct GTKEmptyStatefulRowProbe: View {
    @State private var isVisible = false

    var body: some View {
        if isVisible {
            Text("Hidden state row")
        }
    }
}

private struct GTKOnePixelListAnchor: View {
    var body: some View {
        HStack { EmptyView() }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(.init())
            .id("top")
    }
}

private struct GTKTaskStateUpdateProbe: View {
    @State private var loaded = false

    var body: some View {
        Text(loaded ? "Loaded" : "Loading")
            .task {
                loaded = true
            }
    }
}

private struct GTKStatusActionProbeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(Color.gray)
            .scaleEffect(configuration.isPressed ? 0.8 : 1)
    }
}

private func gtkDescriptorContainsText(_ node: GTK4DescriptorNode, _ text: String) -> Bool {
    if case .text(let descriptor) = node.props, descriptor.content == text {
        return true
    }
    return node.children.contains { gtkDescriptorContainsText($0, text) }
}

private struct StatefulGTKStatusRowProbe: View {
    let index: Int
    @State private var isExpanded = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("avatar")
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 8) {
                Text("John Mastodon")
                    .lineLimit(1)
                Text("""
                Here's to the crazy ones. The misfits. The rebels. The troublemakers.
                They are long enough to wrap in a timeline cell and force width-resolved row height.
                """)
                .lineLimit(nil)

                StatefulGTKStatusActionsProbe(index: index)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 12)
    }
}

private struct ExternalStatefulGTKStatusRowProbe: View {
    @State private var index: Int

    init(index: Int) {
        _index = .init(wrappedValue: index)
    }

    var body: some View {
        StatefulGTKStatusRowProbe(index: index)
    }
}

private struct StatefulGTKStatusActionsProbe: View {
    let index: Int
    @State private var isShareSheetPresented = false

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                statusActionProbeButton("reply-\(index)", count: "34")
                statusActionProbeButton("boost-\(index)", count: "10")
                statusActionProbeButton("favorite-\(index)", count: "8")
                HStack {
                    statusActionProbeButton("share-\(index)", count: nil)
                    Spacer()
                }
                Text("menu-\(index)")
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private final class GTKButtonActionRecorder {
    private let lock = NSLock()
    private(set) var values: [Int] = []

    func record(_ value: Int) {
        lock.lock()
        values.append(value)
        lock.unlock()
    }
}

private struct GTKMutableButtonActionProbeView: View {
    @State private var selectedID: Int
    let recorder: GTKButtonActionRecorder

    init(selectedID: State<Int>, recorder: GTKButtonActionRecorder) {
        self._selectedID = selectedID
        self.recorder = recorder
    }

    var body: some View {
        VStack {
            Text("selected \(selectedID)")
            Button("Favorite") {
                recorder.record(selectedID)
            }
        }
    }
}

private struct GTKMutableMenuActionProbeView: View {
    @State private var selectedID: Int
    let recorder: GTKButtonActionRecorder

    init(selectedID: State<Int>, recorder: GTKButtonActionRecorder) {
        self._selectedID = selectedID
        self.recorder = recorder
    }

    var body: some View {
        VStack {
            Text("selected \(selectedID)")
            Menu("Actions") {
                MenuItem("Boost") {
                    recorder.record(selectedID)
                }
            }
        }
    }
}

private final class GTKScopedEnvironmentMenuModel {
    let id: Int
    let recorder: GTKButtonActionRecorder

    init(id: Int, recorder: GTKButtonActionRecorder) {
        self.id = id
        self.recorder = recorder
    }

    func record() {
        recorder.record(id)
    }
}

private struct GTKScopedEnvironmentMenuProbeView: View {
    @Environment(GTKScopedEnvironmentMenuModel.self) private var model
    @State private var revision: Int

    init(revision: State<Int>) {
        self._revision = revision
    }

    var body: some View {
        VStack {
            Text("revision \(revision)")
            Menu("Actions") {
                MenuItem("Boost") {
                    model.record()
                }
            }
        }
    }
}

private struct GTKStatefulFormRowButtonProbeView: View {
    @State private var isReady = true
    let recorder: GTKButtonActionRecorder

    var body: some View {
        Button(isReady ? "Open account" : "Waiting") {
            recorder.record(42)
        }
    }
}

private struct GTKMutableIdentifiedStateProbeView: View {
    @State private var selectedID: Int
    let recorder: GTKButtonActionRecorder

    init(selectedID: State<Int>, recorder: GTKButtonActionRecorder) {
        self._selectedID = selectedID
        self.recorder = recorder
    }

    var body: some View {
        GTKStatefulIdentifiedButtonProbeView(modelID: selectedID, recorder: recorder)
            .id(selectedID)
    }
}

private struct GTKStatefulIdentifiedButtonProbeView: View {
    @State private var modelID: Int
    let recorder: GTKButtonActionRecorder

    init(modelID: Int, recorder: GTKButtonActionRecorder) {
        self._modelID = State(wrappedValue: modelID)
        self.recorder = recorder
    }

    var body: some View {
        Button("Record") {
            recorder.record(modelID)
        }
    }
}

private struct GTKAccidentalVExpandOverlayProbe: View, GTKRenderable {
    typealias Body = Never

    var body: Never { fatalError("GTKAccidentalVExpandOverlayProbe is a primitive view") }

    @MainActor
    func gtkCreateWidget() -> OpaquePointer {
        let box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
        let label = gtk_label_new("Preview")!
        gtk_widget_set_size_request(box, -1, 64)
        gtk_widget_set_hexpand(box, 1)
        gtk_widget_set_vexpand(box, 1)
        gtk_box_append(boxPointer(box), label)
        return opaqueFromWidget(box)
    }
}

private func statusActionProbeButton(_ title: String, count: String?) -> some View {
    Button {} label: {
        HStack(spacing: 2) {
            Text(title)
            if let count {
                Text(count)
                    .lineLimit(1)
                    .foregroundColor(Color.gray)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
    }
    .buttonStyle(GTKStatusActionProbeButtonStyle())
    .offset(x: -8)
}

private struct GTKWindowRootSheetItem: Identifiable {
    let id: Int
    let name: String
}

private final class GTKWindowRootObservableProbe: ObservableObject {
    @Published var item: GTKWindowRootSheetItem?
}

private struct GTKWindowRootAppStateProbe {
    @State var model = GTKWindowRootObservableProbe()
}

private final class GTKWindowRootClientProbe: ObservableObject {
    let name: String

    init(name: String) {
        self.name = name
    }
}

private final class GTKWindowRootClientManagerProbe: ObservableObject {
    @Published var client = GTKWindowRootClientProbe(name: "signed-out")
}

private struct GTKWindowRootEnvironmentAppStateProbe {
    @State var manager = GTKWindowRootClientManagerProbe()
}

private struct GTKWindowRootEnvironmentReaderProbe: View {
    @Environment(GTKWindowRootClientProbe.self) private var client

    var body: some View {
        Text("client \(client.name)")
    }
}

private func requireGTK(
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    guard gtk_is_initialized() != 0 else {
        throw XCTSkip("GTK could not initialize in this environment.", file: file, line: line)
    }
}

private func unwrapFirstChild(
    of widget: UnsafeMutablePointer<GtkWidget>,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> UnsafeMutablePointer<GtkWidget> {
    guard let child = gtk_widget_get_first_child(widget) else {
        XCTFail("Expected widget to have a child.", file: file, line: line)
        throw XCTSkip()
    }
    return child
}

private func unwrapFirstDescendant(
    ofType typeName: String,
    in widget: UnsafeMutablePointer<GtkWidget>,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> UnsafeMutablePointer<GtkWidget> {
    if let found = gtkFirstDescendant(ofType: typeName, in: widget) {
        return found
    }
    XCTFail("Expected widget tree to contain \(typeName).", file: file, line: line)
    throw XCTSkip()
}

private func gtkFirstDescendant(
    ofType typeName: String,
    in widget: UnsafeMutablePointer<GtkWidget>
) -> UnsafeMutablePointer<GtkWidget>? {
    if gtkWidgetTypeName(widget) == typeName {
        return widget
    }

    var child = gtk_widget_get_first_child(widget)
    while let current = child {
        if let found = gtkFirstDescendant(ofType: typeName, in: current) {
            return found
        }
        child = gtk_widget_get_next_sibling(current)
    }

    return nil
}

private func unwrapNextSibling(
    of widget: UnsafeMutablePointer<GtkWidget>,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> UnsafeMutablePointer<GtkWidget> {
    guard let sibling = gtk_widget_get_next_sibling(widget) else {
        XCTFail("Expected widget to have a next sibling.", file: file, line: line)
        throw XCTSkip()
    }
    return sibling
}

private func measuredSize(of widget: UnsafeMutablePointer<GtkWidget>) -> ViewSize {
    var widthMin: Int32 = 0
    var widthNat: Int32 = 0
    var heightMin: Int32 = 0
    var heightNat: Int32 = 0
    gtk_swift_widget_measure(widget, GTK_ORIENTATION_HORIZONTAL, -1, &widthMin, &widthNat)
    gtk_swift_widget_measure(widget, GTK_ORIENTATION_VERTICAL, -1, &heightMin, &heightNat)
    return ViewSize(
        width: Double(max(widthMin, widthNat)),
        height: Double(max(heightMin, heightNat))
    )
}

private func allocate(widget: UnsafeMutablePointer<GtkWidget>, size: ViewSize) {
    gtk_widget_allocate(widget, Int32(size.width), Int32(size.height), -1, nil)
}

private func allocatedSize(of widget: UnsafeMutablePointer<GtkWidget>) -> ViewSize {
    ViewSize(
        width: Double(gtk_widget_get_width(widget)),
        height: Double(gtk_widget_get_height(widget))
    )
}

private func translatedChildOrigin(
    child: UnsafeMutablePointer<GtkWidget>,
    in wrapper: UnsafeMutablePointer<GtkWidget>
) -> ViewPoint {
    var sourcePoint = graphene_point_t()
    graphene_point_init(&sourcePoint, 0, 0)
    var translatedPoint = graphene_point_t()
    _ = gtk_widget_compute_point(child, wrapper, &sourcePoint, &translatedPoint)
    return ViewPoint(x: Double(translatedPoint.x), y: Double(translatedPoint.y))
}

private func gtkWidgetTypeName(_ widget: UnsafeMutablePointer<GtkWidget>) -> String {
    String(cString: g_type_name(gtk_swift_get_widget_type(widget)))
}

private func gtkCountLayoutHelpers(in widget: UnsafeMutablePointer<GtkWidget>) -> Int {
    var count = 0
    let gobject = UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GObject.self)
    if g_object_get_data(gobject, gtkSwiftLayoutHelperMarker) != nil {
        count += 1
    }
    var child = gtk_widget_get_first_child(widget)
    while let current = child {
        count += gtkCountLayoutHelpers(in: current)
        child = gtk_widget_get_next_sibling(current)
    }
    return count
}

private func gtkCountDescendants(
    ofType typeName: String,
    in widget: UnsafeMutablePointer<GtkWidget>
) -> Int {
    var count = gtkWidgetTypeName(widget) == typeName ? 1 : 0
    var child = gtk_widget_get_first_child(widget)
    while let current = child {
        count += gtkCountDescendants(ofType: typeName, in: current)
        child = gtk_widget_get_next_sibling(current)
    }
    return count
}

private func gtkCollectButtons(
    in widget: UnsafeMutablePointer<GtkWidget>,
    into buttons: inout [UnsafeMutablePointer<GtkWidget>]
) {
    if gtk_swift_widget_is_button(widget) != 0 {
        buttons.append(widget)
    }
    var child = gtk_widget_get_first_child(widget)
    while let current = child {
        gtkCollectButtons(in: current, into: &buttons)
        child = gtk_widget_get_next_sibling(current)
    }
}

private func gtkCollectMenuButtons(
    in widget: UnsafeMutablePointer<GtkWidget>,
    into menuButtons: inout [UnsafeMutablePointer<GtkWidget>]
) {
    if gtk_swift_widget_is_menu_button(widget) != 0 {
        menuButtons.append(widget)
    }
    var child = gtk_widget_get_first_child(widget)
    while let current = child {
        gtkCollectMenuButtons(in: current, into: &menuButtons)
        child = gtk_widget_get_next_sibling(current)
    }
}

private func gtkCollectLabels(
    in widget: UnsafeMutablePointer<GtkWidget>,
    into labels: inout [UnsafeMutablePointer<GtkWidget>]
) {
    if gtkWidgetTypeName(widget) == "GtkLabel" {
        labels.append(widget)
        return
    }
    var child = gtk_widget_get_first_child(widget)
    while let current = child {
        gtkCollectLabels(in: current, into: &labels)
        child = gtk_widget_get_next_sibling(current)
    }
}

private func gtkLabelTexts(in widget: UnsafeMutablePointer<GtkWidget>) -> [String] {
    var labels: [UnsafeMutablePointer<GtkWidget>] = []
    gtkCollectLabels(in: widget, into: &labels)
    return labels.map { label in
        String(cString: gtk_label_get_text(OpaquePointer(label)))
    }
}

private func gtkDebugWidgetAncestors(
    _ widget: UnsafeMutablePointer<GtkWidget>,
    in root: UnsafeMutablePointer<GtkWidget>
) {
    var lines: [String] = []
    var current: UnsafeMutablePointer<GtkWidget>? = widget
    var depth = 0
    while let node = current, depth < 24 {
        var minW: gint = 0
        var natW: gint = 0
        var minH: gint = 0
        var natH: gint = 0
        gtk_widget_measure(node, GTK_ORIENTATION_HORIZONTAL, -1, &minW, &natW, nil, nil)
        gtk_widget_measure(node, GTK_ORIENTATION_VERTICAL, -1, &minH, &natH, nil, nil)
        let origin = translatedChildOrigin(child: node, in: root)
        let size = allocatedSize(of: node)
        lines.append(
            "#\(depth) \(gtkWidgetTypeName(node)) origin=\(Int(origin.x)),\(Int(origin.y)) size=\(Int(size.width))x\(Int(size.height)) natural=\(natW)x\(natH) min=\(minW)x\(minH) hex=\(gtk_widget_get_hexpand(node)) halign=\(gtk_widget_get_halign(node).rawValue)"
        )
        var childLines: [String] = []
        var child = gtk_widget_get_first_child(node)
        var index = 0
        while let current = child, index < 12 {
            let childOrigin = translatedChildOrigin(child: current, in: root)
            let childSize = allocatedSize(of: current)
            childLines.append(
                "  child[\(index)] \(gtkWidgetTypeName(current)) origin=\(Int(childOrigin.x)),\(Int(childOrigin.y)) size=\(Int(childSize.width))x\(Int(childSize.height)) hex=\(gtk_widget_get_hexpand(current)) halign=\(gtk_widget_get_halign(current).rawValue)"
            )
            child = gtk_widget_get_next_sibling(current)
            index += 1
        }
        if !childLines.isEmpty {
            lines.append(contentsOf: childLines)
        }
        if node == root {
            break
        }
        current = gtk_widget_get_parent(node)
        depth += 1
    }
    let output = "[GTK4RenderTests tree]\n" + lines.joined(separator: "\n") + "\n"
    FileHandle.standardError.write(Data(output.utf8))
}
