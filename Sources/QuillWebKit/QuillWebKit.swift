// QuillWebKit
// ===========
// WebKit (WK*) shadow types for platforms where Apple's WebKit isn't
// available (Linux, server-side macOS without WebKit). On real Apple
// platforms QuillFoundation already re-exports the system WebKit module
// so this file is essentially empty there.

import QuillFoundation

#if !os(macOS) && !os(iOS)
import AppKit

public struct WKAudiovisualMediaTypes: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let audio = WKAudiovisualMediaTypes(rawValue: 1 << 0)
    public static let video = WKAudiovisualMediaTypes(rawValue: 1 << 1)
    public static let all: WKAudiovisualMediaTypes = [.audio, .video]
}

// On Apple platforms `WKWebView` is a `UIView` subclass (it inherits
// `addSubview`-ability, `layoutMargins`, and its `scrollView`). Signal's
// CaptchaView relies on all three (`addSubview(webView)`,
// `autoPinEdgesToSuperviewEdges`, `webView.layoutMargins = .zero`), so the
// shadow must subclass UIView -- not NSView -- to match.
@MainActor open class WKWebView: UIView, @unchecked Sendable {
    public override init(frame: CGRect) {
        super.init(frame: frame)
    }

    public convenience init() {
        self.init(frame: .zero)
    }

    public init(frame: CGRect, configuration: WKWebViewConfiguration) {
        self.configuration = configuration
        super.init(frame: frame)
    }

    /// Apple-exact `required init?(coder:)` (WKWebView adopts NSCoding there;
    /// QuillAppKit's NSView coder init is now `required` to match AppKit, so
    /// this override must be too). Coder ignored — no unarchiving on Linux.
    public required init?(coder: NSCoder) {
        super.init(frame: .zero)
    }

    public var configuration = WKWebViewConfiguration()
    public weak var navigationDelegate: WKNavigationDelegate?
    /// Stored (not recomputed per access) so callers that mutate the scroll
    /// view -- e.g. CaptchaView tweaking inset/indicator behavior -- observe a
    /// stable instance, mirroring UIKit's `WKWebView.scrollView`.
    public private(set) lazy var scrollView = UIScrollView()
    public var allowsBackForwardNavigationGestures = false
    public var allowsLinkPreview = false
    public var customUserAgent: String?
    public func loadFileURL(_: URL, allowingReadAccessTo: URL) {}
    public func reload() {}
    @MainActor public func evaluateJavaScript(_: String) async throws -> Any? { nil }
    public func evaluateJavaScript(_ javaScriptString: String, completionHandler: ((Any?, Error?) -> Void)? = nil) {
        completionHandler?(nil, nil)
    }
    public func load(_: URLRequest) -> WKNavigation? { nil }
    public func loadHTMLString(_: String, baseURL: URL?) -> WKNavigation? { nil }
    public func stopLoading() {}
}

public class WKContentRuleList: NSObject {}

public class WKUserContentController: NSObject {
    public func addUserScript(_: WKUserScript) {}
    public func add(_: WKContentRuleList) {}
    public func add(_ scriptMessageHandler: WKScriptMessageHandler, name: String) {
        _ = (scriptMessageHandler, name)
    }
    public func removeAllUserScripts() {}
    public func removeScriptMessageHandler(forName name: String) {
        _ = name
    }
}

public class WKWebViewConfiguration: NSObject {
    public var preferences: WKPreferences
    public var defaultWebpagePreferences: WKWebpagePreferences
    public var mediaTypesRequiringUserActionForPlayback: WKAudiovisualMediaTypes = .all
    public var websiteDataStore: WKWebsiteDataStore = .default()

    public override init() {
        self.preferences = WKPreferences()
        self.defaultWebpagePreferences = WKWebpagePreferences()
        super.init()
    }

    public func setURLSchemeHandler(_: Any?, forURLScheme: String) {}
    public var userContentController = WKUserContentController()
}

public class WKWebsiteDataStore: NSObject, @unchecked Sendable {
    private static let defaultStore = WKWebsiteDataStore()
    private static let nonPersistentStore = WKWebsiteDataStore()

    public static func `default`() -> WKWebsiteDataStore { defaultStore }
    public static func nonPersistent() -> WKWebsiteDataStore { nonPersistentStore }
}

public protocol WKURLSchemeHandler: AnyObject {}

public enum WKNavigationResponsePolicy: Int, Sendable {
    case cancel
    case allow
}

public class WKNavigationResponse: NSObject {}

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

public class WKScriptMessage: NSObject {
    public let name: String
    public let body: Any
    public weak var webView: WKWebView?

    public init(name: String = "", body: Any = NSNull(), webView: WKWebView? = nil) {
        self.name = name
        self.body = body
        self.webView = webView
        super.init()
    }
}

public protocol WKScriptMessageHandler: AnyObject {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage)
}

public class WKContentRuleListStore: NSObject {
    public static func `default`() -> WKContentRuleListStore { WKContentRuleListStore() }
    public func compileContentRuleList(forIdentifier: String, encodedContentRuleList: String) async throws -> WKContentRuleList? { nil }
}

// Apple's `WKNavigationDelegate` methods are ALL optional. Swift protocols
// have no `optional` outside `@objc`, so instead every method gets a default
// implementation in the extension below; conformers (CaptchaView) implement
// only the subset they need and still satisfy the protocol.
@MainActor public protocol WKNavigationDelegate: AnyObject {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!)
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error)
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error)
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!)
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!)
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    )
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    )
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView)
}

public extension WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {}
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {}
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {}
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {}
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {}
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        decisionHandler(.allow)
    }
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        decisionHandler(.allow)
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {}
}

public class WKNavigation: NSObject {}

public class WKNavigationAction: NSObject {
    public var request: URLRequest = URLRequest(url: URL(string: "about:blank")!)
}

public enum WKNavigationActionPolicy: Int, Sendable {
    case cancel, allow
}

#endif
