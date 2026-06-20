import Foundation
import Capacitor
import WebKit

@objc(InAppAuthWebViewPlugin)
public class InAppAuthWebViewPlugin: CAPPlugin, WKNavigationDelegate, WKUIDelegate {

    private var webView: WKWebView?
    private var webViewController: InAppAuthWebViewController?
    private var pendingCall: CAPPluginCall?
    private var successUrlPattern: String = "audiobookshelf://"
    private var errorUrlPattern: String = ""

    @objc func show(_ call: CAPPluginCall) {
        guard let urlString = call.getString("url"),
              let url = URL(string: urlString) else {
            call.reject("Invalid URL")
            return
        }

        self.successUrlPattern = call.getString("successUrlPattern", "audiobookshelf://")
        self.errorUrlPattern = call.getString("errorUrlPattern", "")
        let title = call.getString("title", "Authentication")
        let showToolbar = call.getBool("showToolbar", true)
        let enableJavaScript = call.getBool("enableJavaScript", true)

        if webViewController != nil {
            call.reject("WebView is already showing")
            return
        }

        pendingCall = call

        DispatchQueue.main.async {
            self.presentWebView(url: url, title: title, showToolbar: showToolbar, enableJavaScript: enableJavaScript)
        }
    }

    @objc func hide(_ call: CAPPluginCall) {
        if webViewController != nil {
            dismissWebView()
            call.resolve()
        } else {
            call.reject("WebView is not showing")
        }
    }

    @objc func getCookies(_ call: CAPPluginCall) {
        guard let urlString = call.getString("url"),
              let url = URL(string: urlString) else {
            call.reject("Invalid URL")
            return
        }

        // Use the shared WKHTTPCookieStore from the main WebView
        // This ensures cookies are shared with CapacitorHttp requests
        let cookieStore = WKWebsiteDataStore.default().httpCookieStore
        cookieStore.getAllCookies { cookies in
            var cookieDict: [String: String] = [:]
            for cookie in cookies where cookie.domain == url.host || url.host?.hasSuffix(cookie.domain) == true {
                cookieDict[cookie.name] = cookie.value
            }

            call.resolve([
                "cookies": cookieDict
            ])
        }
    }

    private func presentWebView(url: URL, title: String, showToolbar: Bool, enableJavaScript: Bool) {
        guard let bridge = bridge, let webView = bridge.webView else {
            rejectPendingCall("Bridge or main WebView not available")
            return
        }

        // Create configuration sharing the same process pool and cookie store as main WebView
        let configuration = WKWebViewConfiguration()
        configuration.processPool = webView.configuration.processPool
        configuration.websiteDataStore = WKWebsiteDataStore.default() // Shares cookies with main app

        // Enable JavaScript
        configuration.preferences.javaScriptEnabled = enableJavaScript

        // Create WKWebView
        let authWebView = WKWebView(frame: .zero, configuration: configuration)
        authWebView.navigationDelegate = self
        authWebView.uiDelegate = self
        authWebView.allowsBackForwardNavigationGestures = true

        // Create view controller
        let webViewController = InAppAuthWebViewController()
        webViewController.webView = authWebView
        webViewController.title = title
        webViewController.showToolbar = showToolbar
        webViewController.onDismiss = { [weak self] in
            self?.dismissWebView()
        }

        self.webView = authWebView
        self.webViewController = webViewController

        // Load URL
        authWebView.load(URLRequest(url: url))

        // Present modally
        if let presentingVC = bridge.viewController {
            let navController = UINavigationController(rootViewController: webViewController)
            navController.modalPresentationStyle = .formSheet
            presentingVC.present(navController, animated: true)
        } else {
            rejectPendingCall("No presenting view controller")
        }
    }

    private func dismissWebView() {
        DispatchQueue.main.async { [weak self] in
            self?.webViewController?.dismiss(animated: true) {
                self?.webView = nil
                self?.webViewController = nil
            }
        }
    }

