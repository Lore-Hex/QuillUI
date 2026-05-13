import Foundation
import QuillUI

public struct QuillInteractionSmokeConfiguration: Equatable, Sendable {
    public static let defaultWidth: Double = 640
    public static let defaultHeight: Double = 760

    public let backend: QuillBackendIdentifier
    public let windowTitle: String
    public let title: String
    public let clickTargetTitle: String
    public let panelMessage: String
    public let width: Double
    public let height: Double

    public init(
        backend: QuillBackendIdentifier,
        windowTitle: String,
        title: String,
        clickTargetTitle: String,
        panelMessage: String,
        width: Double = Self.defaultWidth,
        height: Double = Self.defaultHeight
    ) {
        self.backend = backend
        self.windowTitle = windowTitle
        self.title = title
        self.clickTargetTitle = clickTargetTitle
        self.panelMessage = panelMessage
        self.width = width
        self.height = height
    }

    public static func backendParitySurface(
        for backend: QuillBackendIdentifier
    ) -> QuillInteractionSmokeConfiguration {
        QuillInteractionSmokeConfiguration(
            backend: backend,
            windowTitle: "Quill Backend Interaction",
            title: "Quill Backend Interaction",
            clickTargetTitle: "Native backend click target",
            panelMessage: "QuillUI rendered this panel after a native backend button click."
        )
    }
}

public enum QuillInteractionSmokeScene {
    public static func scene(
        for backend: QuillBackendIdentifier
    ) -> some Scene {
        let configuration = QuillInteractionSmokeConfiguration.backendParitySurface(
            for: backend
        )

        return QuillAppWindow.scene(
            configuration.windowTitle,
            width: configuration.width,
            height: configuration.height,
            defaultSizePolicy: .requested
        ) {
            QuillInteractionSmokeView(configuration: configuration)
        }
    }
}

public struct QuillBackendInteractionSmokeApp<Backend: QuillBackend>: App {
    public init() {}

    public var body: some Scene {
        QuillInteractionSmokeScene.scene(for: Backend.identifier)
    }
}

public struct QuillInteractionSmokeView: View {
    private let title: String
    private let clickTargetTitle: String
    private let panelMessage: String

    @State private var isOpen = false
    @State private var typedText = ""

    public init(configuration: QuillInteractionSmokeConfiguration) {
        self.title = configuration.title
        self.clickTargetTitle = configuration.clickTargetTitle
        self.panelMessage = configuration.panelMessage
    }

    public init(
        title: String,
        clickTargetTitle: String,
        backendName: String
    ) {
        self.title = title
        self.clickTargetTitle = clickTargetTitle
        self.panelMessage = "QuillUI rendered this panel after a \(backendName) button click."
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold))

                Spacer()

                Button(isOpen ? "Hide Panel" : "Open Panel") {
                    isOpen.toggle()
                }
                .frame(width: 132, height: 36)
            }
            .padding(16)

            Divider()

            ZStack(alignment: .topLeading) {
                Color(hex: "#F7F7F8")

                VStack(alignment: .leading, spacing: 14) {
                    Text(clickTargetTitle)
                        .font(.system(size: 24, weight: .semibold))

                    Text("Button taps must mutate Swift state and repaint the view tree.")
                        .font(.system(size: 15))
                        .foregroundColor(Color(hex: "#4A4A4D"))

                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Type here", text: $typedText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 320, height: 36)

                        Text(typedText.isEmpty ? "No typed text yet" : "Typed: \(typedText)")
                            .font(.system(size: 14))
                            .foregroundColor(Color(hex: "#4A4A4D"))
                    }

                    if isOpen {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Interaction Open")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(Color(hex: "#FFFFFF"))

                            Text(panelMessage)
                                .font(.system(size: 14))
                                .foregroundColor(Color(hex: "#E8E8EA"))
                        }
                        .padding(18)
                        .frame(width: 360, alignment: .leading)
                        .background(Color(hex: "#1F2937"))
                        .cornerRadius(8)
                    }

                    NestedSidebarSmoke()
                    NestedBannerSmoke()
                    NestedSheetSmoke()
                    SidebarSheetSmoke()
                    BannerSheetSmoke()
                }
                .padding(32)
            }
        }
        .frame(width: 640, height: 760)
    }
}

private struct NestedSidebarSmoke: View {
    @State private var sidebarOpened = false

    var body: some View {
        QuillSidebarNavigationButton(
            title: sidebarOpened ? "Sidebar Open" : "Settings",
            systemImage: "gearshape.fill"
        ) {
            sidebarOpened.toggle()
        }
        .frame(width: 260, alignment: .leading)
    }
}

private struct NestedBannerSmoke: View {
    @State private var bannerOpened = false

    var body: some View {
        QuillStatusBanner(
            message: bannerOpened ? "Banner Open" : "Banner closed",
            actionTitle: "Settings"
        ) {
            bannerOpened.toggle()
        }
        .frame(width: 520, alignment: .leading)
    }
}

private struct NestedSheetSmoke: View {
    @State private var isPresented = false

    var body: some View {
        Button("Open Nested Sheet") {
            isPresented.toggle()
        }
        .sheet(isPresented: $isPresented) {
            SmokeSheetContent(
                title: "Nested Sheet Open",
                message: "A child view presented this sheet from @State.",
                width: 360,
                height: 180
            )
        }
    }
}

private struct SidebarSheetSmoke: View {
    @State private var isPresented = false

    var body: some View {
        QuillSidebarNavigationButton(
            title: "Open Sidebar Sheet",
            systemImage: "gearshape.fill"
        ) {
            isPresented.toggle()
        }
        .frame(width: 260, alignment: .leading)
        .sheet(isPresented: $isPresented) {
            SmokeSheetContent(
                title: "Sidebar Sheet Open",
                message: "A Quill sidebar button presented this sheet from @State.",
                width: 420,
                height: 200
            )
        }
    }
}

private struct BannerSheetSmoke: View {
    @State private var isPresented = false

    var body: some View {
        QuillStatusBanner(
            message: "Banner sheet closed",
            actionTitle: "Settings"
        ) {
            isPresented.toggle()
        }
        .frame(width: 520, alignment: .leading)
        .sheet(isPresented: $isPresented) {
            SmokeSheetContent(
                title: "Banner Sheet Open",
                message: "A Quill status banner action presented this sheet from @State.",
                width: 420,
                height: 200
            )
        }
    }
}

private struct SmokeSheetContent: View {
    let title: String
    let message: String
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 20, weight: .semibold))
            Text(message)
                .font(.system(size: 14))
        }
        .padding(24)
        .frame(width: width, height: height, alignment: .leading)
        .background(Color(hex: "#ECECF2"))
    }
}
