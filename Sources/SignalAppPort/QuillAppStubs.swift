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
