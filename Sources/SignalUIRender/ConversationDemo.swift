// ConversationDemo.swift — a Signal conversation styled by Signal's REAL engine.
// =============================================================================
// The real ConversationViewController + CVComponent message pipeline live in
// Signal's app target. This renderer now links that module when the prepared
// app slice exists, while the visible conversation demo still uses
// ConversationStyle until a DB-backed CVC bootstrap is installed.

import SignalUI
import SignalServiceKit
import QuillUIKit
import UIKit
import QuillFoundation
import Foundation
#if canImport(SignalApp)
import SignalApp
#endif

@MainActor
enum SignalConversationDemo {

    private struct Msg { let text: String; let time: String; let incoming: Bool }

    static func makeConversationViewController() -> UIViewController {
        SignalSettingsDemo.bootstrapMinimalEnvironment()

        // Colors from Signal's REAL ConversationStyle logic. The full
        // ConversationStyle(thread:) initializer needs a TSContactThread, whose
        // construction reaches SSKEnvironment (a DB-backed address cache we don't
        // bootstrap) — so we use the static incoming-bubble color function (no
        // thread) plus Signal's real default chat color, "ultramarine" (the exact
        // OWSColor swatch from PaletteChatColor+Constants).
        let incomingColor = resolveSolid(ConversationStyle.bubbleChatColorIncoming(
            hasWallpaper: false,
            shouldDimWallpaperInDarkMode: false,
            isDarkThemeEnabled: Theme.isDarkThemeEnabled
        ))                                                                          // real #E9E9E9 (light)
        let outgoingColor = OWSColor(red: 0.17254901960784313,
                                     green: 0.4196078431372549,
                                     blue: 0.9294117647058922).asUIColor            // ultramarine

        let ink = UIColor(red: 0.07, green: 0.07, blue: 0.08, alpha: 1)
        let gray = UIColor(red: 0.42, green: 0.42, blue: 0.45, alpha: 1)

        let root = UIView(frame: CGRect(x: 0, y: 0, width: 760, height: 720))
        root.backgroundColor = .white

        // Header: contact name + encryption subtitle.
        let header = makeHeader(name: "Alice Moreau",
                                subtitle: "Signal message · end-to-end encrypted",
                                ink: ink, gray: gray)

        // Message list inside a scroll view (so it expands and pins the composer
        // to the bottom — the renderer gives a UIScrollView vexpand).
        let messages = UIStackView()
        messages.axis = .vertical
        messages.spacing = 10
        messages.alignment = .fill

        let convo: [Msg] = [
            Msg(text: "did you really get Signal running on the Quill board??", time: "06:01", incoming: true),
            Msg(text: "yep — native ARM64 Linux, real libsignal underneath", time: "06:02", incoming: false),
            Msg(text: "no Electron??", time: "06:03", incoming: true),
            Msg(text: "none. it's a 12 MB binary, boots in under a second", time: "06:03", incoming: false),
            Msg(text: "ok that's actually wild. send a screenshot", time: "06:04", incoming: true),
            Msg(text: "same Signal UI code — just rendered through QuillUI on GTK", time: "06:05", incoming: false),
        ]
        for m in convo {
            messages.addArrangedSubview(makeRow(m, incomingColor: incomingColor, outgoingColor: outgoingColor,
                                                ink: ink, gray: gray))
        }

        let pad = UIView()
        pad.accessibilityIdentifier = "qclass:qmsgpad"
        pad.addSubview(messages)

        let scroll = UIScrollView()
        scroll.addSubview(pad)

        // Composer: rounded "Message" field + Send.
        let composer = makeComposer(gray: gray)

        root.addSubview(header)
        root.addSubview(scroll)
        root.addSubview(composer)

        let vc = UIViewController()
        vc.view = root
        return vc
    }

    static func makeRealAppLinkProbeViewController() -> UIViewController {
        SignalSettingsDemo.bootstrapMinimalEnvironment()

        let root = UIView(frame: CGRect(x: 0, y: 0, width: 520, height: 260))
        root.backgroundColor = .white

        let title = UILabel()
        title.text = "SignalApp module linked"
        title.font = UIFont.systemFont(ofSize: 22, weight: .semibold)
        title.textColor = UIColor(red: 0.07, green: 0.07, blue: 0.08, alpha: 1)

        let subtitle = UILabel()
        #if canImport(SignalApp)
        _ = QuillSignalAppModuleProbe.hasConversationViewController
        subtitle.text = "Real ConversationViewController is linked into the Linux GTK renderer."
        #else
        subtitle.text = "Prepared SignalApp slice is not present in this checkout."
        #endif
        subtitle.font = UIFont.systemFont(ofSize: 15)
        subtitle.textColor = UIColor(red: 0.36, green: 0.36, blue: 0.39, alpha: 1)
        subtitle.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [title, subtitle])
        stack.axis = .vertical
        stack.spacing = 8
        stack.frame = CGRect(x: 24, y: 32, width: 472, height: 160)
        root.addSubview(stack)

