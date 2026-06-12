//
// signal-chat -- a native QuillOS Signal client window: conversation list,
// message thread, composer. Real Signal protocol + real libsignal crypto via
// quill-signal-bridge (presage); rendered by QuillUI's SwiftUI-on-GTK backend.
//
// GTK layout rules (LESSONS.md STEP K): fill colors via .background(Color),
// never ZStack { Color; content }; stretch rows with HStack { … Spacer() }.
//
import Foundation
import QuillUI
import QuillUIGtk

private enum Brand {
    static let blue = "#3A76F0"
    static let blueDeep = "#2456C4"
    static let ink = "#1B1B1F"
    static let subtle = "#6A6A70"
    static let canvas = "#F5F6F8"
    static let surface = "#FFFFFF"
    static let sidebar = "#FBFBFD"
    static let hairline = "#E4E4E8"
    static let bubbleIn = "#E9EAEE"
    static let selected = "#E8F0FE"
    static let green = "#2FAE60"
}

private let avatarPalette = ["#3A76F0", "#7C3AED", "#0E9488", "#D9480F", "#B23386", "#5C7CFA"]

struct SignalChatApp: App {
    init() {}
    var body: some Scene {
        QuillAppWindow.scene(
            "Signal · QuillOS",
            width: 1080,
            height: 700,
            defaultSizePolicy: .requested
        ) {
            ChatRootView()
        }
    }
}

/// Captured ScrollViewProxy so the poll timer can pin the thread to bottom.
final class ProxyHolder {
    static let shared = ProxyHolder()
    var proxy: ScrollViewProxy?
}

