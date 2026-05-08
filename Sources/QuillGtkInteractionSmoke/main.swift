import BackendGTK4
import QuillUI

private struct QuillGtkInteractionSmokeApp: App {
    var body: some Scene {
        WindowGroup("Quill GTK Interaction") {
            SmokeView()
        }
        .defaultWindowSize(width: 640, height: 420)
    }
}

private struct SmokeView: View {
    @State private var isOpen = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Quill GTK Interaction")
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
                    Text("Native GTK click target")
                        .font(.system(size: 24, weight: .semibold))

                    Text("Button taps must mutate Swift state and repaint the view tree.")
                        .font(.system(size: 15))
                        .foregroundColor(Color(hex: "#4A4A4D"))

                    if isOpen {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Interaction Open")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(Color(hex: "#FFFFFF"))

                            Text("QuillUI rendered this panel after a GTK button click.")
                                .font(.system(size: 14))
                                .foregroundColor(Color(hex: "#E8E8EA"))
                        }
                        .padding(18)
                        .frame(width: 360, alignment: .leading)
                        .background(Color(hex: "#1F2937"))
                        .cornerRadius(8)
                    }
                }
                .padding(32)
            }
        }
        .frame(width: 640, height: 420)
    }
}

GTK4Backend().run(QuillGtkInteractionSmokeApp.self)
