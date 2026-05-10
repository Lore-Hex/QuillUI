// QuillWebKit
// ===========
// WebKit (WK*) shadow types for platforms where Apple's WebKit isn't
// available (Linux, server-side macOS without WebKit). On real Apple
// platforms QuillFoundation already re-exports the system WebKit module
// so this file is essentially empty there.

import QuillFoundation

#if !os(macOS) && !os(iOS)

public enum WKAudiovisualMediaTypes: Int, Sendable {
    case all = 1
}

@MainActor open class WKWebView: @unchecked Sendable {
    public init() {}
    public init(frame: CGRect, configuration: WKWebViewConfiguration) {}
    public init(coder: NSCoder) {}
    public var configuration = WKWebViewConfiguration()
    public weak var navigationDelegate: WKNavigationDelegate?
    public func loadFileURL(_: URL, allowingReadAccessTo: URL) {}
    public func reload() {}
    @MainActor public func evaluateJavaScript(_: String) async throws -> Any? { nil }
    public func load(_: URLRequest) -> WKNavigation? { nil }
    public func loadHTMLString(_: String, baseURL: URL?) -> WKNavigation? { nil }
    public func stopLoading() {}
}

public class WKContentRuleList: NSObject {}

public class WKUserContentController: NSObject {
    public func addUserScript(_: WKUserScript) {}
    public func add(_: WKContentRuleList) {}
    public func removeAllUserScripts() {}
}

public class WKWebViewConfiguration: NSObject {
    public var preferences: WKPreferences
    public var defaultWebpagePreferences: WKWebpagePreferences
    public var mediaTypesRequiringUserActionForPlayback: WKAudiovisualMediaTypes = .all

    public override init() {
        self.preferences = WKPreferences()
        self.defaultWebpagePreferences = WKWebpagePreferences()
        super.init()
    }

    public func setURLSchemeHandler(_: Any?, forURLScheme: String) {}
    public var userContentController = WKUserContentController()
}

public protocol WKURLSchemeHandler: AnyObject {}

public class WKPreferences: NSObject {
    public var javaScriptCanOpenWindowsAutomatically = false
    public var minimumFontSize: CGFloat = 0
    public var isElementFullscreenEnabled = true
}

public class WKWebpagePreferences: NSObject {
    public var allowsContentJavaScript = true
}

public enum WKUserScriptInjectionTime: Int, Sendable {
    case atDocumentStart, atDocumentEnd
}

public class WKUserScript: NSObject {
    public init(source: String, injectionTime: WKUserScriptInjectionTime, forMainFrameOnly: Bool) {}
}

public class WKContentRuleListStore: NSObject {
    public static func `default`() -> WKContentRuleListStore { WKContentRuleListStore() }
    public func compileContentRuleList(forIdentifier: String, encodedContentRuleList: String) async throws -> WKContentRuleList? { nil }
}

@MainActor public protocol WKNavigationDelegate: AnyObject {
    func webView(_: WKWebView, didFinish: WKNavigation!)
}

public class WKNavigation: NSObject {}

public class WKNavigationAction: NSObject {
    public var request: URLRequest = URLRequest(url: URL(string: "about:blank")!)
}

public enum WKNavigationActionPolicy: Int, Sendable {
    case cancel, allow
}

#endif
