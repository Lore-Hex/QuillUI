@_exported import UIKit
@_exported import QuillRSCoreShim

public typealias RSImage = UIImage
public typealias RSScreen = UIScreen

public extension RSImage {
    convenience init?(systemSymbolName symbolName: String, accessibilityDescription: String?) {
        _ = accessibilityDescription
        self.init(systemName: symbolName)
    }

    func tinted(color: UIColor) -> RSImage? {
        withTintColor(color)
    }

    func withTintColor(_ color: UIColor, renderingMode: UIImage.RenderingMode) -> RSImage {
        _ = renderingMode
        return withTintColor(color)
    }
}

public extension UIColor {
    convenience init?(named name: String) {
        let color = Self.quillNamedColor(name)
        self.init(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
    }

    static var systemPurple: UIColor { UIColor(red: 0.69, green: 0.32, blue: 0.87, alpha: 1) }
    static var systemTeal: UIColor { UIColor(red: 0.35, green: 0.78, blue: 0.98, alpha: 1) }
    static var systemBrown: UIColor { UIColor(red: 0.64, green: 0.52, blue: 0.37, alpha: 1) }
    static var systemIndigo: UIColor { UIColor(red: 0.35, green: 0.34, blue: 0.84, alpha: 1) }

    private static func quillNamedColor(_ name: String) -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        switch name {
        case "primaryAccentColor":
            return (0.00, 0.48, 1.00, 1)
        case "secondaryAccentColor":
            return (0.32, 0.34, 0.90, 1)
        case "starColor":
            return (1.00, 0.68, 0.16, 1)
        case "vibrantTextColor":
            return (0.12, 0.12, 0.13, 1)
        case "controlBackgroundColor":
            return (0.94, 0.94, 0.96, 1)
        case "iconBackgroundColor":
            return (0.88, 0.89, 0.91, 1)
        case "fullScreenBackgroundColor":
            return (0.98, 0.98, 0.99, 1)
        case "sectionHeaderColor":
            return (0.56, 0.56, 0.58, 1)
        default:
            return (0.00, 0.48, 1.00, 1)
        }
    }
}
