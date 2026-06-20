/**
 * InAppAuthWebView Plugin Definitions
 * TypeScript definitions converted to JSDoc for JavaScript projects
 * @module InAppAuthWebView
 */

/**
 * Options for showing the in-app authentication WebView
 * @typedef {Object} InAppAuthWebViewShowOptions
 * @property {string} url - The URL to load in the WebView
 * @property {string} [successUrlPattern="audiobookshelf://"] - URL pattern that indicates successful authentication
 * @property {string} [errorUrlPattern=""] - URL pattern that indicates an error occurred
 * @property {string} [title="Authentication"] - Title to display in the toolbar (iOS only)
 * @property {boolean} [showToolbar=true] - Whether to show the toolbar with a Done button (iOS only)
 * @property {boolean} [enableJavaScript=true] - Enable JavaScript in the WebView
 * @property {boolean} [enableDomStorage=true] - Enable DOM storage in the WebView (Android only)
 */

/**
 * Result from showing the WebView
 * @typedef {Object} InAppAuthWebViewShowResult
 * @property {string} url - The final URL that triggered the completion
 * @property {string} [error] - Error message if the completion was triggered by an error pattern
 */

/**
 * Options for getting cookies
 * @typedef {Object} InAppAuthWebViewGetCookiesOptions
 * @property {string} url - The URL to get cookies for
 */

/**
 * Result from getting cookies
 * @typedef {Object} InAppAuthWebViewGetCookiesResult
 * @property {Object<string, string>} cookies - Map of cookie names to values
 */

/**
 * InAppAuthWebView Plugin Interface
 * @interface InAppAuthWebViewPlugin
 * @property {function(InAppAuthWebViewShowOptions): Promise<InAppAuthWebViewShowResult>} show - Show the in-app authentication WebView
 * @property {function(): Promise<void>} hide - Hide the in-app authentication WebView
 * @property {function(InAppAuthWebViewGetCookiesOptions): Promise<InAppAuthWebViewGetCookiesResult>} getCookies - Get cookies for a specific URL from the shared cookie store
 */

export const InAppAuthWebViewShowOptions = 'InAppAuthWebViewShowOptions';
export const InAppAuthWebViewShowResult = 'InAppAuthWebViewShowResult';
export const InAppAuthWebViewGetCookiesOptions = 'InAppAuthWebViewGetCookiesOptions';
export const InAppAuthWebViewGetCookiesResult = 'InAppAuthWebViewGetCookiesResult';
export const InAppAuthWebViewPlugin = 'InAppAuthWebViewPlugin';