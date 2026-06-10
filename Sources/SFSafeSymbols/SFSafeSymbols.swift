public struct SFSymbol: RawRepresentable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let allSymbols: [SFSymbol] = [
        "number",
        "at",
        "star",
        "heart",
        "bell",
        "bookmark",
        "tag",
        "person",
        "globe",
        "link",
        "list.bullet",
        "tray",
        "paperplane",
        "square.and.pencil",
        "photo",
        "gearshape",
    ].map(SFSymbol.init(rawValue:))
}