    private func finishWithResult(url: URL, error: String? = nil) {
        if let call = pendingCall {
            var result: [String: Any] = ["url": url.absoluteString]
            if let error = error {
                result["error"] = error
            }
            call.resolve(result)
            pendingCall = nil
        }
        dismissWebView()
    }

    private func rejectPendingCall(_ message: String) {
        if let call = pendingCall {
            call.reject(message)
            pendingCall = nil
        }
    }

    // MARK: - WKNavigationDelegate

    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let url = navigationAction.request.url

        if let url = url {
            let urlString = url.absoluteString
            print("[InAppAuthWebView] Navigation: \(urlString)")

            // Ignore known authentication callback URLs that are intermediate steps
            // Cloudflare Access uses /cdn-cgi/access/authorized for its callback
            if urlString.contains("/cdn-cgi/access/authorized") || urlString.contains("/cdn-cgi/access/callback") {
                print("[InAppAuthWebView] Ignoring Cloudflare Access callback URL: \(urlString)")
                decisionHandler(.allow)
                return
            }

            // Check for success pattern
            if !successUrlPattern.isEmpty && urlString.contains(successUrlPattern) {
                print("[InAppAuthWebView] Success URL matched: \(urlString)")
                finishWithResult(url: url)
                decisionHandler(.cancel)
                return
            }

            // Check for error pattern
            if !errorUrlPattern.isEmpty && urlString.contains(errorUrlPattern) {
                print("[InAppAuthWebView] Error URL matched: \(urlString)")
                finishWithResult(url: url, error: "Navigation matched error pattern")
                decisionHandler(.cancel)
                return
            }

            // Handle external links (open in system browser)
            if navigationAction.navigationType == .linkActivated,
               let scheme = url.scheme,
               ["http", "https"].contains(scheme),
               url.host != self.bridge?.webView?.url?.host {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }
        }

        decisionHandler(.allow)
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        print("[InAppAuthWebView] Navigation failed: \(error)")
        finishWithResult(url: webView.url ?? URL(string: "about:blank")!, error: error.localizedDescription)
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("[InAppAuthWebView] Navigation failed: \(error)")
        finishWithResult(url: webView.url ?? URL(string: "about:blank")!, error: error.localizedDescription)
    }

    // MARK: - WKUIDelegate

    public func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        // Handle target="_blank" links
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }
}

// MARK: - Custom View Controller

class InAppAuthWebViewController: UIViewController {

    var webView: WKWebView?
    var showToolbar: Bool = true
    var onDismiss: (() -> Void)?

    private var toolbar: UIToolbar?
    private var progressView: UIProgressView?
    private var observation: NSKeyValueObservation?

    override func viewDidLoad() {
        super.viewDidLoad()

        guard let webView = webView else { return }

        view.backgroundColor = .systemBackground
        view.addSubview(webView)
        webView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        // Add toolbar if requested
        if showToolbar {
            setupToolbar()
        }

        // Add progress bar
        setupProgressBar()

        // Observe loading progress
        observation = webView.observe(\.estimatedProgress, options: .new) { [weak self] _, change in
            if let progress = change.newValue {
                self?.progressView?.setProgress(Float(progress), animated: true)
                self?.progressView?.isHidden = progress >= 1.0
            }
        }
    }

    private func setupToolbar() {
        let toolbar = UIToolbar()
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(toolbar)

        let flexibleSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let doneButton = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(doneTapped))

        toolbar.items = [flexibleSpace, doneButton]
        self.toolbar = toolbar

        NSLayoutConstraint.activate([
            toolbar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    private func setupProgressBar() {
        let progressView = UIProgressView(progressViewStyle: .bar)
        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.trackTintColor = .clear
        progressView.progressTintColor = .systemBlue
        view.addSubview(progressView)

        NSLayoutConstraint.activate([
            progressView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            progressView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            progressView.heightAnchor.constraint(equalToConstant: 2)
        ])

        self.progressView = progressView
    }

    @objc private func doneTapped() {
        onDismiss?()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        observation?.invalidate()
    }
}