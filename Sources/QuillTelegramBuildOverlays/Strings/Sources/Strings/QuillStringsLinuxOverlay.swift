#if os(Linux)
import Foundation

struct QuillStringEnumerationOptions {
    fileprivate enum Kind {
        case byWords
    }

    fileprivate let kind: Kind

    static let byWords = QuillStringEnumerationOptions(kind: .byWords)
}

extension String {
    func enumerateSubstrings(
        in range: Range<String.Index>,
        options: QuillStringEnumerationOptions,
        _ body: (String?, Range<String.Index>, Range<String.Index>, inout Bool) -> Void
    ) {
        switch options.kind {
        case .byWords:
            var cursor = range.lowerBound
            while cursor < range.upperBound {
                while cursor < range.upperBound, !self[cursor].quillIsTelegramWordCharacter {
                    formIndex(after: &cursor)
                }

                let wordStart = cursor
                while cursor < range.upperBound, self[cursor].quillIsTelegramWordCharacter {
                    formIndex(after: &cursor)
                }

                guard wordStart < cursor else {
                    continue
                }

                var stop = false
                let wordRange = wordStart..<cursor
                body(String(self[wordRange]), wordRange, wordRange, &stop)
                if stop {
                    return
                }
            }
        }
    }
}

private extension Character {
    var quillIsTelegramWordCharacter: Bool {
        isLetter || isNumber || self == "'"
    }
}

struct QuillCoreTextLine {
    let glyphCount: Int
}

func CTLineCreateWithAttributedString(_ attributedString: NSAttributedString) -> QuillCoreTextLine {
    QuillCoreTextLine(glyphCount: attributedString.string.count)
}

func CTLineGetGlyphCount(_ line: QuillCoreTextLine) -> Int {
    line.glyphCount
}
#endif
