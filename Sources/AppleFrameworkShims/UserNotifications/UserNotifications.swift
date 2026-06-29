//
// QuillUI Linux shim for Apple's `UserNotifications` framework.
//
// SignalServiceKit's `UserNotificationsPresenter` builds local-notification
// requests (content + trigger + category/action surface) and hands them to
// `UNUserNotificationCenter`. None of that exists in swift-corelibs, so this
// module mirrors the common types/initializers/members while routing state into
// QuillKit's process-local notification compatibility backend.
//
// HONEST STATUS: emulated. Requests, categories, settings, and delivered/pending
// lists are tracked deterministically, but nothing is presented by a desktop
// notification daemon yet. Wiring this to libnotify / org.freedesktop.Notifications
// is a later backend milestone.
//
import Foundation
import QuillKit

public let UNNotificationDefaultActionIdentifier = "com.apple.UNNotificationDefaultActionIdentifier"
public let UNNotificationDismissActionIdentifier = "com.apple.UNNotificationDismissActionIdentifier"

// MARK: - Option sets / enums

public struct UNAuthorizationOptions: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let badge = UNAuthorizationOptions(rawValue: 1 << 0)
    public static let sound = UNAuthorizationOptions(rawValue: 1 << 1)
    public static let alert = UNAuthorizationOptions(rawValue: 1 << 2)
    public static let carPlay = UNAuthorizationOptions(rawValue: 1 << 3)
    public static let criticalAlert = UNAuthorizationOptions(rawValue: 1 << 4)
    public static let providesAppNotificationSettings = UNAuthorizationOptions(rawValue: 1 << 5)
    public static let provisional = UNAuthorizationOptions(rawValue: 1 << 6)
    public static let announcement = UNAuthorizationOptions(rawValue: 1 << 7)
}

public enum UNAuthorizationStatus: Int, Sendable {
    case notDetermined = 0, denied = 1, authorized = 2, provisional = 3, ephemeral = 4
}

public struct UNNotificationActionOptions: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let authenticationRequired = UNNotificationActionOptions(rawValue: 1 << 0)
    public static let destructive = UNNotificationActionOptions(rawValue: 1 << 1)
    public static let foreground = UNNotificationActionOptions(rawValue: 1 << 2)
}

public struct UNNotificationCategoryOptions: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let customDismissAction = UNNotificationCategoryOptions(rawValue: 1 << 0)
    public static let allowInCarPlay = UNNotificationCategoryOptions(rawValue: 1 << 1)
    public static let hiddenPreviewsShowTitle = UNNotificationCategoryOptions(rawValue: 1 << 2)
    public static let hiddenPreviewsShowSubtitle = UNNotificationCategoryOptions(rawValue: 1 << 3)
    public static let allowAnnouncement = UNNotificationCategoryOptions(rawValue: 1 << 4)
}

public struct UNNotificationPresentationOptions: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let badge = UNNotificationPresentationOptions(rawValue: 1 << 0)
    public static let sound = UNNotificationPresentationOptions(rawValue: 1 << 1)
    public static let alert = UNNotificationPresentationOptions(rawValue: 1 << 2)
    public static let banner = UNNotificationPresentationOptions(rawValue: 1 << 3)
    public static let list = UNNotificationPresentationOptions(rawValue: 1 << 4)
}

// MARK: - Sound

public struct UNNotificationSoundName: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

public final class UNNotificationSound: @unchecked Sendable {
    public let name: UNNotificationSoundName?
    public init(named name: UNNotificationSoundName) { self.name = name }
    private init() { self.name = nil }
    public static let `default` = UNNotificationSound()
}

// MARK: - Content

public class UNNotificationContent: @unchecked Sendable {
    public var title: String = ""
    public var subtitle: String = ""
    public var body: String = ""
    public var badge: NSNumber?
    public var sound: UNNotificationSound?
    public var categoryIdentifier: String = ""
    public var threadIdentifier: String = ""
    public var targetContentIdentifier: String?
    public var userInfo: [AnyHashable: Any] = [:]
    public var attachments: [UNNotificationAttachment] = []
    public init() {}

    /// iOS refreshes content from a donated communication intent (sender avatar,
    /// etc.). Inert on Linux: returns self unchanged.
    public func updating(from intent: UNNotificationContentProviding) throws -> UNNotificationContent { self }
}

public final class UNMutableNotificationContent: UNNotificationContent, @unchecked Sendable {
    public override init() { super.init() }
}

public final class UNNotificationAttachment: @unchecked Sendable {
    public let identifier: String
    public let url: URL
    public init(identifier: String, url: URL, options: [AnyHashable: Any]? = nil) throws {
        self.identifier = identifier
        self.url = url
    }
}

/// Marker protocol: SignalServiceKit asks `interaction.intent as? UNNotificationContentProviding`.
public protocol UNNotificationContentProviding {}

// MARK: - Triggers

public class UNNotificationTrigger: @unchecked Sendable {
    public let repeats: Bool
    public init(repeats: Bool) { self.repeats = repeats }
}

