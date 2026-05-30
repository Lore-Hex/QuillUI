//
//  EmptyConversaitonView.swift
//  Enchanted
//

import SwiftUI
import QuillUI

struct EmptyConversaitonView: View, KeyboardReadable {
    var sendPrompt: (String) -> Void

    private var prompts: [QuillPrompt] {
        SamplePrompts.samples.prefix(4).map { sample in
            QuillPrompt(
                id: sample.id,
                title: sample.prompt,
                systemImage: sample.type.icon
            )
        }
    }

    var body: some View {
        QuillChatEmptyState(
            brandTitle: "Enchanted",
            prompts: prompts,
            columns: 1,
            cardWidth: 619,
            cardHeight: 64,
            spacing: 15
        ) { prompt in
            sendPrompt(prompt.title)
        }
    }
}
