//
// QuillUI Linux shim for Apple's Contacts framework.
//
// Signal's SignalServiceKit uses Contacts value types to import/export system
// contacts and serialize vCards (CNContact, CNLabeledValue, CNPhoneNumber,
// CNPostalAddress, …). Linux has no system address book, so CNContactStore
// access is DEFERRED (returns empty / .denied). The value types are real so
// Signal can construct and read them (the vCard / sharing paths operate on data
// Signal already holds). Surface matches Apple's Contacts API; extend as new
// call sites appear.
//
// Note: Apple's CNContact/CNPostalAddress are immutable with CNMutable*
// subclasses for mutation. Here the bases expose settable vars and the mutable
// subclasses are thin — Signal only mutates through the CNMutable* types, so
// behavior matches; the looser base mutability is harmless.
//
import Foundation

// MARK: - Key descriptors

public protocol CNKeyDescriptor {}
extension String: CNKeyDescriptor {}
extension NSString: CNKeyDescriptor {}

public let CNContactGivenNameKey = "givenName"
public let CNContactFamilyNameKey = "familyName"
public let CNContactMiddleNameKey = "middleName"
public let CNContactNamePrefixKey = "namePrefix"
public let CNContactNameSuffixKey = "nameSuffix"
public let CNContactNicknameKey = "nickname"
public let CNContactOrganizationNameKey = "organizationName"
public let CNContactPhoneNumbersKey = "phoneNumbers"
public let CNContactEmailAddressesKey = "emailAddresses"
public let CNContactPostalAddressesKey = "postalAddresses"
public let CNContactImageDataKey = "imageData"
public let CNContactThumbnailImageDataKey = "thumbnailImageData"
public let CNContactImageDataAvailableKey = "imageDataAvailable"
public let CNContactIdentifierKey = "identifier"
public let CNContactPropertyAttribute = "CNContactPropertyAttribute"

// MARK: - Labels

public let CNLabelHome = "_$!<Home>!$_"
public let CNLabelWork = "_$!<Work>!$_"
public let CNLabelOther = "_$!<Other>!$_"
public let CNLabelEmailiCloud = "iCloud"
public let CNLabelURLAddressHomePage = "_$!<HomePage>!$_"
public let CNLabelPhoneNumberMobile = "_$!<Mobile>!$_"
public let CNLabelPhoneNumberiPhone = "iPhone"
public let CNLabelPhoneNumberMain = "_$!<Main>!$_"
public let CNLabelPhoneNumberHomeFax = "_$!<HomeFAX>!$_"
public let CNLabelPhoneNumberWorkFax = "_$!<WorkFAX>!$_"
public let CNLabelPhoneNumberOtherFax = "_$!<OtherFAX>!$_"
public let CNLabelPhoneNumberPager = "_$!<Pager>!$_"

// MARK: - Value types

public class CNPhoneNumber: NSObject {
    public let stringValue: String
    public init(stringValue: String) {
        self.stringValue = stringValue
        super.init()
    }
}

public class CNPostalAddress: NSObject {
    public var street = ""
    public var subLocality = ""
    public var city = ""
    public var subAdministrativeArea = ""
    public var state = ""
    public var postalCode = ""
    public var country = ""
    public var isoCountryCode = ""
    public override init() { super.init() }
}

public final class CNMutablePostalAddress: CNPostalAddress {}

public class CNLabeledValue<ValueType> {
    public let label: String?
    public let value: ValueType
    public init(label: String?, value: ValueType) {
        self.label = label
        self.value = value
    }

    /// The localized, user-visible name for a label (e.g. CNLabelHome -> "home").
    /// On iOS Contacts localizes the canonical `_$!<Home>!$_` tokens; on Linux we
    /// return the label string unchanged (best-effort, no Contacts localization).
    public static func localizedString(forLabel label: String) -> String { label }
}

public class CNContact: NSObject {
    public var identifier: String = UUID().uuidString
    public var givenName = ""
    public var familyName = ""
    public var middleName = ""
    public var namePrefix = ""
    public var nameSuffix = ""
    public var nickname = ""
    public var organizationName = ""
    public var phoneNumbers: [CNLabeledValue<CNPhoneNumber>] = []
    public var emailAddresses: [CNLabeledValue<NSString>] = []
    public var postalAddresses: [CNLabeledValue<CNPostalAddress>] = []
    public var imageData: Data?
    public var thumbnailImageData: Data?
    public var imageDataAvailable = false

    public override init() { super.init() }

    public func isKeyAvailable(_ key: CNKeyDescriptor) -> Bool { true }
    public func areKeysAvailable(_ keys: [CNKeyDescriptor]) -> Bool { true }

    // Fetch predicates. Inert on Linux (no system address book) -> match nothing.
    public static func predicateForContacts(withIdentifiers identifiers: [String]) -> NSPredicate {
        _ = identifiers
        return NSPredicate(value: false)
    }
    public static func predicateForContacts(matchingName name: String) -> NSPredicate {
        _ = name
        return NSPredicate(value: false)
    }
}

public final class CNMutableContact: CNContact {}

// MARK: - Formatting / serialization

public enum CNContactFormatterStyle: Sendable { case fullName, phoneticFullName }

public class CNContactFormatter {
    public init() {}
    public var style: CNContactFormatterStyle = .fullName

    public func string(from contact: CNContact) -> String? {
        CNContactFormatter.string(from: contact, style: .fullName)
    }

    public static func string(from contact: CNContact, style: CNContactFormatterStyle) -> String? {
        let parts = [contact.givenName, contact.familyName].filter { !$0.isEmpty }
        if parts.isEmpty {
            return contact.organizationName.isEmpty ? nil : contact.organizationName
        }
        return parts.joined(separator: " ")
    }