        let vc = UIViewController()
        vc.view = root
        return vc
    }

    static func makeRealComponentPreviewViewController() -> UIViewController {
        SignalSettingsDemo.bootstrapMinimalEnvironment()

        #if canImport(SignalApp)
        return QuillSignalRealComponentPreview.makeViewController()
        #else
        return makeRealAppLinkProbeViewController()
        #endif
    }

    // MARK: - Pieces

    private static func makeHeader(name: String, subtitle: String, ink: UIColor, gray: UIColor) -> UIView {
        let nameLabel = UILabel()
        nameLabel.text = name
        nameLabel.textColor = ink
        nameLabel.font = UIFont.systemFont(ofSize: 17)

        let subtitleLabel = UILabel()
        subtitleLabel.text = subtitle
        subtitleLabel.textColor = gray
        subtitleLabel.font = UIFont.systemFont(ofSize: 13)

        let stack = UIStackView(arrangedSubviews: [nameLabel, subtitleLabel])
        stack.axis = .vertical
        stack.spacing = 1

        let header = UIView()
        header.accessibilityIdentifier = "qclass:qheader"
        header.addSubview(stack)
        return header
    }

    private static func makeRow(_ m: Msg, incomingColor: UIColor, outgoingColor: UIColor,
                                ink: UIColor, gray: UIColor) -> UIView {
        // Bubble: rounded UIView (real ConversationStyle color) + body + timestamp.
        let textColor: UIColor = m.incoming ? ink : .white
        let timeColor: UIColor = m.incoming ? gray : UIColor(white: 1, alpha: 0.75)

        let body = UILabel()
        body.text = m.text
        body.textColor = textColor
        body.font = UIFont.systemFont(ofSize: 15)
        body.numberOfLines = 0

        let time = UILabel()
        time.text = m.time
        time.textColor = timeColor
        time.font = UIFont.systemFont(ofSize: 11)
        time.textAlignment = .right

        let bubbleStack = UIStackView(arrangedSubviews: [body, time])
        bubbleStack.axis = .vertical
        bubbleStack.spacing = 2

        let bubble = UIView()
        bubble.backgroundColor = m.incoming ? incomingColor : outgoingColor
        bubble.layer.cornerRadius = 16
        bubble.accessibilityIdentifier = "qclass:qbubble"
        bubble.addSubview(bubbleStack)

        let spacer = UIView()
        spacer.accessibilityIdentifier = "qspacer"

        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 8
        row.distribution = .equalSpacing
        if m.incoming {
            row.addArrangedSubview(makeAvatar(initial: "A"))
            row.addArrangedSubview(bubble)
            row.addArrangedSubview(spacer)
        } else {
            row.addArrangedSubview(spacer)
            row.addArrangedSubview(bubble)
        }
        return row
    }

    private static func makeAvatar(initial: String) -> UIView {
        let avatar = UIView(frame: CGRect(x: 0, y: 0, width: 28, height: 28))
        avatar.backgroundColor = UIColor(red: 0.50, green: 0.27, blue: 0.90, alpha: 1)
        avatar.layer.cornerRadius = 14
        let label = UILabel()
        label.text = initial
        label.textColor = .white
        label.font = UIFont.systemFont(ofSize: 13)
        label.textAlignment = .center
        avatar.addSubview(label)
        return avatar
    }

    private static func makeComposer(gray: UIColor) -> UIView {
        let placeholder = UILabel()
        placeholder.text = "Message"
        placeholder.textColor = gray
        placeholder.font = UIFont.systemFont(ofSize: 15)

        let field = UIView()
        field.accessibilityIdentifier = "qclass:qfield"
        field.addSubview(placeholder)

        let send = UILabel()
        send.text = "Send"
        send.textColor = UIColor(red: 0.094, green: 0.420, blue: 0.929, alpha: 1)
        send.font = UIFont.systemFont(ofSize: 16)

        let row = UIStackView(arrangedSubviews: [field, send])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        row.distribution = .equalSpacing

        let composer = UIView()
        composer.accessibilityIdentifier = "qclass:qcomposer"
        composer.addSubview(row)
        return composer
    }

    /// Reduce a ConversationStyle color to a single solid UIColor for the renderer.
    private static func resolveSolid(_ value: ColorOrGradientValue) -> UIColor {
        switch value {
        case .solidColor(let color):
            return color
        case .gradient(_, let color2, _):
            return color2
        case .transparent:
            return .clear
        case .blur:
            return UIColor(red: 0.914, green: 0.914, blue: 0.914, alpha: 1)
        }
    }
}
