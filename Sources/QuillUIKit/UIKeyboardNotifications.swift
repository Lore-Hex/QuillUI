//===----------------------------------------------------------------------===//
//
//  UIKeyboardNotifications.swift
//  QuillUIKit — UIResponder's keyboard notification surface for Linux
//
//  Apple's UIResponder keyboard statics: the six show/hide/change-frame
//  notification names plus the five userInfo keys, with the exact ObjC raw
//  values (UIKeyboardWillShowNotification, ...) so string round-trips match
//  Apple. Same honest-Linux contract as the UIMenuController notifications
//  (UIEventsMenus.swift): names only — there is no on-screen keyboard on
//  QuillOS, so nothing posts these today. Signal's view controllers register
//  observers for them (AttachmentApprovalViewController et al.); a future
//  input backend posts them with the userInfo keys below.
//
//===----------------------------------------------------------------------===//

import Foundation
import QuillFoundation

#if !os(iOS)

extension UIResponder {
    // MARK: Keyboard notification names

    public static let keyboardWillShowNotification = Notification.Name("UIKeyboardWillShowNotification")
    public static let keyboardDidShowNotification = Notification.Name("UIKeyboardDidShowNotification")
    public static let keyboardWillHideNotification = Notification.Name("UIKeyboardWillHideNotification")
    public static let keyboardDidHideNotification = Notification.Name("UIKeyboardDidHideNotification")
    public static let keyboardWillChangeFrameNotification = Notification.Name("UIKeyboardWillChangeFrameNotification")
    public static let keyboardDidChangeFrameNotification = Notification.Name("UIKeyboardDidChangeFrameNotification")

    // MARK: Keyboard userInfo keys

    /// CGRect (as NSValue on Apple): keyboard frame at animation start.
    public static let keyboardFrameBeginUserInfoKey = "UIKeyboardFrameBeginUserInfoKey"
    /// CGRect (as NSValue on Apple): keyboard frame at animation end.
    public static let keyboardFrameEndUserInfoKey = "UIKeyboardFrameEndUserInfoKey"
    /// TimeInterval (as NSNumber on Apple): animation duration in seconds.
    public static let keyboardAnimationDurationUserInfoKey = "UIKeyboardAnimationDurationUserInfoKey"
    /// UIView.AnimationCurve raw value (as NSNumber on Apple).
    public static let keyboardAnimationCurveUserInfoKey = "UIKeyboardAnimationCurveUserInfoKey"
    /// Bool (as NSNumber on Apple): whether the keyboard belongs to this app.
    public static let keyboardIsLocalUserInfoKey = "UIKeyboardIsLocalUserInfoKey"
}

#endif // !os(iOS)
