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
            // Single-column macOS-parity layout, matching the core app + slice.
            // The GTK4 single-column relayout spin is fixed in the shared
            // ScrollView cross-axis tick (gtkScrollViewCrossAxisTickCallback now
            // clamps fill width to the child's min), so the generated profile no
            // longer blows the CPU/RSS budget.
            columns: 1,
            cardWidth: 619,
            cardHeight: 64,
            spacing: 15
        ) { prompt in
            sendPrompt(prompt.title)
        }
    }
}
