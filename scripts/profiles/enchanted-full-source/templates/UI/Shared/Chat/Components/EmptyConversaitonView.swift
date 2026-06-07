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
            layout: .wideDesktopCards
        ) { prompt in
            sendPrompt(prompt.title)
        }
    }
}
