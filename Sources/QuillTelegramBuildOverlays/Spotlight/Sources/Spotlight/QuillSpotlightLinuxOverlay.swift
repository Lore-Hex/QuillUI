#if os(Linux)

import AppKit
import Foundation
import Postbox
import TelegramCore

extension Peer {
    var displayTitle: String {
        if let user = self as? TelegramUser {
            let firstName = user.firstName ?? ""
            let lastName = user.lastName ?? ""
            let combined = [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ")
            if !combined.isEmpty {
                return combined
            }
            if let phone = user.phone, !phone.isEmpty {
                return phone
            }
        }
        if let group = self as? TelegramGroup {
            return group.title
        }
        if let channel = self as? TelegramChannel {
            return channel.title
        }
        return "\(id.toInt64())"
    }
}

struct QuillSpotlightThemeIcons {
    var appUpdate: NSImage {
        NSImage(size: NSSize(width: 32, height: 32))
    }
}

struct QuillSpotlightTheme {
    var icons = QuillSpotlightThemeIcons()
}

let theme = QuillSpotlightTheme()

func urlVars(with url: String) -> ([String: String], Set<String>) {
    let query = url.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).last.map(String.init) ?? url
    var variables: [String: String] = [:]
    var emptyVariables = Set<String>()

    for component in query.split(separator: "&", omittingEmptySubsequences: false) {
        let parts = component.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        guard let key = parts.first.map(String.init), !key.isEmpty else {
            continue
        }
        if parts.count == 2 {
            variables[key.lowercased()] = String(parts[1])
        } else {
            emptyVariables.insert(key)
        }
    }

    return (variables, emptyVariables)
}

#endif
