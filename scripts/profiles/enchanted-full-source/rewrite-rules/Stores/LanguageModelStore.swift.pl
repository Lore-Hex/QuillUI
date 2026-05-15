s{init\(swiftDataService: SwiftDataService\) \{
        self\.swiftDataService = swiftDataService
    \}}{<<'SWIFT'}se;
init(swiftDataService: SwiftDataService) {
        self.swiftDataService = swiftDataService
        let environment = ProcessInfo.processInfo.environment
        if environment["QUILLUI_ENCHANTED_REFERENCE_MODE"] == "1"
            || environment["QUILLUI_QUILL_CHAT_REFERENCE_MODE"] == "1" {
            let fallbackModel = LanguageModelSD(name: "llava:latest", imageSupport: true, modelProvider: .ollama)
            self.models = [fallbackModel]
            self.selectedModel = fallbackModel
            self.supportsImages = fallbackModel.supportsImages
        }
    }
SWIFT

s{func loadModels\(\) async throws \{.*?\n    \}\n    \n    func deleteAllModels\(\)}{<<'SWIFT'}se;
func loadModels() async throws {
        let environment = ProcessInfo.processInfo.environment
        if environment["QUILLUI_ENCHANTED_REFERENCE_MODE"] == "1"
            || environment["QUILLUI_QUILL_CHAT_REFERENCE_MODE"] == "1" {
            let storedModels = (try? await swiftDataService.fetchModels()) ?? []
            let fallbackModels = storedModels.isEmpty
                ? [LanguageModelSD(name: "llava:latest", imageSupport: true, modelProvider: .ollama)]
                : storedModels

            DispatchQueue.main.async {
                self.models = fallbackModels
                if self.selectedModel == nil {
                    self.selectedModel = fallbackModels.first
                }
                self.supportsImages = fallbackModels.first?.supportsImages ?? false
            }
            return
        }

        let remoteModels = try await OllamaService.shared.getModels()
        try await swiftDataService.saveModels(models: remoteModels.map{LanguageModelSD(name: $0.name, imageSupport: $0.imageSupport, modelProvider: .ollama)})

        let storedModels = (try? await swiftDataService.fetchModels()) ?? []

        DispatchQueue.main.async {
            let remoteModelNames = remoteModels.map { $0.name }
            self.models = storedModels.filter{remoteModelNames.contains($0.name)}
        }
    }

    func deleteAllModels()
SWIFT
