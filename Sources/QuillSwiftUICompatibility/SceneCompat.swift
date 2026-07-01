import SwiftOpenUI

public extension Window {
    func windowStyle<S: WindowStyle>(_ style: S) -> Self {
        _ = style
        return self
    }
}
