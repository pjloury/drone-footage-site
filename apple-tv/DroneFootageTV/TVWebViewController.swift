import UIKit
import WebKit

// MARK: - TVWebViewController
//
// Wraps drones.pjloury.com in a fullscreen WKWebView and translates
// Siri Remote presses into the keyboard events the site already handles:
//
//   D-pad Left/Right  →  ArrowLeft / ArrowRight  →  prev / next clip
//   D-pad Up/Down     →  ArrowUp   / ArrowDown   →  toggle name card
//   Select (click)    →  Enter                   →  confirm section pick
//   Menu              →  Escape                  →  close section menu
//   Play/Pause        →  s                       →  open/close sections
//
// The desktop user-agent is injected at document-start so the site's
// IS_MOBILE check evaluates to false before any JS runs.  The ?tv=1
// parameter tells the site to keep nav arrows visible indefinitely and
// enable keyboard-driven section-menu navigation.

class TVWebViewController: UIViewController {

    private var webView: WKWebView!

    // MARK: - Setup

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupWebView()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
    }

    override var canBecomeFirstResponder: Bool { true }

    private func setupWebView() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsAirPlayForMediaPlayback = true

        // Inject desktop UA at document start — IS_MOBILE is evaluated once
        // when the script tag runs; changing navigator.userAgent afterwards
        // has no effect on IS_MOBILE.
        let desktopUA = WKUserScript(
            source: """
            Object.defineProperty(navigator, 'userAgent', {
                value: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Safari/605.1.15',
                writable: false, configurable: false
            });
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(desktopUA)

        webView = WKWebView(frame: view.bounds, configuration: config)
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.navigationDelegate = self
        // Also set the HTTP User-Agent header for the initial page request
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
            "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Safari/605.1.15 AppleTV/1.0"
        view.addSubview(webView)

        load()
    }

    private func load() {
        guard let url = URL(string: "https://drones.pjloury.com?tv=1") else { return }
        var req = URLRequest(url: url)
        req.cachePolicy = .returnCacheDataElseLoad
        webView.load(req)
    }

    // MARK: - Remote Input

    // Map UIPress types from the Siri Remote to the key strings the site
    // listens for.  Returns nil for presses we don't handle so they bubble
    // normally (e.g. the volume buttons, which go to the system).
    private func jsKey(for type: UIPress.PressType) -> String? {
        switch type {
        case .leftArrow:  return "ArrowLeft"
        case .rightArrow: return "ArrowRight"
        case .upArrow:    return "ArrowUp"
        case .downArrow:  return "ArrowDown"
        case .select:     return "Enter"
        case .menu:       return "Escape"
        case .playPause:  return "s"   // opens / closes the section menu
        default:          return nil
        }
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var handled = false
        for press in presses {
            if let key = jsKey(for: press.type) {
                fireKey(key)
                handled = true
            }
        }
        if !handled { super.pressesBegan(presses, with: event) }
    }

    // Dispatches a synthetic KeyboardEvent on document so the site's
    // existing keydown listeners handle it identically to a real keystroke.
    private func fireKey(_ key: String) {
        let safe = key.replacingOccurrences(of: "'", with: "\\'")
        webView.evaluateJavaScript("""
            document.dispatchEvent(new KeyboardEvent('keydown', {
                key: '\(safe)', bubbles: true, cancelable: true
            }));
        """)
    }
}

// MARK: - WKNavigationDelegate

extension TVWebViewController: WKNavigationDelegate {

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Keep nav arrows readable even when .hidden is applied (they fade
        // to 35% rather than disappearing — still confirms direction presses).
        // Hide the cursor completely; it will never exist on a TV anyway.
        webView.evaluateJavaScript("""
            (function() {
                var s = document.createElement('style');
                s.textContent = [
                    '.nav-arrow          { opacity: 1    !important; pointer-events: auto !important; }',
                    '.nav-arrow.hidden   { opacity: 0.35 !important; }',
                    '* { cursor: none !important; }'
                ].join('\\n');
                document.head.appendChild(s);
            })();
        """)
    }

    // Retry on network failure (Apple TV may lose Wi-Fi briefly on wake)
    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            self?.load()
        }
    }
}
