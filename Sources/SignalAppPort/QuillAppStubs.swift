// QuillAppStubs.swift — Linux stand-ins for Signal app types whose defining
// files live in iOS-only subsystems pruned from the conversation-rendering slice
// (calling, donations, device transfer, the iPad split-view shell). They exist so
// the kept conversation/message code resolves and compiles; none of them is
// instantiated on the render path. Started empty and grown member-by-member as the
// build reports "has no member" — kept deliberately minimal.
//
// Symlinked into the disposable .upstream app tree's QuillPort/ by
// quill-signal-prep-app.sh so the canonical app source stays untouched.

import Foundation
import UIKit
import SignalServiceKit
import SignalUI

// MARK: - Calling (Calls/ pruned: needs WebRTC/CallKit)

class CallService {
    let callServiceState = CallServiceState()
}

class CallServiceState {
    var currentCall: SignalCall?

    func addObserver(_ observer: CallServiceStateObserver, syncStateImmediately: Bool) {
        _ = observer
        _ = syncStateImmediately
    }
}

class SignalCall {
    enum Mode {
        case groupThread(Data)
        case other

        func matches(_ other: Mode) -> Bool {
            switch (self, other) {
            case let (.groupThread(lhs), .groupThread(rhs)):
                return lhs == rhs
            case (.other, .other):
                return true
            default:
                return false
            }
        }
    }

    var mode: Mode = .other
}
struct CallStarter {}
struct CallLink: Equatable {
    let url: URL?

    init() {
        self.url = nil
    }

    init?(url: URL) {
        self.url = url
    }
}

// MARK: - Donations (pruned: needs PassKit/StoreKit donation flow)

class DonateViewController: UIViewController {
    enum PreferredDonateMode {
        case oneTime
    }

    enum FinishResult {
        case completedDonation(UIViewController, DonationReceiptCredentialResultStore.Mode)
        case monthlySubscriptionCancelled(UIViewController, String)
    }

    init(
        preferredDonateMode: PreferredDonateMode,
        completion: @escaping (FinishResult) -> Void
    ) {
        _ = preferredDonateMode
        _ = completion
        super.init()
    }

    required init?(coder: NSCoder) {
        nil
    }
}

// MARK: - App shell / misc subsystems pruned for the render slice

class ConversationSplitViewController: UIViewController {}
class CameraCaptureSession {}
class ProvisioningManager {}
class QuickRestoreManager {}
struct DeviceProvisioningURL {
    enum LinkType {
        case linkDevice
        case quickRestore
    }

    let linkType: LinkType

    init?(urlString: String) {
        linkType = urlString.contains("quick") ? .quickRestore : .linkDevice
    }
}
class BackupAttachmentDownloadTracker {}

// MARK: - Push / debug / device-transfer / backups / quick-restore services
// (defining files pruned: they import PushKit / CocoaLumberjack / Multipeer /
//  BackgroundTasks, or live under the pruned Backups/DeviceTransfer/QuickRestore
//  subsystems). Empty stand-ins; members grown build-driven where still referenced.

class PushRegistrationManager {}
class DebugLogDumper {}
enum DebugLogs {}
class BackupAttachmentUploadTracker {}
class BackupSettingsViewController: UIViewController {}
class BackupEnablingManager {}
class BackupDisablingManager {}
class DeviceTransferService {}
protocol DeviceTransferServiceProtocol {}
class DeviceTransferCoordinator {}
class DeviceTransferStatusViewController: UIViewController {}
class OutgoingDeviceRestorePresenter {}
class BaseQuickRestoreQRCodeViewController: UIViewController {}
class EnterAccountEntropyPoolViewController: UIViewController {}
class CapturePreviewView: UIView {}
class LocationPicker: UIViewController {
    weak var delegate: LocationPickerDelegate?
}

protocol LocationPickerDelegate: AnyObject {
    func didPickLocation(_ locationPicker: LocationPicker, location: Location)
    func locationPickerDidCancel()
}

extension LocationPickerDelegate {
    func didPickLocation(_ locationPicker: LocationPicker, location: Location) {
        _ = locationPicker
        _ = location
    }

    func locationPickerDidCancel() {}
}

struct Location {
    func prepareAttachment() async throws -> SendableAttachment {
        throw NSError(domain: "QuillSignalLocation", code: 1)
    }
}

// MARK: - Calling glue still referenced from kept code (Calls/ pruned)

protocol CallServiceStateObserver: AnyObject {}
class CallViewControllerWindowReference {}
struct CallTarget {}
class CallLinkProfileKeySharingManager {}

// MARK: - Generated-asset + Foundation typealiases corelibs lacks

public typealias NSInteger = Int
struct ImageResource {}

extension UIImage {
    static var check: UIImage { UIImage(named: "check") ?? UIImage() }
    static var pinSlash: UIImage { UIImage(named: "pin-slash") ?? UIImage() }
    static var pin: UIImage { UIImage(named: "pin") ?? UIImage() }
    static var pinFill: UIImage { UIImage(named: "pin-fill") ?? UIImage() }
    static var chatArrow: UIImage { UIImage(named: "chat-arrow") ?? UIImage() }
    static var listBullet: UIImage { UIImage(named: "list-bullet") ?? UIImage() }
    static var personQuestionmarkCompact: UIImage { UIImage(named: "person-questionmark-compact") ?? UIImage() }
    static var groupQuestionmarkCompact: UIImage { UIImage(named: "group-questionmark-compact") ?? UIImage() }
    static var tag22: UIImage { UIImage(named: "tag-22") ?? UIImage() }
}

extension Optional where Wrapped == UIImage {
    static var check: UIImage? { UIImage.check }
    static var pinSlash: UIImage? { UIImage.pinSlash }
    static var pin: UIImage? { UIImage.pin }
    static var pinFill: UIImage? { UIImage.pinFill }
    static var chatArrow: UIImage? { UIImage.chatArrow }
    static var listBullet: UIImage? { UIImage.listBullet }
    static var personQuestionmarkCompact: UIImage? { UIImage.personQuestionmarkCompact }
    static var groupQuestionmarkCompact: UIImage? { UIImage.groupQuestionmarkCompact }
    static var tag22: UIImage? { UIImage.tag22 }
}
