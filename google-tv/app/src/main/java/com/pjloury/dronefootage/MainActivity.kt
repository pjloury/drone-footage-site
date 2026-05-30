package com.pjloury.dronefootage

import android.os.Bundle
import android.view.KeyEvent
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.appcompat.app.AppCompatActivity

// MainActivity
//
// Full-screen WebView wrapper for drones.pjloury.com, targeting Google TV /
// Android TV.  D-pad events from the TV remote are translated into synthetic
// KeyboardEvents that the site already listens for:
//
//   D-pad Left / Right   →  ArrowLeft / ArrowRight  →  prev / next clip
//   D-pad Up / Down      →  ArrowUp   / ArrowDown   →  toggle name card
//   D-pad Centre / Enter →  Enter                   →  confirm section pick
//   Back                 →  Escape                  →  close section menu
//   Play/Pause           →  s                       →  open/close section menu

class MainActivity : AppCompatActivity() {

    private lateinit var webView: WebView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
        setupWebView()
    }

    private fun setupWebView() {
        webView = findViewById(R.id.webview)

        webView.settings.apply {
            javaScriptEnabled = true
            // Allow autoplay without user interaction
            mediaPlaybackRequiresUserGesture = false
            domStorageEnabled = true
            loadWithOverviewMode = true
            useWideViewPort = true
            // Desktop UA — keeps the site out of mobile-quality mode
            userAgentString = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
                "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36 GoogleTV/1.0"
            cacheMode = WebSettings.LOAD_DEFAULT
            mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
        }

        webView.webViewClient = object : WebViewClient() {
            override fun onPageFinished(view: WebView, url: String) {
                injectTVStyles(view)
            }
            // Keep all navigation inside this WebView
            override fun shouldOverrideUrlLoading(
                view: WebView,
                request: WebResourceRequest
            ) = false
        }

        // Allow video to go fullscreen if the site requests it
        webView.webChromeClient = WebChromeClient()

        webView.loadUrl(SITE_URL)
    }

    // Keep nav arrows visible at reduced opacity even when .hidden is applied.
    // The site hides them after 5 s on desktop but IS_TV disables that timer.
    // This CSS is belt-and-suspenders for any edge case.
    private fun injectTVStyles(view: WebView) {
        view.evaluateJavascript(
            """
            (function() {
                var s = document.createElement('style');
                s.textContent = [
                    '.nav-arrow          { opacity: 1    !important; pointer-events: auto !important; }',
                    '.nav-arrow.hidden   { opacity: 0.35 !important; }',
                    '* { cursor: none !important; }'
                ].join('\n');
                document.head.appendChild(s);
            })();
            """.trimIndent(),
            null
        )
    }

    // MARK: - Remote input

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        // Only act on key-down; let key-up events pass through normally
        if (event.action != KeyEvent.ACTION_DOWN) return super.dispatchKeyEvent(event)

        val jsKey = when (event.keyCode) {
            KeyEvent.KEYCODE_DPAD_LEFT              -> "ArrowLeft"
            KeyEvent.KEYCODE_DPAD_RIGHT             -> "ArrowRight"
            KeyEvent.KEYCODE_DPAD_UP                -> "ArrowUp"
            KeyEvent.KEYCODE_DPAD_DOWN              -> "ArrowDown"
            KeyEvent.KEYCODE_DPAD_CENTER,
            KeyEvent.KEYCODE_ENTER,
            KeyEvent.KEYCODE_NUMPAD_ENTER           -> "Enter"
            KeyEvent.KEYCODE_BACK                   -> "Escape"
            KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE,
            KeyEvent.KEYCODE_MEDIA_PLAY,
            KeyEvent.KEYCODE_MEDIA_PAUSE            -> "s"
            else -> return super.dispatchKeyEvent(event)
        }

        fireKeyEvent(jsKey)
        return true
    }

    // Dispatches a synthetic KeyboardEvent so the site's existing keydown
    // listeners handle it identically to a real keystroke from a keyboard.
    private fun fireKeyEvent(key: String) {
        val safe = key.replace("'", "\\'")
        webView.evaluateJavascript(
            """
            document.dispatchEvent(new KeyboardEvent('keydown', {
                key: '$safe', bubbles: true, cancelable: true
            }));
            """.trimIndent(),
            null
        )
    }

    @Deprecated("Use OnBackPressedDispatcher instead")
    override fun onBackPressed() {
        if (webView.canGoBack()) webView.goBack()
        else super.onBackPressed()
    }

    companion object {
        private const val SITE_URL = "https://drones.pjloury.com?tv=1"
    }
}
