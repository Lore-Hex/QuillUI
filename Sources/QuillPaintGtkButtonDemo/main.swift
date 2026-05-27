import QuillUIGtk

struct QuillPaintGtkButtonDemoApp: App {
    var body: some Scene {
        QuillAppWindow.scene(
            "QuillPaint GTK Button",
            width: 320,
            height: 180,
            defaultSizePolicy: .requested
        ) {
            VStack(spacing: 16) {
                Button("QuillPaint Button") {}
            }
            .padding(32)
        }
    }
}

QuillGtkPaintAdapter.install()
QuillGtkApp.run(QuillPaintGtkButtonDemoApp.self)
