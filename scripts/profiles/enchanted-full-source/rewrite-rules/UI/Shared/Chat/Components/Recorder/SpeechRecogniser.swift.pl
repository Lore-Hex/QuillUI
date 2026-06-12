s/actor SpeechRecognizer/final class SpeechRecognizer/;
s/^[ \t]*\@MainActor[ \t]+//gm;
s/nonisolated private func/private func/g;
s/await self\.setUpdateHandler/self.setUpdateHandler/g;
s/await transcribe\(\)/transcribe()/g;
s/await reset\(\)/reset()/g;
s/await onUpdate\?\(message\)/onUpdate?(message)/g;
