/// A control that toggles between on and off states.
public struct Toggle: View {
    public typealias Body = Never

    public let label: String
    public let isOn: Binding<Bool>

    public init(_ label: String = "", isOn: Binding<Bool>) {
        self.label = label
        self.isOn = isOn
    }

    public init<Label: View>(isOn: Binding<Bool>, @ViewBuilder label: () -> Label) {
        let builtLabel = label()
        if let text = builtLabel as? Text {
            self.label = text.content
        } else {
            self.label = ""
        }
        self.isOn = isOn
    }

    public var body: Never { fatalError("Toggle is a primitive view") }
}
