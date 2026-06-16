import Foundation
import Testing
@testable import QuillSourceLowering

/// Unit coverage for the opt-in ``ActorIsolationLowering`` rule. Each case
/// exercises one of the transformations its doc comment promises, plus the two
/// carve-outs (type-qualified receivers and trailing-closure calls) that must
/// keep their `await`.
@Suite("Actor-isolation lowering (SwiftSyntax)")
struct ActorIsolationLoweringTests {
    private func lower(_ source: String) -> String {
        ActorIsolationLowering().lower(source)
    }

    @Test("actor declaration becomes a final class")
    func actorBecomesFinalClass() {
        let lowered = lower("actor Foo {}")
        #expect(lowered.contains("final class Foo {}"))
        #expect(!lowered.contains("actor Foo"))
    }

    @Test("actor with existing modifiers becomes a final class keeping them")
    func actorWithModifiersKeepsThem() {
        let source = """
        public actor SpeechRecognizer {
            var count = 0
        }
        """
        let lowered = lower(source)
        // The rule prepends `final` ahead of the existing modifier list, so the
        // access modifier follows `final` (`final public class …`). Both
        // keyword orders are valid Swift; assert on the rule's actual shape.
        #expect(lowered.contains("final public class SpeechRecognizer"))
        #expect(!lowered.contains("actor SpeechRecognizer"))
    }

    @Test("nonisolated modifier is removed from a func")
    func nonisolatedModifierRemoved() {
        let source = """
        nonisolated private func setUpdateHandler() {}
        """
        let lowered = lower(source)
        #expect(!lowered.contains("nonisolated"))
        #expect(lowered.contains("private func setUpdateHandler()"))
    }

    @Test("await on a self call is dropped")
    func awaitOnSelfCallDropped() {
        let source = """
        func run() async {
            await self.transcribe()
        }
        """
        let lowered = lower(source)
        #expect(lowered.contains("self.transcribe()"))
        #expect(!lowered.contains("await self.transcribe()"))
    }

    @Test("await on a lower-cased local instance call is dropped")
    func awaitOnInstanceCallDropped() {
        let source = """
        func run() async {
            await speechRecognizer.userInit()
        }
        """
        let lowered = lower(source)
        #expect(lowered.contains("speechRecognizer.userInit()"))
        #expect(!lowered.contains("await speechRecognizer.userInit()"))
    }

    @Test("await on a type-qualified (capitalized) call is kept")
    func awaitOnTypeQualifiedCallKept() {
        let source = """
        func run() async {
            await SFSpeechRecognizer.hasAuthorizationToRecognize()
        }
        """
        let lowered = lower(source)
        #expect(lowered.contains("await SFSpeechRecognizer.hasAuthorizationToRecognize()"))
    }

    @Test("await on a trailing-closure call is kept")
    func awaitOnTrailingClosureCallKept() {
        let source = """
        func run() async {
            await withCheckedContinuation { continuation in
                continuation.resume()
            }
        }
        """
        let lowered = lower(source)
        #expect(lowered.contains("await withCheckedContinuation"))
    }

    @Test("a representative SpeechRecognizer snippet lowers like the Perl rule")
    func representativeSpeechRecognizerSnippet() {
        let source = """
        actor SpeechRecognizer {
            nonisolated private func setUpdateHandler() {}

            func recognize() async {
                await self.setUpdateHandler()
                await transcribe()
                let ok = await SFSpeechRecognizer.hasAuthorizationToRecognize()
                _ = ok
            }
        }
        """
        let lowered = lower(source)
        #expect(lowered.contains("final class SpeechRecognizer"))
        #expect(!lowered.contains("actor SpeechRecognizer"))
        #expect(!lowered.contains("nonisolated"))
        #expect(lowered.contains("self.setUpdateHandler()"))
        #expect(!lowered.contains("await self.setUpdateHandler()"))
        #expect(lowered.contains("transcribe()"))
        #expect(!lowered.contains("await transcribe()"))
        // The type-qualified authorization check still needs its await.
        #expect(lowered.contains("await SFSpeechRecognizer.hasAuthorizationToRecognize()"))
    }

    @Test("lowering is a no-op for sources with no actor isolation")
    func noOpForPlainSource() {
        let source = """
        struct Plain {
            func greet() -> String { "hi" }
        }
        """
        #expect(lower(source) == source)
    }
}
