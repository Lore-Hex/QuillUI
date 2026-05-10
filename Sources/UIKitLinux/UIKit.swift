@_exported import Foundation
@_exported import QuillKit

public typealias CGFloat = Double
public final class UIScreen: NSObject, @unchecked Sendable {
    @MainActor public static let main = UIScreen()
    public let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
}
public class UIResponder: NSObject, @unchecked Sendable {}
public class UIView: UIResponder {
    public override init() {}
}
public class UIViewController: UIResponder {
    public override init() {}
    public var view = UIView()
}
public class UISplitViewController: UIViewController {
    public enum DisplayMode: Int { case oneBesideSecondary = 0 }
    public var preferredDisplayMode: DisplayMode = .oneBesideSecondary
}
