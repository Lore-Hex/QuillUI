//
// Minimal headless AppContext for the QuillOS Signal smoke harness (Track B).
// Installed via SetCurrentAppContext(...) before running Signal's GRDB schema
// migrations. Only the directory-path accessors do real work (the schema
// migration reads appSharedDataDirectoryPath); everything else is an inert
// "headless, backgrounded, no-UI" default. Globbed into the SSK module.
//
import Foundation
import UIKit

public final class QuillSmokeAppContext: NSObject, AppContext {
    private let root: String, docs: String, shared: String, dbBase: String, logs: String
    public let appLaunchTime: Date
    public var mainWindow: UIWindow?

    public override init() {
        let fm = FileManager.default
        let r = fm.temporaryDirectory
            .appendingPathComponent("quill-signal-smoke", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let d = r.appendingPathComponent("Documents", isDirectory: true)
        let s = r.appendingPathComponent("SharedData", isDirectory: true)
        let db = r.appendingPathComponent("Database", isDirectory: true)
        let lg = r.appendingPathComponent("Logs", isDirectory: true)
        for u in [r, d, s, db, lg] { try? fm.createDirectory(at: u, withIntermediateDirectories: true) }
        root = r.path; docs = d.path; shared = s.path; dbBase = db.path; logs = lg.path
        appLaunchTime = Date()
        super.init()
    }
    public var type: AppContextType { .main }
    public var isMainAppAndActive: Bool { false }
    @MainActor public var isMainAppAndActiveIsolated: Bool { false }
    public var isRTL: Bool { false }
    public var isRunningTests: Bool { false }
    public var frame: CGRect { .zero }
    public var reportedApplicationState: UIApplication.State { .background }
    public func isInBackground() -> Bool { true }
    public func isAppForegroundAndActive() -> Bool { false }
    public func mainApplicationStateOnLaunch() -> UIApplication.State { .background }
    public func canPresentNotifications() -> Bool { false }
    public var shouldProcessIncomingMessages: Bool { false }
    public var hasUI: Bool { false }
    public func beginBackgroundTask(with expirationHandler: @escaping BackgroundTaskExpirationHandler) -> UIBackgroundTaskIdentifier { .invalid }
    public func endBackgroundTask(_ backgroundTaskIdentifier: UIBackgroundTaskIdentifier) {}
    public func frontmostViewController() -> UIViewController? { nil }
    public func openSystemSettings() {}
    public func open(_ url: URL, completion: ((Bool) -> Void)?) { completion?(false) }
    public func runNowOrWhenMainAppIsActive(_ block: @escaping AppActiveBlock) { block() }
    public func appDocumentDirectoryPath() -> String { docs }
    public func appSharedDataDirectoryPath() -> String { shared }
    public func appDatabaseBaseDirectoryPath() -> String { dbBase }
    public var debugLogsDirPath: String { logs }
    public func appUserDefaults() -> UserDefaults { .standard }
}
