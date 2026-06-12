/// Window-level chrome style hints understood by desktop backends.
public enum WindowStyle: Equatable, Sendable {
    /// Use the backend default window chrome.
    case automatic
    /// Hide the title bar. GTK also suppresses SwiftOpenUI's in-window menu strip.
    case hiddenTitleBar
}

