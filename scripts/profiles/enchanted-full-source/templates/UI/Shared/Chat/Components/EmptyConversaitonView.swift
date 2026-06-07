//
//  EmptyConversaitonView.swift
//  Enchanted
//

import SwiftUI
import QuillUI

struct EmptyConversaitonView: View, KeyboardReadable {
    var sendPrompt: (String) -> Void

    var body: some View {
        QuillSelectedPromptEmptyState(
            brandTitle: "Enchanted",
            source: SamplePrompts.samples,
            id: { $0.id },
            title: { $0.prompt },
            systemImage: { $0.type.icon },
            sendPrompt: sendPrompt
        )
    }
}
