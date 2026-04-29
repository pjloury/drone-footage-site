package com.pjloury.drones;

import android.app.Activity;
import android.graphics.Color;
import android.os.Bundle;
import android.view.KeyEvent;
import android.view.View;
import android.view.ViewGroup;
import android.view.Window;
import android.view.WindowManager;
import android.webkit.WebChromeClient;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.FrameLayout;
import android.widget.ProgressBar;

/**
 * Full-screen WebView activity that loads drones.pjloury.com.
 * Designed for Google TV / Android TV — handles D-pad navigation
 * and keeps the experience immersive.
 */
public class MainActivity extends Activity {

    private static final String SITE_URL = "https://drones.pjloury.com";

    private WebView webView;
    private ProgressBar progressBar;
    private View customFullscreenView;
    private WebChromeClient.CustomViewCallback customFullscreenCallback;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        // Full-screen immersive
        requestWindowFeature(Window.FEATURE_NO_TITLE);
        getWindow().setFlags(
                WindowManager.LayoutParams.FLAG_FULLSCREEN,
                WindowManager.LayoutParams.FLAG_FULLSCREEN
        );
        getWindow().getDecorView().setSystemUiVisibility(
                View.SYSTEM_UI_FLAG_FULLSCREEN
                        | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                        | View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
        );

        setContentView(R.layout.activity_main);

        progressBar = findViewById(R.id.progress_bar);
        webView = findViewById(R.id.webview);

        configureWebView();
        webView.loadUrl(SITE_URL);
    }

    private void configureWebView() {
        WebSettings settings = webView.getSettings();

        // Enable JavaScript (required for the video player)
        settings.setJavaScriptEnabled(true);

        // Enable DOM storage and media playback
        settings.setDomStorageEnabled(true);
        settings.setMediaPlaybackRequiresUserGesture(false);

        // Allow mixed content (shouldn't be needed, but just in case)
        settings.setMixedContentMode(WebSettings.MIXED_CONTENT_COMPATIBILITY_MODE);

        // Cache for faster reloads
        settings.setCacheMode(WebSettings.LOAD_DEFAULT);

        // Set a desktop-like user agent so the site doesn't serve mobile layout
        String defaultUA = settings.getUserAgentString();
        settings.setUserAgentString(defaultUA + " GoogleTV DronesApp/1.0");

        // Handle navigation inside the WebView (don't open external browser)
        webView.setWebViewClient(new WebViewClient() {
            @Override
            public void onPageFinished(WebView view, String url) {
                super.onPageFinished(view, url);
                progressBar.setVisibility(View.GONE);
            }
        });

        // Show loading progress + handle the HTML5 Fullscreen API. The site
        // doesn't currently call requestFullscreen(), but if it ever does
        // (or if we add a "go fullscreen" affordance later) Android needs an
        // onShowCustomView/onHideCustomView pair or the page silently fails.
        webView.setWebChromeClient(new WebChromeClient() {
            @Override
            public void onProgressChanged(WebView view, int newProgress) {
                if (newProgress < 100) {
                    progressBar.setVisibility(View.VISIBLE);
                    progressBar.setProgress(newProgress);
                } else {
                    progressBar.setVisibility(View.GONE);
                }
            }

            @Override
            public void onShowCustomView(View view, CustomViewCallback callback) {
                if (customFullscreenView != null) {
                    callback.onCustomViewHidden();
                    return;
                }
                customFullscreenView = view;
                customFullscreenCallback = callback;
                FrameLayout decor = (FrameLayout) getWindow().getDecorView();
                decor.addView(view, new FrameLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT,
                        ViewGroup.LayoutParams.MATCH_PARENT));
            }

            @Override
            public void onHideCustomView() {
                if (customFullscreenView == null) return;
                FrameLayout decor = (FrameLayout) getWindow().getDecorView();
                decor.removeView(customFullscreenView);
                customFullscreenView = null;
                if (customFullscreenCallback != null) {
                    customFullscreenCallback.onCustomViewHidden();
                    customFullscreenCallback = null;
                }
            }
        });

        // Black background to match the site
        webView.setBackgroundColor(Color.BLACK);
    }

    /**
     * Handle D-pad / remote control keys.
     *   LEFT  → previous video (clicks left edge nav button, falls back to
     *           a synthetic edge click which the site's doc-level handler
     *           catches)
     *   RIGHT / CENTER / ENTER → next video (mirror of the above)
     *   UP / DOWN → toggle the welcome card (matches the site's keyboard
     *           handler for ArrowUp/ArrowDown)
     *   BACK → standard webView history if applicable; otherwise falls
     *           through and exits the app (default Android behavior).
     */
    @Override
    public boolean onKeyDown(int keyCode, KeyEvent event) {
        switch (keyCode) {
            case KeyEvent.KEYCODE_DPAD_LEFT:
                webView.evaluateJavascript(
                    "(function(){" +
                    "  var b=document.getElementById('nav-left');" +
                    "  if(b){b.click();return;}" +
                    "  var x=window.innerWidth*0.1, y=window.innerHeight/2;" +
                    "  var el=document.elementFromPoint(x,y);" +
                    "  if(el)el.dispatchEvent(new MouseEvent('click',{bubbles:true,clientX:x,clientY:y}));" +
                    "})();",
                    null
                );
                return true;

            case KeyEvent.KEYCODE_DPAD_RIGHT:
            case KeyEvent.KEYCODE_DPAD_CENTER:
            case KeyEvent.KEYCODE_ENTER:
                webView.evaluateJavascript(
                    "(function(){" +
                    "  var b=document.getElementById('nav-right');" +
                    "  if(b){b.click();return;}" +
                    "  var x=window.innerWidth*0.9, y=window.innerHeight/2;" +
                    "  var el=document.elementFromPoint(x,y);" +
                    "  if(el)el.dispatchEvent(new MouseEvent('click',{bubbles:true,clientX:x,clientY:y}));" +
                    "})();",
                    null
                );
                return true;

            case KeyEvent.KEYCODE_DPAD_UP:
            case KeyEvent.KEYCODE_DPAD_DOWN:
                // Welcome overlay toggle — site exposes it as a click on #welcome
                webView.evaluateJavascript(
                    "document.getElementById('welcome')?.click();",
                    null
                );
                return true;

            case KeyEvent.KEYCODE_BACK:
                // If a fullscreen video is up, exit fullscreen first
                if (customFullscreenView != null) {
                    webView.evaluateJavascript(
                        "if(document.fullscreenElement)document.exitFullscreen();", null);
                    return true;
                }
                if (webView.canGoBack()) {
                    webView.goBack();
                    return true;
                }
                break;
        }
        return super.onKeyDown(keyCode, event);
    }

    @Override
    protected void onResume() {
        super.onResume();
        webView.onResume();
        // Re-enter immersive mode
        getWindow().getDecorView().setSystemUiVisibility(
                View.SYSTEM_UI_FLAG_FULLSCREEN
                        | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                        | View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
        );
    }

    @Override
    protected void onPause() {
        super.onPause();
        webView.onPause();
    }

    @Override
    protected void onDestroy() {
        webView.destroy();
        super.onDestroy();
    }
}
