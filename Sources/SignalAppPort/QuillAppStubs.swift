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

class CallService {}
class SignalCall {}
struct CallStarter {}
struct CallLink {}

// MARK: - Donations (pruned: needs PassKit/StoreKit donation flow)

class DonateViewController: UIViewController {}

// MARK: - App shell / misc subsystems pruned for the render slice

class ConversationSplitViewController: UIViewController {}
class CameraCaptureSession {}
class ProvisioningManager {}
class QuickRestoreManager {}
struct DeviceProvisioningURL {}
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
class LocationPicker: UIViewController {}
protocol LocationPickerDelegate: AnyObject {}
struct Location {}

// MARK: - Calling glue still referenced from kept code (Calls/ pruned)

protocol CallServiceStateObserver: AnyObject {}
class CallViewControllerWindowReference {}
struct CallTarget {}
class CallLinkProfileKeySharingManager {}

// MARK: - Generated-asset + Foundation typealiases corelibs lacks

public typealias NSInteger = Int
struct ImageResource {}
