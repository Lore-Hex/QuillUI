import SceneKit
import SwiftUI

struct ContentView: View {
    @State private var scene = makeSolarSystemScene()
    @State private var isPaused = false

    var body: some View {
        ZStack(alignment: .bottom) {
            SceneView(
                scene: scene,
                options: [.allowsCameraControl, .autoenablesDefaultLighting]
            )
            .ignoresSafeArea()

            HStack(spacing: 16) {
                ForEach(planets, id: \.name) { planet in
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color(nsColor: planet.color))
                            .frame(width: 10, height: 10)
                        Text(planet.name)
                            .font(.caption)
                    }
                }
                Divider()
                    .frame(height: 14)
                Toggle("Pause", isOn: $isPaused)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                    .onChange(of: isPaused) { paused in
                        scene.isPaused = paused
                    }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.bottom, 12)
        }
        .frame(minWidth: 640, minHeight: 420)
    }
}
