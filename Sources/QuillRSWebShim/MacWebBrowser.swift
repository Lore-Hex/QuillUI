//
//  MacWebBrowser.swift
//  RSWeb
//
//  Quill Linux compatibility for NetNewsWire's RSWeb.MacWebBrowser surface.
//

import AppKit
import Foundation

@MainActor public final class MacWebBrowser {
    @discardableResult public static func openURL(_ url: URL, inBackground: Bool = false) -> Bool {
        guard let preparedURL = url.preparedForOpeningInBrowser() else {
            return false
        }

        if inBackground {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            NSWorkspace.shared.open(preparedURL, configuration: configuration, completionHandler: nil)
            return true
        }

        return NSWorkspace.shared.open(preparedURL)
    }

    public static func sortedBrowsers() -> [MacWebBrowser] {
        guard let url = defaultBrowserURL else {
            return []
        }
        return [MacWebBrowser(url: url)]
    }

    public static func duplicateBrowserNames(in browsers: [MacWebBrowser]) -> Set<String> {
        var names = Set<String>()
        var duplicates = Set<String>()

        for browser in browsers {
            guard let name = browser.name else {
                continue
            }
            if !names.insert(name).inserted {
                duplicates.insert(name)
            }
        }

        return duplicates
    }

    public static func displayPath(of url: URL) -> String {
        let parentPath = canonicalParentPath(for: url)
        return displayPath(forCanonicalParentPath: parentPath)
    }

    static func displayPath(forCanonicalParentPath parentPath: String) -> String {
        let components = (parentPath as NSString).pathComponents

        if components.count >= 3 && components[0] == "/" && components[1] == "Volumes" {
            let volumeName = components[2]
            let inside = components.dropFirst(3).joined(separator: "/")
            return composedVolumePath(volumeName: volumeName, inside: inside)
        }

        return shortenedRootPath(parentPath)
    }

    public static var `default`: MacWebBrowser {
        MacWebBrowser(url: defaultBrowserURL ?? URL(fileURLWithPath: "/usr/bin/xdg-open"))
    }

    public nonisolated let url: URL

    public var icon: NSImage? {
        NSWorkspace.shared.icon(forFile: url.path)
    }

    public nonisolated var name: String? {
        let filename = url.lastPathComponent
        guard !filename.isEmpty else {
            return nil
        }
        if filename.hasSuffix(".app") || filename.hasSuffix(".desktop") {
            return (filename as NSString).deletingPathExtension
        }
        return filename
    }

    public nonisolated var bundleIdentifier: String? {
        Bundle(url: url)?.bundleIdentifier
    }

    public nonisolated var bundlePath: String {
        url.path
    }

    public init(url: URL) {
        self.url = url
    }

    public convenience init?(bundleIdentifier: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return nil
        }
        self.init(url: url)
    }

    public convenience init?(path: String) {
        guard FileManager.default.fileExists(atPath: path) else {
            return nil
        }
        self.init(url: URL(fileURLWithPath: path))
    }

    @discardableResult public func openURL(_ url: URL, inBackground: Bool = false) -> Bool {
        guard let preparedURL = url.preparedForOpeningInBrowser() else {
            return false
        }

        let configuration = NSWorkspace.OpenConfiguration()
        if inBackground {
            configuration.activates = false
        }
        NSWorkspace.shared.open(preparedURL, configuration: configuration, completionHandler: nil)
        return true
    }
}

extension MacWebBrowser: CustomDebugStringConvertible {
    public nonisolated var debugDescription: String {
        if let name, let bundleIdentifier {
            return "MacWebBrowser: \(name) (\(bundleIdentifier))"
        }
        return "MacWebBrowser"
    }
}

private extension MacWebBrowser {
    static func canonicalParentPath(for url: URL) -> String {
        url.deletingLastPathComponent().standardizedFileURL.path
    }

    static func composedVolumePath(volumeName: String, inside: String) -> String {
        if inside.isEmpty {
            return "/\(volumeName)"
        }
        let parts = inside.split(separator: "/", omittingEmptySubsequences: true)
        if parts.count <= 3 {
            return "/\(volumeName)/\(inside)"
        }
        let trailing = String(parts.last ?? "")
        return "/\(volumeName)/.../\(trailing)"
    }

    static func shortenedRootPath(_ path: String) -> String {
        let components = (path as NSString).pathComponents
        let maxComponents = 4
        if components.count <= maxComponents {
            return path
        }
        let leading = "/\(components[1])"
        let trailing = components.last ?? ""
        return "\(leading)/.../\(trailing)"
    }

    static var defaultBrowserURL: URL? {
        NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://apple.com/")!)
    }
}