struct ChatRootView: View {
    @State private var lastGen = -1
    @State private var conversations: [Conversation] = []
    @State private var messages: [String: [ChatMessage]] = [:]
    @State private var selected: String? = nil
    @State private var draft = ""
    @State private var status = "connecting to bridge…"

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 300)
            detail
        }
        .background(Color(hex: Brand.canvas))
        .onAppear {
            ChatStore.shared.start()
            if ChatStore.shared.beginUIPolling() {
                Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
                    pollStore()
                }
            }
        }
    }

    private func pollStore() {
        let snap = ChatStore.shared.snapshot()
        guard snap.gen != lastGen else { return }
        lastGen = snap.gen
        conversations = snap.convos
        messages = snap.messages
        status = snap.status
        if selected == nil { selected = snap.convos.first?.id }
        if let sel = selected, let last = messages[sel]?.last {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                ProxyHolder.shared.proxy?.scrollTo(last.id)
            }
        }
    }

    // MARK: sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Signal")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(Color(hex: "#FFFFFF"))
                Spacer()
            }
            .padding(18)
            .background(Color(hex: Brand.blue))
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(conversations) { convo in
                        conversationRow(convo)
                    }
                }
                .padding(8)
            }
            Spacer()
            HStack(spacing: 6) {
                Text("●").font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color(hex: Brand.green))
                Text(status).font(.system(size: 12))
                    .foregroundColor(Color(hex: Brand.subtle))
                Spacer()
            }
            .padding(12)
        }
        .background(Color(hex: Brand.sidebar))
    }

    private func conversationRow(_ convo: Conversation) -> some View {
        HStack(spacing: 10) {
            avatar(for: convo)
            VStack(alignment: .leading, spacing: 2) {
                Text(convo.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color(hex: Brand.ink))
                Text(snippet(for: convo.id))
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: Brand.subtle))
            }
            Spacer()
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10)
            .fill(Color(hex: selected == convo.id ? Brand.selected : Brand.sidebar)))
        .onTapGesture {
            selected = convo.id
            ChatStore.shared.select(thread: convo.id)
        }
    }

    private func avatar(for convo: Conversation) -> some View {
        let color = avatarPalette[abs(convo.id.hashValue) % avatarPalette.count]
        let initial = String(convo.name.prefix(1)).uppercased()
        // Outer fixed frame clamps the pill even when a parent HStack
        // proposes extra width (the header stretched it otherwise).
        return Text(initial)
            .font(.system(size: 16, weight: .bold))
            .foregroundColor(Color(hex: "#FFFFFF"))
            .frame(width: 38, height: 38)
            .background(RoundedRectangle(cornerRadius: 19).fill(Color(hex: color)))
            .frame(width: 38, height: 38)
    }

    private func snippet(for thread: String) -> String {
        guard let last = messages[thread]?.last else { return " " }
        let prefix = last.fromSelf ? "you: " : ""
        let body = last.body.replacingOccurrences(of: "\n", with: " ")
        return prefix + String(body.prefix(34))
    }

    // MARK: detail

    private var detail: some View {
        VStack(spacing: 0) {
            threadHeader
            if let sel = selected {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(messages[sel] ?? []) { msg in
                                bubbleRow(msg, isGroup: currentConvo?.isGroup ?? false)
                                    .id(msg.id)
                            }
                        }
                        .padding(14)
                    }
                    .onAppear { ProxyHolder.shared.proxy = proxy }
                }
            } else {
                Spacer()
                HStack {
                    Spacer()
                    Text("Select a conversation")
                        .font(.system(size: 15))
                        .foregroundColor(Color(hex: Brand.subtle))
                    Spacer()
                }
                Spacer()
            }
            composer
        }
    }

    private var currentConvo: Conversation? {
        conversations.first { $0.id == selected }
    }

    private var threadHeader: some View {
        HStack(spacing: 10) {
            if let convo = currentConvo {
                avatar(for: convo)
                VStack(alignment: .leading, spacing: 2) {
                    Text(convo.name)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(Color(hex: Brand.ink))
                    Text(convo.isGroup ? "group · Signal protocol · e2e encrypted"
                                       : "Signal protocol · e2e encrypted")
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: Brand.subtle))
                }
            } else {
                Text("Signal on QuillOS")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Color(hex: Brand.ink))
            }
            Spacer()
        }
        .padding(14)
        .background(Color(hex: Brand.surface))
    }

    private func bubbleRow(_ msg: ChatMessage, isGroup: Bool) -> some View {
        HStack(spacing: 0) {
            if msg.fromSelf { Spacer(minLength: 120) }
            VStack(alignment: .leading, spacing: 4) {
                if isGroup && !msg.fromSelf {
                    Text(senderLabel(msg))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(hex: Brand.blueDeep))
                }
                if let path = msg.attachmentPath {
                    Image(filePath: path)
                }
                Text(msg.body)
                    .font(.system(size: 15))
                    .foregroundColor(Color(hex: msg.fromSelf ? "#FFFFFF" : Brand.ink))
                Text(timeLabel(msg.timestamp))
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: msg.fromSelf ? "#D8E2FF" : Brand.subtle))
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 14)
                .fill(Color(hex: msg.fromSelf ? Brand.blue : Brand.bubbleIn)))
            if !msg.fromSelf { Spacer(minLength: 120) }
        }
    }

    private func senderLabel(_ msg: ChatMessage) -> String {
        if let name = msg.senderName, !name.isEmpty { return name }
        if let match = conversations.first(where: { $0.id == msg.sender }) { return match.name }
        return String(msg.sender.prefix(8))
    }

    private func timeLabel(_ ts: UInt64) -> String {
        guard ts > 0 else { return "" }
        let date = Date(timeIntervalSince1970: TimeInterval(ts) / 1000)
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return fmt.string(from: date)
    }

    // MARK: composer

    private var composer: some View {
        HStack(spacing: 10) {
            TextField("Message", text: $draft)
                .onSubmit { sendDraft() }
            Button("Send") { sendDraft() }
        }
        .padding(12)
        .background(Color(hex: Brand.surface))
    }

    private func sendDraft() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let sel = selected else { return }
        draft = ""
        ChatStore.shared.send(thread: sel, body: text)
    }
}

QuillGtkApp.run(SignalChatApp.self)
