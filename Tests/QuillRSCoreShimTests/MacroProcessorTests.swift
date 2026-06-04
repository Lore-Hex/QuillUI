import Foundation
import Testing
@testable import QuillRSCoreShim

/// Pins the vendored RSCore `MacroProcessor` — `[[macro]]` template
/// substitution. Contract: defined keys are replaced; undefined macros are left
/// verbatim (delimiters and all); empty delimiters throw.
@Suite("QuillRSCoreShim — MacroProcessor ([[macro]] templating)")
struct MacroProcessorTests {

    @Test("replaces a defined macro with its value")
    func basicSubstitution() throws {
        let out = try MacroProcessor.renderedText(
            withTemplate: "Hello [[name]]!", substitutions: ["name": "World"]
        )
        #expect(out == "Hello World!")
    }

    @Test("replaces multiple and repeated macros")
    func multipleMacros() throws {
        let out = try MacroProcessor.renderedText(
            withTemplate: "[[a]]-[[b]]-[[a]]", substitutions: ["a": "1", "b": "2"]
        )
        #expect(out == "1-2-1")
    }

    @Test("leaves an undefined macro verbatim, delimiters included")
    func undefinedMacroLeftAsIs() throws {
        let out = try MacroProcessor.renderedText(
            withTemplate: "x [[missing]] y", substitutions: [:]
        )
        #expect(out == "x [[missing]] y")
    }

    @Test("a template with no macros is returned unchanged")
    func noMacros() throws {
        let out = try MacroProcessor.renderedText(
            withTemplate: "plain text, no macros", substitutions: ["a": "1"]
        )
        #expect(out == "plain text, no macros")
    }

    @Test("custom delimiters are honored")
    func customDelimiters() throws {
        let out = try MacroProcessor.renderedText(
            withTemplate: "Hi {name}", substitutions: ["name": "Q"],
            macroStart: "{", macroEnd: "}"
        )
        #expect(out == "Hi Q")
    }

    @Test("an unterminated macro start is left verbatim")
    func unterminatedMacro() throws {
        let out = try MacroProcessor.renderedText(
            withTemplate: "start [[oops no end", substitutions: ["oops": "X"]
        )
        #expect(out == "start [[oops no end")
    }

    @Test("empty delimiters throw emptyMacroDelimiter")
    func emptyDelimiterThrows() {
        #expect(throws: MacroProcessorError.self) {
            _ = try MacroProcessor.renderedText(
                withTemplate: "x", substitutions: [:], macroStart: "", macroEnd: "]]"
            )
        }
    }
}
