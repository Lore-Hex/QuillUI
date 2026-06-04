//
// QuillUI Linux shim for `Intents` (SiriKit).
//
// SignalServiceKit donates INInteraction/INSendMessageIntent/INStartCallIntent
// for system intent suggestions (Siri, share sheet, notification avatars). The
// Intents framework is unavailable on Linux, so these are inert value-holders:
// constructors store nothing and `donate()` is a no-op. The surface mirrors the
// exact initializers and members SSK constructs so the upstream Swift compiles.
//
// Part of the Signal-iOS -> QuillOS port. Behavior deferred.
//
import Foundation

// MARK: - Base intent + response

open class INIntent: NSObject {}

open class INIntentResponse: NSObject {}

// MARK: - INInteraction (donation)

public final class INInteraction: NSObject {
    public let intent: INIntent
    public let response: INIntentResponse?

    public init(intent: INIntent, response: INIntentResponse?) {
        self.intent = intent
        self.response = response
        super.init()
    }

    /// On iOS this registers the interaction with the system. Inert on Linux.
    public func donate(completion: ((Error?) -> Void)? = nil) {
        completion?(nil)
    }

    /// Async form. Inert on Linux (never throws).
    public func donate() async throws {}
}

public enum INInteractionDirection: Int, Sendable {
    case unspecified
    case outgoing
    case incoming
}

// MARK: - Person

public enum INPersonHandleType: Int, Sendable {
    case unknown
    case emailAddress
    case phoneNumber
}

/// On iOS a RawRepresentable String wrapper; opaque here (SSK only passes nil).
public struct INPersonHandleLabel: RawRepresentable, Sendable, Equatable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

public final class INPersonHandle: NSObject {
    public let value: String?
    public let type: INPersonHandleType
    public let label: INPersonHandleLabel?

    public init(value: String?, type: INPersonHandleType, label: INPersonHandleLabel? = nil) {
        self.value = value
        self.type = type
        self.label = label
        super.init()
    }
}

public enum INPersonSuggestionType: Int, Sendable {
    case none
    case socialProfile
    case instantMessageAddress
}

public final class INImage: NSObject {
    public init(imageData: Data) { super.init() }
    public init(named name: String) { super.init() }
}

public final class INPerson: NSObject {
    public let personHandle: INPersonHandle?
    public let nameComponents: PersonNameComponents?
    public let displayName: String?
    public let image: INImage?
    public let contactIdentifier: String?
    public let customIdentifier: String?
    public let isMe: Bool
    public let suggestionType: INPersonSuggestionType

    public init(personHandle: INPersonHandle?,
                nameComponents: PersonNameComponents?,
                displayName: String?,
                image: INImage?,
                contactIdentifier: String?,
                customIdentifier: String?,
                isMe: Bool,
                suggestionType: INPersonSuggestionType) {
        self.personHandle = personHandle
        self.nameComponents = nameComponents
        self.displayName = displayName
        self.image = image
        self.contactIdentifier = contactIdentifier
        self.customIdentifier = customIdentifier
        self.isMe = isMe
        self.suggestionType = suggestionType
        super.init()
    }
}

public final class INSpeakableString: NSObject {
    public let spokenPhrase: String
    public init(spokenPhrase: String) {
        self.spokenPhrase = spokenPhrase
        super.init()
    }
}

// MARK: - Send-message intent

public enum INOutgoingMessageType: Int, Sendable {
    case unknown
    case outgoingMessageText
    case outgoingMessageAudio
}

open class INSendMessageAttachment: NSObject {}

public final class INSendMessageIntentDonationMetadata: NSObject {
    public var recipientCount: Int = 0
    public var mentionsCurrentUser: Bool = false
    public var isReplyToCurrentUser: Bool = false
    public override init() { super.init() }
}

public final class INSendMessageIntent: INIntent {
    public var recipients: [INPerson]?
    public var outgoingMessageType: INOutgoingMessageType
    public var content: String?
    public var speakableGroupName: INSpeakableString?
    public var conversationIdentifier: String?
    public var serviceName: String?
    public var sender: INPerson?
    public var attachments: [INSendMessageAttachment]?
    public var donationMetadata: INSendMessageIntentDonationMetadata?

    public init(recipients: [INPerson]?,
                outgoingMessageType: INOutgoingMessageType,
                content: String?,
                speakableGroupName: INSpeakableString?,
                conversationIdentifier: String?,
                serviceName: String?,
                sender: INPerson?,
                attachments: [INSendMessageAttachment]?) {
        self.recipients = recipients
        self.outgoingMessageType = outgoingMessageType
        self.content = content
        self.speakableGroupName = speakableGroupName
        self.conversationIdentifier = conversationIdentifier
        self.serviceName = serviceName
        self.sender = sender
        self.attachments = attachments
        super.init()
    }

    /// Mirrors INIntent.setImage(_:forParameterNamed:) (key-path form). Inert.
    public func setImage<Value>(_ image: INImage?, forParameterNamed keyPath: KeyPath<INSendMessageIntent, Value>) {}
}

// MARK: - Start-call intent

open class INCallRecordFilter: NSObject {}
open class INCallRecord: NSObject {}

public enum INCallAudioRoute: Int, Sendable {
    case unknown
    case speakerphoneAudioRoute
    case bluetoothAudioRoute
}

public enum INCallDestinationType: Int, Sendable {
    case unknown
    case normal
    case video
    case emergency
    case voicemail
}

public enum INCallCapability: Int, Sendable {
    case unknown
    case audioCall
    case videoCall
}

public final class INStartCallIntent: INIntent {
    public let callRecordFilter: INCallRecordFilter?
    public let callRecordToCallBack: INCallRecord?
    public let audioRoute: INCallAudioRoute
    public let destinationType: INCallDestinationType
    public let contacts: [INPerson]?
    public let callCapability: INCallCapability

    public init(callRecordFilter: INCallRecordFilter?,
                callRecordToCallBack: INCallRecord?,
                audioRoute: INCallAudioRoute,
                destinationType: INCallDestinationType,
                contacts: [INPerson]?,
                callCapability: INCallCapability) {
        self.callRecordFilter = callRecordFilter
        self.callRecordToCallBack = callRecordToCallBack
        self.audioRoute = audioRoute
        self.destinationType = destinationType
        self.contacts = contacts
        self.callCapability = callCapability
        super.init()
    }
}
