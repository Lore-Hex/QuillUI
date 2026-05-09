//
//  EmptyConversaitonView.swift
//  Enchanted
//

import SwiftUI
import QuillUI

struct EmptyConversaitonView: View, KeyboardReadable {
    var sendPrompt: (String) -> Void

    private var prompts: [QuillPrompt] {
        let macReferenceOrder = [
            "How to center div in HTML?",
            "How to do personal taxes in USA?",
            "Explain supercomputers like I'm five years old",
            "Write a text message asking a friend to be my plus-one at a wedding"
        ]
        let samplesByPrompt = Dictionary(uniqueKeysWithValues: SamplePrompts.samples.map { ($0.prompt, $0) })
        return macReferenceOrder.compactMap { samplesByPrompt[$0] }.map { sample in
            QuillPrompt(
                id: sample.id,
                title: sample.prompt,
                systemImage: sample.type.icon
            )
        }
    }

    var body: some View {
        QuillChatEmptyState(
            brandTitle: "Quill",
            prompts: prompts,
            columns: 4,
            cardWidth: 155,
            cardHeight: 128,
            spacing: 15
        ) { prompt in
            sendPrompt(prompt.title)
        }
    }
}
