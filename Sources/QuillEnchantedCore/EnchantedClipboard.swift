import QuillKit

public enum EnchantedClipboard {
    public static func setString(_ message: String) {
        QuillClipboard.shared.setString(message)
    }
}
