/// A modifier that presents the iOS 18 limited-contacts access picker.
///
/// Mirrors ContactsUI's SwiftUI `View.contactAccessPicker(isPresented:completionHandler:)`.
/// On Linux there is no Contacts entitlement flow, so this is an inert wrapper:
/// it stores the binding + completion handler but never presents anything. It
/// exists so SignalUI's `ContactAccessLimitedReminderView` (gated `@available(iOS 18, *)`)
/// compiles unchanged.
public struct ContactAccessPickerModifierView<Content: View>: View, PrimitiveView {
    public typealias Body = Never

    public let content: Content
    public let isPresented: Binding<Bool>
    public let completionHandler: ([String]) -> Void

    public var body: Never { fatalError("ContactAccessPickerModifierView is a primitive view") }
}

extension View {
    /// Present the limited-contacts access picker when `isPresented` becomes true.
    /// The completion handler receives the identifiers of newly granted contacts.
    public func contactAccessPicker(
        isPresented: Binding<Bool>,
        completionHandler: @escaping ([String]) -> Void
    ) -> some View {
        ContactAccessPickerModifierView(
            content: self,
            isPresented: isPresented,
            completionHandler: completionHandler
        )
    }
}
