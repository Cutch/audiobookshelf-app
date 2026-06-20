package com.audiobookshelf.app.plugins.InAppAuthWebView

import android.annotation.SuppressLint
import android.app.Activity
import android.graphics.Bitmap
import android.net.Uri
import android.os.Build
import android.util.Log
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import androidx.annotation.NonNull
import com.getcapacitor.JSObject
import com.getcapacitor.Plugin
import com.getcapacitor.PluginCall
import com.getcapacitor.PluginMethod
import com.getcapacitor.annotation.CapacitorPlugin

@CapacitorPlugin(name = "InAppAuthWebView")
class InAppAuthWebViewPlugin : Plugin() {

    private val TAG = "InAppAuthWebView"
    private var authWebView: WebView? = null
    private var webViewContainer: FrameLayout? = null
    private var pendingCall: PluginCall? = null
    private var successUrlPattern = "audiobookshelf://"
    private var errorUrlPattern = ""
    private var isShowing = false

    @PluginMethod
    fun show(call: PluginCall) {
        val url = call.getString("url") ?: ""
        successUrlPattern = call.getString("successUrlPattern") ?: "audiobookshelf://"
        errorUrlPattern = call.getString("errorUrlPattern") ?: ""
        val title = call.getString("title") ?: "Authentication"
        val showToolbar = call.getBoolean("showToolbar") == true
        val enableJavaScript = call.getBoolean("enableJavaScript") == true
        val enableDomStorage = call.getBoolean("enableDomStorage") == true

        if (url.isEmpty()) {
            call.reject("URL is required")
            return
        }

        if (isShowing) {
            call.reject("WebView is already showing")
            return
        }

        pendingCall = call
        showWebView(url, title, showToolbar, enableJavaScript, enableDomStorage)
    }

    @PluginMethod
    fun hide(call: PluginCall) {
        if (isShowing) {
            hideWebView()
            call.resolve()
        } else {
            call.reject("WebView is not showing")
        }
    }

    @PluginMethod
    fun getCookies(call: PluginCall) {
        val url = call.getString("url")
        if (url == null || url.isEmpty()) {
            call.reject("URL is required")
            return
        }

        val cookieManager = CookieManager.getInstance()
        val cookies = cookieManager.getCookie(url)

        val result = JSObject()
        if (cookies != null && cookies.isNotEmpty()) {
            val cookieMap = JSObject()
            val cookiePairs = cookies.split(";")
            for (pair in cookiePairs) {
                val trimmed = pair.trim()
                val equalsIndex = trimmed.indexOf('=')
                if (equalsIndex > 0) {
                    val key = trimmed.substring(0, equalsIndex)
                    val value = trimmed.substring(equalsIndex + 1)
                    cookieMap.put(key, value)
                } else if (trimmed.isNotEmpty()) {
                    cookieMap.put(trimmed, "")
                }
            }
            result.put("cookies", cookieMap)
        } else {
            result.put("cookies", JSObject())
        }
        call.resolve(result)
    }

    @SuppressLint("SetJavaScriptEnabled")
    private fun showWebView(url: String, title: String, showToolbar: Boolean,
                            enableJavaScript: Boolean, enableDomStorage: Boolean) {
        activity?.runOnUiThread {
            try {
                val activity = this.activity ?: return@runOnUiThread

                // Create WebView
                authWebView = WebView(activity.applicationContext)
                authWebView!!.layoutParams = FrameLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.MATCH_PARENT
                )

                val settings = authWebView!!.settings
                settings.javaScriptEnabled = enableJavaScript
                settings.domStorageEnabled = enableDomStorage
                settings.allowFileAccess = false
                settings.allowContentAccess = false
                settings.mixedContentMode = WebSettings.MIXED_CONTENT_COMPATIBILITY_MODE

                // IMPORTANT: Use the same CookieManager as the main app WebView
                // This ensures cookies are shared with CapacitorHttp requests
                val cookieManager = CookieManager.getInstance()
                cookieManager.setAcceptCookie(true)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                    cookieManager.setAcceptThirdPartyCookies(authWebView!!, true)
                }

                // Create container
                webViewContainer = FrameLayout(activity)
                webViewContainer!!.layoutParams = FrameLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.MATCH_PARENT
                )
                webViewContainer!!.addView(authWebView!!)

