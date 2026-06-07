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
        let referenceSamples = macReferencePromptTitles.compactMap { title in
            SamplePrompts.samples.first { $0.prompt == title }
        }
        let selectedSamples = referenceSamples.count == macReferencePromptTitles.count
            ? referenceSamples
            : Array(SamplePrompts.samples.prefix(4))

        return selectedSamples.map { sample in
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
            // Genuine macOS Enchanted shows the four sample prompts as a single
            // CENTERED row of 4 cards (Tests/Fixtures/Enchanted/macos-reference.png).
            // The earlier GTK4 LazyVGrid relayout-spin / single-column collapse was
            // caused by a fixed card frame WIDER than its flexible column in the
            // ~1180pt pane; QuillChatEmptyState.promptGridMetrics now clamps the
            // card to its column width for the multi-column non-reference window,
            // so 4 columns fit + center without spinning. Match the macOS target.
            columns: 4,
            cardWidth: 302,
            cardHeight: 128,
            spacing: 15
        ) { prompt in
            sendPrompt(prompt.title)
        }
    }
}
