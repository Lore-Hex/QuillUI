/// A view that displays an icon alongside a text label.
public protocol AnyLabelView {
    var title: String { get }
    var systemImage: String? { get }
    var imagePath: String? { get }
}

public struct Label<Title: View, Icon: View>: View, AnyLabelView {
    public typealias Body = Never

    public let title: String
    public let systemImage: String?
    public let imagePath: String?
    public let titleView: Title?
    public let iconView: Icon?

    /// Create a label with a system icon name.
    public init(_ title: String, systemImage: String) where Title == Text, Icon == Image {
        self.title = quillResolveLocalizedString(title)
        self.systemImage = systemImage
        self.imagePath = nil
        self.titleView = nil
        self.iconView = nil
    }

    /// Create a label with an image file path.
    public init(_ title: String, image: String) where Title == Text, Icon == Image {
        self.title = quillResolveLocalizedString(title)
        self.systemImage = nil
        self.imagePath = image
        self.titleView = nil
        self.iconView = nil
    }

    public init<T>(_ title: T, systemImage: String) where Title == Text, Icon == Image {
        self.title = quillResolveLocalizedString(String(describing: title))
        self.systemImage = systemImage
        self.imagePath = nil
        self.titleView = nil
        self.iconView = nil
    }

    public init<T>(_ title: T, image: String) where Title == Text, Icon == Image {
        self.title = quillResolveLocalizedString(String(describing: title))
        self.systemImage = nil
        self.imagePath = image
        self.titleView = nil
        self.iconView = nil
    }

    public init(
        @ViewBuilder title: () -> Title,
        @ViewBuilder icon: () -> Icon
    ) {
        let titleView = title()
        let iconView = icon()
        self.title = (titleView as? Text)?.content ?? ""
        if let image = iconView as? Image {
            switch image.source {
            case .systemName(let name), .materialSymbol(let name):
                self.systemImage = name
                self.imagePath = nil
            case .filePath(let path):
                self.systemImage = nil
                self.imagePath = path
            }
        } else {
            self.systemImage = nil
            self.imagePath = nil
        }
        self.titleView = titleView
        self.iconView = iconView
    }

    public var body: Never { fatalError("Label is a primitive view") }
}