                // Set OnKeyListener to handle back button
                authWebView!!.setOnKeyListener(View.OnKeyListener { _, keyCode, event ->
                    if (keyCode == KeyEvent.KEYCODE_BACK && event.action == KeyEvent.ACTION_DOWN) {
                        if (authWebView!!.canGoBack()) {
                            authWebView!!.goBack()
                            return@OnKeyListener true
                        } else {
                            hideWebView()
                            pendingCall?.let { call ->
                                call.resolve(JSObject().apply { put("dismissed", true) })
                                pendingCall = null
                            }
                            return@OnKeyListener true
                        }
                    }
                    false
                })

                // Set WebViewClient to handle navigation
                authWebView!!.webViewClient = object : WebViewClient() {
                    override fun onPageStarted(view: WebView?, url: String?, favicon: Bitmap?) {
                        super.onPageStarted(view, url, favicon)
                        url?.let {
                            Log.d(TAG, "Page started: $it")
                            checkUrlAndFinish(it)
                        }
                    }

                    override fun onPageFinished(view: WebView?, url: String?) {
                        super.onPageFinished(view, url)
                        url?.let { Log.d(TAG, "Page finished: $it") }
                    }
                    override fun onReceivedError(view: WebView?, request: WebResourceRequest?, error: WebResourceError?) {
                        super.onReceivedError(view, request, error)
                        Log.e(TAG, "WebView error: ${error?.description}")
                        pendingCall?.let { call ->
                            val result = JSObject()
                            request?.url?.let { result.put("url", it.toString()) }
                            error?.description?.let { result.put("error", it.toString()) }
                            call.resolve(result)
                            pendingCall = null
                        }
                        hideWebView()
                    }

                    override fun shouldOverrideUrlLoading(view: WebView?, request: WebResourceRequest?): Boolean {
                        val url = request?.url?.toString() ?: return false
                        Log.d(TAG, "Should override URL: $url")
                        return checkUrlAndFinish(url)
                    }

                    @Suppress("DEPRECATION")
                    override fun shouldOverrideUrlLoading(view: WebView?, url: String?): Boolean {
                        url?.let {
                            Log.d(TAG, "Should override URL (deprecated): $it")
                            return checkUrlAndFinish(it)
                        }
                        return false
                    }
                }

                // Add to activity
                val decorView = activity.window.decorView as ViewGroup
                decorView.addView(webViewContainer!!)

                // Load URL
                authWebView!!.loadUrl(url)
                isShowing = true

            } catch (e: Exception) {
                Log.e(TAG, "Error showing WebView", e)
                rejectPendingCall(e.message ?: "Unknown error")
            }
        }
    }

    private fun checkUrlAndFinish(url: String): Boolean {
        // Ignore known authentication callback URLs that are intermediate steps
        // Cloudflare Access uses /cdn-cgi/access/authorized for its callback
        if (url.contains("/cdn-cgi/access/authorized") || url.contains("/cdn-cgi/access/callback")) {
            Log.d(TAG, "Ignoring Cloudflare Access callback URL: $url")
            return false
        }

        // Check for success pattern
        if (successUrlPattern.isNotEmpty() && url.contains(successUrlPattern)) {
            Log.d(TAG, "Success URL matched: $url")
            finishWithResult(url, null)
            return true
        }

        // Check for error pattern
        if (errorUrlPattern.isNotEmpty() && url.contains(errorUrlPattern)) {
            Log.d(TAG, "Error URL matched: $url")
            finishWithResult(url, "Navigation matched error pattern")
            return true
        }

        return false
    }

    private fun finishWithResult(url: String, error: String?) {
        pendingCall?.let { call ->
            val result = JSObject()
            result.put("url", url)
            error?.let { result.put("error", it) }
            call.resolve(result)
            pendingCall = null
        }
        hideWebView()
    }

    private fun hideWebView() {
        activity?.runOnUiThread {
            webViewContainer?.let { container ->
                val decorView = activity?.window?.decorView as? ViewGroup
                decorView?.removeView(container)
                webViewContainer = null
            }
            authWebView?.destroy()
            authWebView = null
            isShowing = false
        }
    }

    private fun rejectPendingCall(message: String) {
        pendingCall?.let {
            it.reject(message)
            pendingCall = null
        }
    }

    override fun handleOnDestroy() {
        super.handleOnDestroy()
        if (isShowing) {
            hideWebView()
            pendingCall?.let {
                it.reject("Activity destroyed")
                pendingCall = null
            }
        }
    }
}
