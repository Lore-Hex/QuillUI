//
//  EmptyConversaitonView.swift
//  Enchanted
//

import SwiftUI
import QuillUI

struct EmptyConversaitonView: View, KeyboardReadable {
    var sendPrompt: (String) -> Void

    private let macReferencePromptTitles = [
        "How to center div in HTML?",
        "How to do personal taxes in USA?",
        "Explain supercomputers like I'm five years old",
        "Write a text message asking a friend to be my plus-one at a wedding"
    ]

    private var prompts: [QuillPrompt] {
        QuillPrompt.selectedPrompts(
            from: SamplePrompts.samples,
            preferredTitles: macReferencePromptTitles,
            id: { $0.id },
            title: { $0.prompt },
            systemImage: { $0.type.icon }
        )
    }

    var body: some View {
        QuillChatEmptyState(
            brandTitle: "Enchanted",
            prompts: prompts,
            layout: .wideDesktopCards
        ) { prompt in
            sendPrompt(prompt.title)
        }
    }
}
