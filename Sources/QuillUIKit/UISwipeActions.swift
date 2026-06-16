import Foundation
import QuillFoundation
import CoreGraphics

/// A single action shown when a table-view (or collection-view) row is swiped.
///
/// Mirrors the public shape of UIKit's `UIContextualAction`. On Linux there is
/// no live UIKit runtime, so the stored `handler` is retained but never invoked
/// automatically by the framework.
@MainActor
open class UIContextualAction {

    /// The visual style of the action, which influences its default appearance.
    public enum Style: Int {
        case normal
        case destructive
    }

    /// The block executed when the user selects the action.
    ///
    /// Parameters mirror UIKit: the action itself, the source view in which the
    /// action is displayed, and a completion handler the receiver invokes with
    /// `true` if the action was performed or `false` if it was not.
    public typealias Handler = @MainActor (UIContextualAction, UIView, @escaping (Bool) -> Void) -> Void

    private let _style: Style
    private let _handler: Handler

    /// The style that applies to the action's button.
    public var style: Style { _style }

    /// The block executed when the user selects this action.
    public var handler: Handler { _handler }

    /// The title displayed on the action's button.
    public var title: String?

    /// The image displayed on the action's button.
    public var image: UIImage?

    /// The background color of the action's button.
    ///
    /// UIKit always provides a non-nil default, so this is implicitly unwrapped.
    public var backgroundColor: UIColor! = UIColor(white: 0.5, alpha: 1.0)
    public var accessibilityLabel: String?

    /// Creates a new contextual action with the specified title and behavior.
    public init(style: Style, title: String?, handler: @escaping Handler) {
        self._style = style
        self.title = title
        self._handler = handler
    }
}

/// The set of actions to perform when swiping a table-view or collection-view row.
///
/// Mirrors the public shape of UIKit's `UISwipeActionsConfiguration`.
@MainActor
open class UISwipeActionsConfiguration {

    private let _actions: [UIContextualAction]

    /// The swipe actions, in the order they should be displayed.
    public var actions: [UIContextualAction] { _actions }

    /// A Boolean value indicating whether a full swipe automatically performs
    /// the first action. Defaults to `true`, matching UIKit.
    public var performsFirstActionWithFullSwipe: Bool = true

    /// Creates a swipe-actions configuration from the specified actions.
    public init(actions: [UIContextualAction]) {
        self._actions = actions
    }
}
