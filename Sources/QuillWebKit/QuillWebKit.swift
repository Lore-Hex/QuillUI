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

@MainActor open class WKWebView: NSView, @unchecked Sendable {
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
    public weak var uiDelegate: WKUIDelegate?
    /// Stored (not recomputed per access) so callers that mutate the scroll
    /// view -- e.g. CaptchaView tweaking inset/indicator behavior -- observe a
    /// stable instance, mirroring UIKit's `WKWebView.scrollView`.
    public private(set) lazy var scrollView = UIScrollView()
    public var allowsBackForwardNavigationGestures = false
    public var allowsLinkPreview = false
    public var obscuredContentInsets: NSEdgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    public var customUserAgent: String?
    public private(set) var lastLoadedFileURL: URL?
    public private(set) var lastReadAccessURL: URL?
    public private(set) var lastLoadedHTMLString: String?
    public private(set) var lastLoadedHTMLBaseURL: URL?
    public private(set) var evaluatedJavaScript: [String] = []
    public private(set) var isLoading = false
    public func loadFileURL(_ url: URL, allowingReadAccessTo readAccessURL: URL) {
        lastLoadedFileURL = url
        lastReadAccessURL = readAccessURL
        isLoading = true
        navigationDelegate?.webView(self, didCommit: WKNavigation())
    }
    public func reload() {}
    @MainActor public func evaluateJavaScript(_: String) async throws -> Any? { nil }
    public func evaluateJavaScript(_ javaScriptString: String, completionHandler: ((Any?, Error?) -> Void)? = nil) {
        evaluatedJavaScript.append(javaScriptString)
        completionHandler?(nil, nil)
    }
    public func load(_: URLRequest) -> WKNavigation? { nil }
    public func loadHTMLString(_ string: String, baseURL: URL?) -> WKNavigation? {
        lastLoadedHTMLString = string
        lastLoadedHTMLBaseURL = baseURL
        isLoading = true
        let navigation = WKNavigation()
        navigationDelegate?.webView(self, didFinish: navigation)
        return navigation
    }
    public func stopLoading() { isLoading = false }
}

public class WKContentRuleList: NSObject {
    public let identifier: String
    public let encodedContentRuleList: String

    public init(identifier: String = "", encodedContentRuleList: String = "") {
        self.identifier = identifier
        self.encodedContentRuleList = encodedContentRuleList
        super.init()
    }
}

public class WKUserContentController: NSObject {
    public private(set) var quillUserScripts: [WKUserScript] = []
    public private(set) var quillContentRuleLists: [WKContentRuleList] = []
    public private(set) var quillScriptMessageHandlers: [String: WKScriptMessageHandler] = [:]

    public func addUserScript(_ userScript: WKUserScript) {
        quillUserScripts.append(userScript)
    }

    public func add(_ contentRuleList: WKContentRuleList) {
        guard !quillContentRuleLists.contains(where: { $0 === contentRuleList }) else {
            return
        }
        quillContentRuleLists.append(contentRuleList)
    }

    public func add(_ scriptMessageHandler: WKScriptMessageHandler, name: String) {
        quillScriptMessageHandlers[name] = scriptMessageHandler
    }

    public func removeAllUserScripts() {
        quillUserScripts.removeAll()
    }

    public func removeScriptMessageHandler(forName name: String) {
        quillScriptMessageHandlers.removeValue(forKey: name)
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

    public private(set) var quillURLSchemeHandlers: [String: Any] = [:]

    public func setURLSchemeHandler(_ handler: Any?, forURLScheme scheme: String) {
        if let handler {
            quillURLSchemeHandlers[scheme] = handler
        } else {
            quillURLSchemeHandlers.removeValue(forKey: scheme)
        }
    }

    public var userContentController = WKUserContentController()
}

public class WKWebsiteDataStore: NSObject, @unchecked Sendable {
    private static let defaultStore = WKWebsiteDataStore()
    private static let nonPersistentStore = WKWebsiteDataStore()

    public static func `default`() -> WKWebsiteDataStore { defaultStore }
    public static func nonPersistent() -> WKWebsiteDataStore { nonPersistentStore }
}

@MainActor public protocol WKURLSchemeHandler: AnyObject {
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask)
    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask)
}

public extension WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        _ = (webView, urlSchemeTask)
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        _ = (webView, urlSchemeTask)
    }
}

open class WKURLSchemeTask: NSObject {
    public let request: URLRequest
    public private(set) var receivedResponses: [URLResponse] = []
    public private(set) var receivedData: [Data] = []
    public private(set) var isFinished = false
    public private(set) var error: Error?

    public init(request: URLRequest) {
        self.request = request
        super.init()
    }

    open func didReceive(_ response: URLResponse) {
        receivedResponses.append(response)
    }

    open func didReceive(_ data: Data) {
        receivedData.append(data)
    }

    open func didFinish() {
        isFinished = true
    }

    open func didFailWithError(_ error: Error) {
        self.error = error
    }
}

public enum WKNavigationResponsePolicy: Int, Sendable {
    case cancel
    case allow
}

public class WKNavigationResponse: NSObject {}

public class WKPreferences: NSObject {
    public var javaScriptCanOpenWindowsAutomatically = false
    public var minimumFontSize: CGFloat = 0
    public var isElementFullscreenEnabled = true
    public var _developerExtrasEnabled = false
}

public class WKWebpagePreferences: NSObject {
    public var allowsContentJavaScript = true
}

public enum WKUserScriptInjectionTime: Int, Sendable {
    case atDocumentStart, atDocumentEnd
}

public class WKUserScript: NSObject {
    public let source: String
    public let injectionTime: WKUserScriptInjectionTime
    public let isForMainFrameOnly: Bool

    public init(source: String, injectionTime: WKUserScriptInjectionTime, forMainFrameOnly: Bool) {
        self.source = source
        self.injectionTime = injectionTime
        self.isForMainFrameOnly = forMainFrameOnly
        super.init()
    }
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
    public func compileContentRuleList(forIdentifier: String, encodedContentRuleList: String) async throws -> WKContentRuleList? {
        WKContentRuleList(identifier: forIdentifier, encodedContentRuleList: encodedContentRuleList)
    }
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
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
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
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
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

public enum WKNavigationType: Int, Sendable {
    case linkActivated
    case formSubmitted
    case backForward
    case reload
    case formResubmitted
    case other = -1
}

public class WKNavigationAction: NSObject {
    public var request: URLRequest = URLRequest(url: URL(string: "about:blank")!)
    public var navigationType: WKNavigationType = .other
    public var modifierFlags: NSEvent.ModifierFlags = []

    public init(
        request: URLRequest = URLRequest(url: URL(string: "about:blank")!),
        navigationType: WKNavigationType = .other,
        modifierFlags: NSEvent.ModifierFlags = []
    ) {
        self.request = request
        self.navigationType = navigationType
        self.modifierFlags = modifierFlags
        super.init()
    }
}

public enum WKNavigationActionPolicy: Int, Sendable {
    case cancel, allow
}

public class WKWindowFeatures: NSObject {}

@MainActor public protocol WKUIDelegate: AnyObject {
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView?
}

public extension WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        _ = (webView, configuration, navigationAction, windowFeatures)
        return nil
    }
}

#endif
