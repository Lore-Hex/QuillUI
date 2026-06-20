/// Encoding used when SwiftUI-style inline images are interpolated into
/// `Text`, such as `Text("\(Image(systemName: "globe")) Public")`.
///
/// SwiftUI treats these as inline attachments. Swift string interpolation
/// falls back to `String(describing:)`, so SwiftOpenUI encodes a compact,
/// private marker that backends can replace with their native symbol renderer.
public enum QuillInlineImageText {
    public enum Kind: String {
        case systemName
        case material
        case filePath
    }

    public struct Token: Equatable {
        public let kind: Kind
        public let name: String

        public init(kind: Kind, name: String) {
            self.kind = kind
            self.name = name
        }
    }

    public enum Segment: Equatable {
        case text(String)
        case image(Token)
    }

    public static let markerStart = "\u{E000}"
    public static let markerEnd = "\u{E001}"

    public static func marker(systemName: String) -> String {
        marker(kind: .systemName, name: systemName)
    }

    public static func marker(materialName: String) -> String {
        marker(kind: .material, name: materialName)
    }

    public static func marker(filePath: String) -> String {
        marker(kind: .filePath, name: filePath)
    }

    public static func containsMarker(_ text: String) -> Bool {
        text.contains(markerStart)
    }

    public static func parse(_ text: String) -> [Segment] {
        var segments: [Segment] = []
        var cursor = text.startIndex

        while let startRange = text[cursor...].range(of: markerStart) {
            appendText(String(text[cursor..<startRange.lowerBound]), to: &segments)

            let payloadStart = startRange.upperBound
            guard let endRange = text[payloadStart...].range(of: markerEnd) else {
                appendText(String(text[startRange.lowerBound...]), to: &segments)
                return segments
            }

            let rawMarker = String(text[startRange.lowerBound..<endRange.upperBound])
            let payload = String(text[payloadStart..<endRange.lowerBound])
            if let separator = payload.firstIndex(of: ":") {
                let rawKind = String(payload[..<separator])
                let nameStart = payload.index(after: separator)
                let name = String(payload[nameStart...])
                if let kind = Kind(rawValue: rawKind), !name.isEmpty {
                    segments.append(.image(Token(kind: kind, name: name)))
                } else {
                    appendText(rawMarker, to: &segments)
                }
            } else {
                appendText(rawMarker, to: &segments)
            }

            cursor = endRange.upperBound
        }

        appendText(String(text[cursor...]), to: &segments)
        return segments
    }

    private static func marker(kind: Kind, name: String) -> String {
        guard !name.isEmpty,
              !name.contains(markerStart),
              !name.contains(markerEnd),
              !kind.rawValue.contains(":")
        else { return "" }
        return "\(markerStart)\(kind.rawValue):\(name)\(markerEnd)"
    }

    private static func appendText(_ text: String, to segments: inout [Segment]) {
        guard !text.isEmpty else { return }
        if case .text(let existing) = segments.last {
            segments[segments.count - 1] = .text(existing + text)
        } else {
            segments.append(.text(text))
        }
    }
}
