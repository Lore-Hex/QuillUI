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
            // NOTE: the generated upstream Enchanted profile keeps the legacy
            // 2-column grid. The single-column macOS-parity layout (shared
            // EnchantedVisualMetrics) is used by the core app + upstream slice,
            // but inside the real Enchanted view hierarchy SwiftOpenUI's GTK4
            // LazyVGrid relayout-spins on a single column, blowing the CPU/RSS
            // profile budget. Tracked separately; revisit once that GTK4 grid
            // path is fixed.
            columns: 2,
            cardWidth: 302,
            cardHeight: 128,
            spacing: 15
        ) { prompt in
            sendPrompt(prompt.title)
        }
    }
}
