s/actor SpeechRecognizer/final class SpeechRecognizer/;
s/Task \{[ \t]*\@MainActor[ \t]+in/Task {/g;
s/Task \{[ \t]*\@MainActor[ \t]+\[errorMessage\][ \t]+in/Task { [errorMessage] in/g;
s/^[ \t]*\@MainActor[ \t]+//gm;
s/nonisolated private func/private func/g;
s/await self\.setUpdateHandler/self.setUpdateHandler/g;
s/await transcribe\(\)/transcribe()/g;
s/await reset\(\)/reset()/g;
s/await onUpdate\?\(message\)/onUpdate?(message)/g;
