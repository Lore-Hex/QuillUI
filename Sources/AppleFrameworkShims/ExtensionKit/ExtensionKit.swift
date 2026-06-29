import Foundation
import AppKit
import SwiftUI
import ExtensionFoundation

public protocol AppExtensionScene {}

extension Never: AppExtensionScene {}
extension Array: AppExtensionScene where Element: AppExtensionScene {}

public struct PrimitiveAppExtensionScene: AppExtensionScene {
    public let id: String

    public init<Content: View>(id: String, @ViewBuilder content: () -> Content) {
        self.id = id
        _ = content()
    }

    public init<Content: View>(
        id: String,
        @ViewBuilder content: () -> Content,
        onConnection: (NSXPCConnection) -> Bool
    ) {
        self.id = id
        _ = content()
        _ = onConnection
    }
}

public struct AppExtensionSceneConfiguration: AppExtensionConfiguration {
    public init<Scene: AppExtensionScene, Configuration: AppExtensionConfiguration>(
        _ scene: Scene,
        configuration: Configuration
    ) {
        _ = (scene, configuration)
    }
}

public struct TupleAppExtensionScene<Content>: AppExtensionScene {
    public let content: Content

    public init(_ content: Content) {
        self.content = content
    }
}

@resultBuilder
public enum AppExtensionSceneBuilder {
    public static func buildBlock<Content: AppExtensionScene>(_ content: Content) -> Content {
        content
    }

    public static func buildBlock<First: AppExtensionScene, Second: AppExtensionScene>(
        _ first: First,
        _ second: Second
    ) -> TupleAppExtensionScene<(First, Second)> {
        TupleAppExtensionScene((first, second))
    }
}

open class EXAppExtensionBrowserViewController: NSViewController {}

public protocol EXHostViewControllerDelegate: AnyObject {
    func hostViewControllerWillDeactivate(_ viewController: EXHostViewController, error: Error?)
    func hostViewControllerDidActivate(_ viewController: EXHostViewController)
}

public extension EXHostViewControllerDelegate {
    func hostViewControllerWillDeactivate(_ viewController: EXHostViewController, error: Error?) {
        _ = (viewController, error)
    }

    func hostViewControllerDidActivate(_ viewController: EXHostViewController) {
        _ = viewController
    }
}

open class EXHostViewController: NSViewController {
    public struct Configuration: Sendable {
        public var appExtension: AppExtensionIdentity
        public var sceneID: String

        public init(appExtension: AppExtensionIdentity, sceneID: String) {
            self.appExtension = appExtension
            self.sceneID = sceneID
        }
    }

    public weak var delegate: EXHostViewControllerDelegate?
    public var configuration: Configuration? {
        didSet {
            delegate?.hostViewControllerDidActivate(self)
        }
    }

    nonisolated public func makeXPCConnection() throws -> NSXPCConnection {
        let serviceName = MainActor.assumeIsolated {
            configuration?.appExtension.bundleIdentifier ?? ""
        }
        return NSXPCConnection(serviceName: serviceName)
    }
}
