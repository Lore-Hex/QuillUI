import Foundation

/// Formats live WireGuard runtime stats for display, mirroring upstream
/// WireGuard-Apple's tunnel detail ("Data received" / "Data sent" / "Latest
/// handshake"). Pure value-to-string logic, so it is fully unit-testable; the live
/// data itself comes from `QuillWireGuardStatusParser` (slice 1) on an active
/// tunnel. Rendering these strings into the GTK/Qt detail is a follow-up that needs
/// the device runtime to feed live status.
public enum QuillWireGuardRuntimeFormatter {

    /// Human-readable transfer count using binary units:
    /// `0 B`, `512 B`, `1.00 KiB`, `1.50 KiB`, `2.00 MiB`, `1.00 GiB`.
    /// Exact bytes below 1 KiB; two decimals above.
    public static func transferText(_ bytes: UInt64) -> String {
        let units = ["KiB", "MiB", "GiB", "TiB", "PiB"]
        if bytes < 1024 {
            return "\(bytes) B"
        }
        var value = Double(bytes) / 1024
        var unitIndex = 0
        while value >= 1024 && unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }
        return String(format: "%.2f %@", value, units[unitIndex])
    }

    /// Relative latest-handshake text. `nil` (never connected) -> "Never";
    /// otherwise "Just now" / "N seconds|minutes|hours|days ago", mirroring
    /// upstream's "X ago". `now` is injected for deterministic formatting/testing.
    public static func handshakeText(_ date: Date?, now: Date) -> String {
        guard let date else { return "Never" }
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 5 { return "Just now" }
        if seconds < 60 { return "\(seconds) seconds ago" }

        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes) minute\(minutes == 1 ? "" : "s") ago" }

        let hours = minutes / 60
        if hours < 24 { return "\(hours) hour\(hours == 1 ? "" : "s") ago" }

        let days = hours / 24
        return "\(days) day\(days == 1 ? "" : "s") ago"
    }
}
