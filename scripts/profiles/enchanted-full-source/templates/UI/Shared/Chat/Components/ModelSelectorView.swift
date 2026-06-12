//
//  ModelSelector.swift
//  Enchanted
//

import SwiftUI
import QuillUI

struct ModelSelectorView: View {
    var modelsList: [LanguageModelSD]
    var selectedModel: LanguageModelSD?
    var onSelectModel: (_ model: LanguageModelSD?) -> Void
    var showChevron = true

    private var selectedTitle: String {
        selectedModel?.name ?? "Select Model"
    }

    private var modelActions: [QuillMenuAction] {
        QuillMenuAction.selectableModels(
            modelsList,
            selectedID: selectedModel?.name,
            id: \.name,
            name: \.name
        ) { model in
            withAnimation(.easeOut) {
                onSelectModel(model)
            }
        }
    }

    var body: some View {
        QuillMenuButton(
            title: selectedTitle,
            systemImage: showChevron ? "chevron.down" : "",
            actions: modelActions
        )
    }
}
