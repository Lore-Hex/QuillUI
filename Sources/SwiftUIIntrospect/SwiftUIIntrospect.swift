import SwiftUI

public extension View {
    func introspect<T>(_ type: T.Type, on platform: Any..., perform action: @escaping (T) -> Void) -> some View { self }
}
