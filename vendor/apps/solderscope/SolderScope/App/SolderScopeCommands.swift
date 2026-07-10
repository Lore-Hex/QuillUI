import SwiftUI

struct SolderScopeCommands: Commands {
    @ObservedObject var appState: AppState

    var body: some Commands {
        // Replace default New/Open commands
        CommandGroup(replacing: .newItem) { }

        // View commands
        CommandMenu("View") {
            Button("Toggle Scale Bar") {
                appState.toggleScaleBar()
            }
            .keyboardShortcut("b", modifiers: [])

            Button("Cycle Integration") {
                appState.cycleIntegration()
            }
            .keyboardShortcut("i", modifiers: [])

            Divider()

            Button("Reset View") {
                appState.resetView()
            }
            .keyboardShortcut("0", modifiers: [])

            Divider()

            Button("Flip Horizontal") {
                appState.flipHorizontal()
            }
            .keyboardShortcut("h", modifiers: [])

            Button("Flip Vertical") {
                appState.flipVertical()
            }
            .keyboardShortcut("v", modifiers: [])

            Button("Rotate 90° Clockwise") {
                appState.rotateClockwise()
            }
            .keyboardShortcut("]", modifiers: [])

            Divider()

            Button("Recalibrate...") {
                appState.isCalibrating = true
            }
            .disabled(appState.selectedCamera == nil)
        }

        // Capture commands
        CommandMenu("Capture") {
            Button(appState.isFrozen ? "Unfreeze" : "Freeze") {
                appState.toggleFreeze()
            }
            .keyboardShortcut(.space, modifiers: [])

            Divider()

            Button("Take Snapshot") {
                appState.takeSnapshot()
            }
            .keyboardShortcut("s", modifiers: [])

            Button(appState.isRecording ? "Stop Recording" : "Start Recording") {
                appState.toggleRecording()
            }
            .keyboardShortcut("r", modifiers: [])
        }

        // Help commands
        CommandGroup(replacing: .help) {
            Button("SolderScope Help") {
                // Open help
            }

            Divider()

            Button("Keyboard Shortcuts") {
                // Show keyboard shortcuts
            }
        }
    }
}