public final class UNTimeIntervalNotificationTrigger: UNNotificationTrigger, @unchecked Sendable {
    public let timeInterval: TimeInterval
    public init(timeInterval: TimeInterval, repeats: Bool) {
        self.timeInterval = timeInterval
        super.init(repeats: repeats)
    }
}

// MARK: - Actions / categories

public final class UNNotificationActionIcon: @unchecked Sendable {
    public let systemImageName: String?
    public let templateImageName: String?
    public init(systemImageName: String) {
        self.systemImageName = systemImageName
        self.templateImageName = nil
    }
    public init(templateImageName: String) {
        self.systemImageName = nil
        self.templateImageName = templateImageName
    }
}

public class UNNotificationAction: @unchecked Sendable {
    public let identifier: String
    public let title: String
    public let options: UNNotificationActionOptions
    public let icon: UNNotificationActionIcon?
    public init(
        identifier: String,
        title: String,
        options: UNNotificationActionOptions = [],
        icon: UNNotificationActionIcon? = nil
    ) {
        self.identifier = identifier
        self.title = title
        self.options = options
        self.icon = icon
    }
}

public final class UNTextInputNotificationAction: UNNotificationAction, @unchecked Sendable {
    public let textInputButtonTitle: String
    public let textInputPlaceholder: String
    public init(
        identifier: String,
        title: String,
        options: UNNotificationActionOptions = [],
        icon: UNNotificationActionIcon? = nil,
        textInputButtonTitle: String,
        textInputPlaceholder: String
    ) {
        self.textInputButtonTitle = textInputButtonTitle
        self.textInputPlaceholder = textInputPlaceholder
        super.init(identifier: identifier, title: title, options: options, icon: icon)
    }
}

/// NSObject base gives identity hashing so `Set<UNNotificationCategory>` works.
public final class UNNotificationCategory: NSObject, @unchecked Sendable {
    public let identifier: String
    public let actions: [UNNotificationAction]
    public let intentIdentifiers: [String]
    public let hiddenPreviewsBodyPlaceholder: String
    public let categoryOptions: UNNotificationCategoryOptions
    public init(
        identifier: String,
        actions: [UNNotificationAction],
        intentIdentifiers: [String],
        options: UNNotificationCategoryOptions = []
    ) {
        self.identifier = identifier
        self.actions = actions
        self.intentIdentifiers = intentIdentifiers
        self.hiddenPreviewsBodyPlaceholder = ""
        self.categoryOptions = options
        super.init()
    }

    public init(
        identifier: String,
        actions: [UNNotificationAction],
        intentIdentifiers: [String],
        hiddenPreviewsBodyPlaceholder: String,
        options: UNNotificationCategoryOptions = []
    ) {
        self.identifier = identifier
        self.actions = actions
        self.intentIdentifiers = intentIdentifiers
        self.hiddenPreviewsBodyPlaceholder = hiddenPreviewsBodyPlaceholder
        self.categoryOptions = options
        super.init()
    }
}

// MARK: - Request / notification

public final class UNNotificationRequest: @unchecked Sendable {
    public let identifier: String
    public let content: UNNotificationContent
    public let trigger: UNNotificationTrigger?
    public init(identifier: String, content: UNNotificationContent, trigger: UNNotificationTrigger?) {
        self.identifier = identifier
        self.content = content
        self.trigger = trigger
    }
}

public final class UNNotification: @unchecked Sendable {
    public let request: UNNotificationRequest
    public let date: Date
    public init(request: UNNotificationRequest, date: Date = Date(timeIntervalSince1970: 0)) {
        self.request = request
        self.date = date
    }
}

public final class UNNotificationResponse: @unchecked Sendable {
    public let notification: UNNotification
    public let actionIdentifier: String

    public init(notification: UNNotification, actionIdentifier: String = "") {
        self.notification = notification
        self.actionIdentifier = actionIdentifier
    }
}

public final class UNNotificationSettings: @unchecked Sendable {
    public let authorizationStatus: UNAuthorizationStatus
    public init(authorizationStatus: UNAuthorizationStatus = .notDetermined) {
        self.authorizationStatus = authorizationStatus
    }
}

// MARK: - QuillKit mapping

private extension UNAuthorizationStatus {
    init(_ status: QuillNotificationAuthorizationStatus) {
        switch status {
        case .notDetermined:
            self = .notDetermined
        case .denied:
            self = .denied
        case .authorized:
            self = .authorized
        case .provisional:
            self = .provisional
        case .ephemeral:
            self = .ephemeral
        }
    }
}

private extension QuillNotificationRequestRecord {
    init(_ request: UNNotificationRequest) {
        self.init(
            identifier: request.identifier,
            title: request.content.title,
            subtitle: request.content.subtitle,
            body: request.content.body,
            categoryIdentifier: request.content.categoryIdentifier,
            threadIdentifier: request.content.threadIdentifier
        )
    }
}

// MARK: - Center

public protocol UNUserNotificationCenterDelegate: AnyObject {}