    public static func attributedString(
        from contact: CNContact,
        style: CNContactFormatterStyle,
        defaultAttributes attributes: [NSAttributedString.Key: Any]?
    ) -> NSAttributedString? {
        guard let value = string(from: contact, style: style) else { return nil }
        return NSAttributedString(string: value, attributes: attributes)
    }

    public static func descriptorForRequiredKeys(for style: CNContactFormatterStyle) -> CNKeyDescriptor {
        CNContactGivenNameKey
    }
}

public class CNPostalAddressFormatter {
    public enum Style: Sendable {
        case mailingAddress
    }

    public var style: Style = .mailingAddress

    public init() {}

    public func string(from postalAddress: CNPostalAddress) -> String {
        [postalAddress.street, postalAddress.city, postalAddress.state, postalAddress.postalCode, postalAddress.country]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

public enum CNContactVCardSerialization {
    // Real vCard (de)serialization is deferred; Signal's own contact model is
    // the source of truth on Linux.
    public static func data(with contacts: [CNContact]) throws -> Data { Data() }
    public static func contacts(with data: Data) throws -> [CNContact] { [] }
    public static func descriptorForRequiredKeys() -> CNKeyDescriptor { CNContactIdentifierKey }
}

// ContactsUI's CNContactViewController (SSK only needs the required-keys
// descriptor). The view controller itself is not presented on Linux.
public class CNContactViewController {
    public static func descriptorForRequiredKeys() -> CNKeyDescriptor { CNContactIdentifierKey }
    public init() {}
}

public extension NSNotification.Name {
    static let CNContactStoreDidChange = NSNotification.Name("CNContactStoreDidChangeNotification")
}

// MARK: - Store (system access deferred on Linux)

public enum CNEntityType: Sendable { case contacts }

public enum CNAuthorizationStatus: Int, Sendable {
    case notDetermined = 0
    case restricted = 1
    case denied = 2
    case authorized = 3
    case limited = 4
}

public struct CNErrorCode: RawRepresentable, Equatable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let communicationError = CNErrorCode(rawValue: 1)
    public static let dataAccessError = CNErrorCode(rawValue: 2)
}

public struct CNError: Error {
    public let code: CNErrorCode
    public init(_ code: CNErrorCode = .dataAccessError) { self.code = code }

    // On Apple `CNError.communicationError` is the bridged-error pattern; SSK uses
    // it in `catch CNError.communicationError` / `case CNError.communicationError`.
    // Provide the value + an expression-pattern operator so both type-check (the
    // inert store never actually throws CNError, so this is compile-only).
    public static let communicationError = CNError(.communicationError)
    public static func ~= (pattern: CNError, error: any Error) -> Bool {
        (error as? CNError)?.code == pattern.code
    }
}

public class CNContactFetchRequest {
    public var keysToFetch: [CNKeyDescriptor]
    public var sortOrder: CNContactSortOrder = .userDefault
    public var predicate: NSPredicate?
    public init(keysToFetch: [CNKeyDescriptor]) { self.keysToFetch = keysToFetch }
}

public class CNContactStore {
    public init() {}

    public static func authorizationStatus(for entityType: CNEntityType) -> CNAuthorizationStatus {
        .denied
    }

    public func requestAccess(for entityType: CNEntityType,
                              completionHandler: @escaping (Bool, Error?) -> Void) {
        completionHandler(false, nil)
    }

    public func enumerateContacts(with fetchRequest: CNContactFetchRequest,
                                  usingBlock block: (CNContact, UnsafeMutablePointer<ObjCBool>) -> Void) throws {
        // No system address book on Linux.
    }

    public func unifiedContacts(matching predicate: NSPredicate,
                                keysToFetch keys: [CNKeyDescriptor]) throws -> [CNContact] {
        []
    }

    public func unifiedContact(withIdentifier identifier: String,
                               keysToFetch keys: [CNKeyDescriptor]) throws -> CNContact {
        throw CNError(.dataAccessError)
    }

    /// Commits a batch of contact mutations. Inert on Linux (no system address
    /// book): the request's queued add/update/delete operations are dropped and
    /// the call succeeds. SignalUI: DeleteSystemContactViewController executes a
    /// delete request here.
    public func execute(_ saveRequest: CNSaveRequest) throws {
        _ = saveRequest
    }
}

// MARK: - CNSaveRequest
//
// Accumulates contact mutations to be committed by CNContactStore.execute(_:).
// On Linux nothing is persisted (there is no system Contacts store), so the
// queued operations are recorded but never applied; the type exists so the
// upstream batch-edit code (DeleteSystemContactViewController) compiles.
public class CNSaveRequest: NSObject {
    public override init() { super.init() }

    public func add(_ contact: CNMutableContact, toContainerWithIdentifier identifier: String?) {
        _ = (contact, identifier)
    }

    public func update(_ contact: CNMutableContact) {
        _ = contact
    }

    public func delete(_ contact: CNMutableContact) {
        _ = contact
    }
}

// MARK: - CNContactsUserDefaults

public enum CNContactSortOrder: Int, Sendable {
    case none = 0
    case userDefault = 1
    case givenName = 2
    case familyName = 3
}

/// The Contacts.app sort-order / country preference. Inert on Linux (there is no
/// system Contacts store): reports a sensible default (sort by given name).
public final class CNContactsUserDefaults: @unchecked Sendable {
    private static let _shared = CNContactsUserDefaults()
    public static func shared() -> CNContactsUserDefaults { _shared }
    public var sortOrder: CNContactSortOrder = .givenName
    public var countryCode: String = "us"
    public init() {}
}
