//
//  EmptyConversaitonView.swift
//  Enchanted
//
//  Created by Augustinas Malinauskas on 10/02/2024.
//

import SwiftUI

struct EmptyConversaitonView: View, KeyboardReadable {
    @State private var showPromptsAnimation = false
    @State private var prompts: [SamplePrompts] = []
    let sendPrompt: (String) -> Void
#if os(iOS)
    @State private var isKeyboardVisible = false
#endif
    
#if os(macOS)
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 15), count: 4)
#else
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]
#endif
    @State private var visibleItems = Set<Int>()
    
    var body: some View {
        VStack {
            Spacer()
            
            VStack(spacing: 25) {
                VStack(alignment: .center) {
                    Text("Enchanted")
                        .font(Font.system(size: 46, weight: .thin))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(hex: "4285f4"), Color(hex: "9b72cb"), Color(hex: "d96570"), Color(hex: "#d96570")],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                }
                
                LazyVGrid(columns: columns, alignment: .leading, spacing: 15) {
                    ForEach(0..<prompts.prefix(4).count, id: \.self) { index in
                        promptButton(for: prompts[index], index: index)
                    }
                }
                .onAppear {
                    for index in 0..<4 {
                        DispatchQueue.main.async {
                            visibleItems.insert(index)
                        }
                    }
                }
                .frame(maxWidth: 700)
                .padding()
                .transition(AnyTransition(.opacity).combined(with: .slide))
#if os(iOS)
                .showIf(!isKeyboardVisible)
#endif
            }
            Spacer()
        }
        .onAppear {
            DispatchQueue.main.async {
                withAnimation {
                    prompts = SamplePrompts.samples.shuffled()
                    showPromptsAnimation = true
                }
            }
        }
#if os(iOS)
        .onReceive(keyboardPublisher) { newIsKeyboardVisible in
            DispatchQueue.main.async {
                withAnimation {
                    isKeyboardVisible = newIsKeyboardVisible
                }
            }
        }
#endif

    }

    private func promptButton(for prompt: SamplePrompts, index: Int) -> some View {
        Button(action: {
            withAnimation {
                sendPrompt(prompt.prompt)
            }
        }) {
            VStack(alignment: .leading, spacing: 10) {
                Text(prompt.prompt)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.labelCustom)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 8)

                HStack {
                    Spacer()
                    Image(systemName: prompt.type.icon)
                        .imageScale(.medium)
                        .foregroundStyle(Color.secondary)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
            .padding(15)
            .background(Color.gray5Custom, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.gray4Custom.opacity(0.35), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .opacity(visibleItems.contains(index) ? 1 : 0)
        .animation(.easeOut(duration: 0.3).delay(0.2 * Double(index)), value: visibleItems)
        .transition(.slide)
        .showIf(showPromptsAnimation)
        .buttonStyle(.plain)
        .accessibilityLabel(Text(prompt.prompt))
    }
}

#Preview(traits: .fixedLayout(width: 1000, height: 1000)) {
    EmptyConversaitonView(sendPrompt: {_ in})
}