public final class UNUserNotificationCenter: @unchecked Sendable {
    private static let _shared = UNUserNotificationCenter()
    public static func current() -> UNUserNotificationCenter { _shared }

    public weak var delegate: UNUserNotificationCenterDelegate?
    private let lock = NSLock()
    private var categories: Set<UNNotificationCategory> = []
    private var pendingRequestsByIdentifier: [String: UNNotificationRequest] = [:]
    private var deliveredNotificationsByIdentifier: [String: UNNotification] = [:]

    public func requestAuthorization(options: UNAuthorizationOptions = []) async throws -> Bool {
        QuillNotificationService.shared.requestAuthorization(optionsRawValue: options.rawValue)
    }

    /// Callback-style variant (some call sites use the completion-handler form).
    public func requestAuthorization(
        options: UNAuthorizationOptions = [],
        completionHandler: @escaping (Bool, Error?) -> Void
    ) {
        completionHandler(QuillNotificationService.shared.requestAuthorization(optionsRawValue: options.rawValue), nil)
    }

    public func setNotificationCategories(_ categories: Set<UNNotificationCategory>) {
        lock.withLock {
            self.categories = categories
        }
        QuillNotificationService.shared.setCategories(Set(categories.map(\.identifier)))
    }

    public func setBadgeCount(_ count: Int) async throws {
        _ = count
    }

    public func setBadgeCount(_ count: Int, withCompletionHandler completionHandler: ((Error?) -> Void)? = nil) {
        _ = count
        completionHandler?(nil)
    }

    public func getNotificationCategories(completionHandler: @escaping (Set<UNNotificationCategory>) -> Void) {
        completionHandler(lock.withLock { categories })
    }

    public func notificationCategories() async -> Set<UNNotificationCategory> {
        lock.withLock { categories }
    }

    public func add(_ request: UNNotificationRequest) async throws {
        store(request)
    }

    public func add(
        _ request: UNNotificationRequest,
        withCompletionHandler completionHandler: ((Error?) -> Void)? = nil
    ) {
        store(request)
        completionHandler?(nil)
    }

    private func store(_ request: UNNotificationRequest) {
        let deliverImmediately = request.trigger == nil
        lock.withLock {
            if deliverImmediately {
                pendingRequestsByIdentifier.removeValue(forKey: request.identifier)
                deliveredNotificationsByIdentifier[request.identifier] = UNNotification(request: request, date: Date())
            } else {
                deliveredNotificationsByIdentifier.removeValue(forKey: request.identifier)
                pendingRequestsByIdentifier[request.identifier] = request
            }
        }
        QuillNotificationService.shared.addRequest(
            QuillNotificationRequestRecord(request),
            deliverImmediately: deliverImmediately
        )
    }

    public func getNotificationSettings(completionHandler: @escaping (UNNotificationSettings) -> Void) {
        completionHandler(UNNotificationSettings(
            authorizationStatus: UNAuthorizationStatus(QuillNotificationService.shared.authorizationStatus)
        ))
    }

    public func notificationSettings() async -> UNNotificationSettings {
        UNNotificationSettings(
            authorizationStatus: UNAuthorizationStatus(QuillNotificationService.shared.authorizationStatus)
        )
    }

    public func deliveredNotifications() async -> [UNNotification] {
        deliveredNotificationSnapshot()
    }

    public func getDeliveredNotifications(completionHandler: @escaping ([UNNotification]) -> Void) {
        completionHandler(deliveredNotificationSnapshot())
    }

    private func deliveredNotificationSnapshot() -> [UNNotification] {
        lock.withLock {
            deliveredNotificationsByIdentifier.values.sorted { lhs, rhs in
                lhs.request.identifier < rhs.request.identifier
            }
        }
    }

    public func pendingNotificationRequests() async -> [UNNotificationRequest] {
        pendingNotificationRequestSnapshot()
    }

    public func getPendingNotificationRequests(completionHandler: @escaping ([UNNotificationRequest]) -> Void) {
        completionHandler(pendingNotificationRequestSnapshot())
    }

    private func pendingNotificationRequestSnapshot() -> [UNNotificationRequest] {
        lock.withLock {
            pendingRequestsByIdentifier.values.sorted { $0.identifier < $1.identifier }
        }
    }

    public func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {
        lock.withLock {
            for identifier in identifiers {
                deliveredNotificationsByIdentifier.removeValue(forKey: identifier)
            }
        }
        QuillNotificationService.shared.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    public func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        lock.withLock {
            for identifier in identifiers {
                pendingRequestsByIdentifier.removeValue(forKey: identifier)
            }
        }
        QuillNotificationService.shared.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    public func removeAllDeliveredNotifications() {
        lock.withLock {
            deliveredNotificationsByIdentifier.removeAll()
        }
        QuillNotificationService.shared.removeAllDeliveredNotifications()
    }

    public func removeAllPendingNotificationRequests() {
        lock.withLock {
            pendingRequestsByIdentifier.removeAll()
        }
        QuillNotificationService.shared.removeAllPendingNotificationRequests()
    }
}
