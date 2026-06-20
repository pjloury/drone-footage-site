import SwiftUI
import WebKit

struct WebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsAirPlayForMediaPlayback = true
        config.allowsPictureInPictureMediaPlayback = false

        // WKWebView on iOS sometimes resolves play() but doesn't advance
        // currentTime (renderer suspended). Retry any video stuck at t=0
        // after the page has had 2s to initialise.
        let retryScript = WKUserScript(
            source: """
            window.addEventListener('load', function() {
                setTimeout(function() {
                    document.querySelectorAll('video').forEach(function(v) {
                        if (v.currentTime < 0.1) {
                            v.play().catch(function(){});
                        }
                    });
                }, 2000);
            });
            """,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(retryScript)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        // Do NOT set isOpaque = false — breaks AVFoundation's hardware video
        // compositor path on iOS (video layer can't render into transparent layer)
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView,
                     decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(.allow)
        }
    }
}
