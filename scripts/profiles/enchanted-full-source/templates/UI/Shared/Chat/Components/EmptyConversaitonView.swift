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
            // Match Enchanted's upstream empty-state prompt list. SwiftOpenUI's
            // GTK renderer now routes this finite one-column LazyVGrid through a
            // static GtkGrid path instead of GtkGridView's relayout-prone path.
            columns: 1,
            cardWidth: 619,
            cardHeight: 64,
            spacing: 15
        ) { prompt in
            sendPrompt(prompt.title)
        }
    }
}
