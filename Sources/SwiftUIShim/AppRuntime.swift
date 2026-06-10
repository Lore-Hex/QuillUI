import BackendGTK4
import SwiftOpenUI

#if os(Linux)
public extension App {
    static func main() {
        GTK4Backend().run(Self.self)
    }
}
#endif
