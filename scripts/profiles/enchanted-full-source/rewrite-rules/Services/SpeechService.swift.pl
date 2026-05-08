s/^[ \t]*\@MainActor[ \t]+final class/final class/gm;
s/([ \t]*)synthesizer\.stopSpeaking\(at: \.immediate\)/$1_ = synthesizer.stopSpeaking(at: .immediate)/g;
