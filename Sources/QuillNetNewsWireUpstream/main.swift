import AppKit
import NetNewsWireMacCore
import QuillAppKitGTK

@main
struct QuillNetNewsWireUpstreamMain {
    @MainActor
    static func main() {
        _ = QuillAppKitGTKAutoInstall.didInstall

        let host = NetNewsWireLinuxMainWindowHost()
        if CommandLine.arguments.contains("--smoke") {
            let snapshot = host.snapshot
            print("NetNewsWire upstream shell: title=\(snapshot.title) subtitle=\(snapshot.subtitle) splitItems=\(snapshot.splitViewItemCount) detailWebView=\(snapshot.hasDetailWebView)")
            return
        }

        host.show()
        NSApplication.shared.run()
    }
}
