#if REELS_FREE
import SwiftUI
import UIKit
import WebKit

/// Instagram in a web view, without Reels (PLAN.md section 6). Three layers:
///   1. a WKContentRuleList blocks network requests to Reels endpoints,
///   2. the navigation delegate cancels loads of /reels/, /reel/ and /explore/,
///   3. an injected script hides the Reels and Explore tabs and bounces in-page route
///      changes back to the feed.
/// The feed itself is not filtered; video posts in the feed still play.
@MainActor
final class InstagramBrowser: NSObject, ObservableObject {
    @Published private(set) var isLoading = false
    @Published private(set) var canGoBack = false
    @Published private(set) var loadError: String?
    /// Set when the filters could not be loaded; Instagram is not opened without them.
    @Published private(set) var setupError: String?
    @Published private(set) var networkFilterWarning: String?
    @Published private(set) var lastBlocked: Date?

    let webView: WKWebView
    private var rules: ReelsRules?
    private var started = false

    override init() {
        let configuration = WKWebViewConfiguration()
        // Persistent cookies, so the Instagram login sticks between visits.
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true
        let major = UIDevice.current.systemVersion.split(separator: ".").first.map(String.init) ?? "18"
        // Look like Mobile Safari, so Instagram serves its normal mobile site.
        configuration.applicationNameForUserAgent = "Version/\(major).0 Mobile/15E148 Safari/604.1"
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsLinkPreview = false
    }

    /// Loads the filters, then Instagram. Fails closed: without the filters nothing loads.
    func start() {
        guard !started else { return }
        started = true
        let rules: ReelsRules
        let script: String
        let ruleList: String
        do {
            rules = try ReelsRules.load(from: .main)
            script = try rules.script(from: .main)
            ruleList = try ReelsRules.contentRuleList(from: .main)
        } catch {
            setupError = error.localizedDescription
            DiagnosticsLog.shared()?.record(.app, "Reels filter not loaded: \(error.localizedDescription)")
            return
        }
        self.rules = rules

        let controller = webView.configuration.userContentController
        controller.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        controller.add(WeakScriptMessageHandler(self), name: ReelsRules.scriptMessageName)

        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "cmx.reels.v\(rules.version)",
            encodedContentRuleList: ruleList
        ) { [weak self] list, error in
            Task { @MainActor in
                guard let self else { return }
                if let list {
                    controller.add(list)
                } else {
                    // Layers 2 and 3 still work without the network filter.
                    let reason = error?.localizedDescription ?? "unknown error"
                    self.networkFilterWarning = "The network filter could not be loaded (\(reason)). Reels links are still refused."
                    DiagnosticsLog.shared()?.record(.app, "Reels content rules failed to compile: \(reason)")
                }
                self.webView.load(URLRequest(url: rules.feedURL))
            }
        }
    }

    func reload() {
        loadError = nil
        if webView.url == nil, let rules {
            webView.load(URLRequest(url: rules.feedURL))
        } else {
            webView.reload()
        }
    }

    func goBack() {
        webView.goBack()
    }

    func goHome() {
        guard let rules else { return }
        loadError = nil
        webView.load(URLRequest(url: rules.feedURL))
    }

    /// Shows "Reels and Explore are not available here" for three seconds.
    fileprivate func noteBlocked() {
        let now = Date()
        lastBlocked = now
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if self?.lastBlocked == now {
                self?.lastBlocked = nil
            }
        }
    }

    private func updateState() {
        isLoading = webView.isLoading
        canGoBack = webView.canGoBack
    }
}

extension InstagramBrowser: WKNavigationDelegate, WKUIDelegate {
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url, let rules else {
            decisionHandler(.cancel)
            return
        }
        switch url.scheme?.lowercased() {
        case "https", "http", "about", "blob", "data":
            break
        default:
            // instagram:// and other app links would leave for the (blocked) app.
            decisionHandler(.cancel)
            return
        }
        if rules.isBlocked(url) {
            decisionHandler(.cancel)
            noteBlocked()
            if navigationAction.targetFrame?.isMainFrame ?? true {
                webView.load(URLRequest(url: rules.feedURL))
            }
            return
        }
        decisionHandler(.allow)
    }

    /// Links that open a new window load in this view instead.
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        loadError = nil
        updateState()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        updateState()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handle(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handle(error)
    }

    private func handle(_ error: Error) {
        updateState()
        let nsError = error as NSError
        // Cancelled loads and loads stopped by our own policy are not failures.
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled { return }
        if nsError.domain == "WebKitErrorDomain", nsError.code == 102 { return }
        loadError = error.localizedDescription
        DiagnosticsLog.shared()?.record(.app, "Instagram web view failed to load: \(nsError.domain) \(nsError.code)")
    }
}

extension InstagramBrowser: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == ReelsRules.scriptMessageName {
            noteBlocked()
        }
    }
}

/// WKUserContentController keeps its message handlers strongly; this breaks the cycle.
private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: (any WKScriptMessageHandler)?

    init(_ target: any WKScriptMessageHandler) {
        self.target = target
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}

struct InstagramWebView: UIViewRepresentable {
    let browser: InstagramBrowser

    func makeUIView(context: Context) -> WKWebView {
        browser.webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}
}

/// The "Instagram (no Reels)" screen.
struct InstagramScreen: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var browser = InstagramBrowser()
    @State private var showingHelp = false

    var body: some View {
        NavigationStack {
            Group {
                if let setupError = browser.setupError {
                    ContentUnavailableView("Reels-free Instagram is unavailable",
                                           systemImage: "exclamationmark.triangle",
                                           description: Text(setupError))
                } else {
                    InstagramWebView(browser: browser)
                        .ignoresSafeArea(edges: .bottom)
                        .overlay {
                            if let error = browser.loadError {
                                loadFailure(error)
                            }
                        }
                }
            }
            .safeAreaInset(edge: .top) {
                VStack(spacing: 6) {
                    if let warning = browser.networkFilterWarning {
                        notice(warning, systemImage: "exclamationmark.triangle")
                    }
                    if browser.lastBlocked != nil {
                        notice("Reels and Explore are not available here.", systemImage: "nosign")
                    }
                }
                .animation(.default, value: browser.lastBlocked)
            }
            .navigationTitle("Instagram")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        browser.goBack()
                    } label: {
                        Image(systemName: "chevron.backward")
                    }
                    .disabled(!browser.canGoBack)
                    .accessibilityLabel("Back")
                    Button {
                        browser.goHome()
                    } label: {
                        Image(systemName: "house")
                    }
                    .accessibilityLabel("Feed")
                    Button {
                        showingHelp = true
                    } label: {
                        Image(systemName: "questionmark.circle")
                    }
                    .accessibilityLabel("Help")
                }
            }
            .alert("If this page is blocked", isPresented: $showingHelp) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("While the Instagram app is shielded, iOS may also block instagram.com in this view. If you see a block screen here, switch Settings → Advanced → Instagram strategy to \"Hide\" and pick Instagram there.")
            }
        }
        .task {
            browser.start()
        }
    }

    private func loadFailure(_ error: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Instagram did not load")
                .font(.headline)
            Text(error)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("If iOS is blocking instagram.com here too, try the \"Hide\" strategy in Settings → Advanced.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Try again") { browser.reload() }
                .buttonStyle(.borderedProminent)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }

    private func notice(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.footnote)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.thinMaterial, in: Capsule())
            .padding(.top, 4)
    }
}
#endif
