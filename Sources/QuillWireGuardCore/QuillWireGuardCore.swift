public enum QuillWireGuardBackend {
    public static var isAvailable: Bool {
        #if os(Linux)
        false
        #else
        true
        #endif
    }
}
