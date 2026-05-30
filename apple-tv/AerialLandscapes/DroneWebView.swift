//
//  DroneWebView.swift
//  AerialLandscapes
//
//  Full-screen WebView for drones.pjloury.com.
//  Active when FeatureFlags.useWebExperience is true.
//
//  Siri Remote → keyboard mapping:
//    ← / →          ArrowLeft / ArrowRight   prev / next clip
//    ↑ / ↓          ArrowUp   / ArrowDown    toggle name card
//    Select (click) Enter                     confirm section pick
//    Menu           Escape                    close section menu
//    Play/Pause     s                         open/close section menu
//

import SwiftUI
import WebKit

// MARK: - SwiftUI wrapper (used by ContentView)

struct DroneWebViewContainer: View {
    var body: some View {
        DroneWebViewRepresentable()
            .ignoresSafeArea()
            .background(Color.black)
    }
}

private struct DroneWebViewRepresentable: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> DroneWebViewController {
        DroneWebViewController()
    }
    func updateUIViewController(_ vc: DroneWebViewController, context: Context) {}
}

// MARK: - UIViewController

class DroneWebViewController: UIViewController {

    private var webView: WKWebView!

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

    // MARK: Setup

    private func setupWebView() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsAirPlayForMediaPlayback = true

        // IS_MOBILE is computed once when the page's <script> tag runs.
        // Overriding userAgent must happen at document-start so the value
        // is already in place before any JS evaluates.
        config.userContentController.addUserScript(WKUserScript(
            source: """
            Object.defineProperty(navigator, 'userAgent', {
                value: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Safari/605.1.15',
                writable: false, configurable: false
            });
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))

        webView = WKWebView(frame: view.bounds, configuration: config)
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.navigationDelegate = self
        // Also sets the HTTP User-Agent request header for the initial load
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

    // MARK: Siri Remote input

    private func jsKey(for type: UIPress.PressType) -> String? {
        switch type {
        case .leftArrow:  return "ArrowLeft"
        case .rightArrow: return "ArrowRight"
        case .upArrow:    return "ArrowUp"
        case .downArrow:  return "ArrowDown"
        case .select:     return "Enter"
        case .menu:       return "Escape"
        case .playPause:  return "s"   // open / close section picker
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

extension DroneWebViewController: WKNavigationDelegate {

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Belt-and-suspenders CSS so nav arrows stay readable on TV regardless
        // of any future JS changes on the site side.
        webView.evaluateJavaScript("""
            (function() {
                var s = document.createElement('style');
                s.textContent = [
                    '.nav-arrow        { opacity: 1    !important; pointer-events: auto !important; }',
                    '.nav-arrow.hidden { opacity: 0.35 !important; }',
                    '* { cursor: none !important; }'
                ].join('\\n');
                document.head.appendChild(s);
            })();
        """)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        // Apple TV may drop Wi-Fi briefly on wake from sleep — retry after 4 s
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            self?.load()
        }
    }
}
