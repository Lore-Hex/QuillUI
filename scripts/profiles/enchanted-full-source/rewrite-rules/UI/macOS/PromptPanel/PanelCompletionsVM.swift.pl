s/self\?\.handleComplete\(\)/Task { \@MainActor in self?.handleComplete() }/g;
s/self\?\.handleError\(error\.localizedDescription\)/Task { \@MainActor in self?.handleError(error.localizedDescription) }/g;
s/self\?\.handleReceive\(response\)/Task { \@MainActor in self?.handleReceive(response) }/g;
s/OKCompletionOptions\(temperature: completion\.modelTemperature \?\? 0\.8\)/OKCompletionOptions(temperature: Double(completion.modelTemperature ?? 0.8))/g;
