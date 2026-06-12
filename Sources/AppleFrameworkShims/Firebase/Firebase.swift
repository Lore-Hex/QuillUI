// Firebase shim: Telegram-Mac's analytics bootstrap is inert on QuillOS.
import Foundation

public enum FirebaseApp {
    public static func configure() {}
}
