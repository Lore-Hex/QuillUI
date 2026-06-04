import Foundation
import Testing
@testable import QuillRSCoreShim

/// Pins the vendored RSCore `String.strippingHTML` against its documented
/// contract: tags removed, script/style bodies discarded, block tags inject a
/// space, whitespace collapses, leading/trailing trimmed, entities NOT decoded,
/// and the `maxCharacters` cap.
@Suite("QuillRSCoreShim — String.strippingHTML")
struct StripHTMLTests {

    @Test("removes simple tags")
    func simpleTags() {
        #expect("<b>Hello</b>".strippingHTML() == "Hello")
        #expect("<p>Hello <b>world</b></p>".strippingHTML() == "Hello world")
    }

    @Test("block-level tags inject a space so word boundaries survive")
    func blockTagsInjectSpace() {
        #expect("<p>a</p><p>b</p>".strippingHTML() == "a b")
        #expect("a<br>b".strippingHTML() == "a b")
    }

    @Test("script and style bodies are discarded entirely")
    func scriptAndStyleDiscarded() {
        #expect("x<script>var n = 1;</script>y".strippingHTML() == "xy")
        #expect("x<style>.a { color: red; }</style>y".strippingHTML() == "xy")
    }

    @Test("runs of whitespace collapse to a single space; ends are trimmed")
    func whitespaceCollapseAndTrim() {
        #expect("a   b\n\nc".strippingHTML() == "a b c")
        #expect("   hello   ".strippingHTML() == "hello")
    }

    @Test("HTML entities are NOT decoded")
    func entitiesNotDecoded() {
        #expect("a&amp;b".strippingHTML() == "a&amp;b")
    }

    @Test("maxCharacters caps the output length")
    func maxCharacters() {
        #expect("hello world".strippingHTML(maxCharacters: 5) == "hello")
    }

    @Test("empty input yields empty output")
    func empty() {
        #expect("".strippingHTML() == "")
    }
}
