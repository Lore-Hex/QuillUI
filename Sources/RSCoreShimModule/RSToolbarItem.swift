import AppKit

/// NetNewsWire's RSCore provides this AppKit helper on macOS. The Linux RSCore
/// shim exposes the same type so unmodified toolbar code can validate through
/// the responder chain.
public class RSToolbarItem: NSToolbarItem {
    override public func validate() {
        guard autovalidates else { return }
        guard view?.window != nil else {
            isEnabled = false
            return
        }

        if let validator = target as? NSUserInterfaceValidations {
            isEnabled = validator.validateUserInterfaceItem(self)
            return
        }

        var responder = view?.window?.firstResponder
        while let current = responder {
            if let validator = current as? NSUserInterfaceValidations {
                isEnabled = validator.validateUserInterfaceItem(self)
                return
            }
            responder = current.nextResponder
        }

        if let validator = NSApplication.shared.delegate as? NSUserInterfaceValidations {
            isEnabled = validator.validateUserInterfaceItem(self)
            return
        }

        isEnabled = false
    }
}
