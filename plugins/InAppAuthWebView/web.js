import { WebPlugin } from '@capacitor/core';

/**
 * Web implementation of InAppAuthWebView (not functional - throws unimplemented)
 */
export class InAppAuthWebViewWeb extends WebPlugin {
  /**
   * Show the in-app authentication WebView
   * @param {Object} options - Options for showing the WebView
   * @returns {Promise<Object>} Result with URL and optional error
   */
  async show(options) {
    console.warn('InAppAuthWebView.show is not implemented on web');
    throw this.unimplemented('show() is not implemented on web platform. Use native iOS/Android.');
  }

  /**
   * Hide the in-app authentication WebView
   * @returns {Promise<void>}
   */
  async hide() {
    console.warn('InAppAuthWebView.hide is not implemented on web');
    throw this.unimplemented('hide() is not implemented on web platform. Use native iOS/Android.');
  }

  /**
   * Get cookies for a specific URL
   * @param {Object} options - Options with URL
   * @returns {Promise<Object>} Empty cookies object
   */
  async getCookies(options) {
    console.warn('InAppAuthWebView.getCookies is not implemented on web');
    return { cookies: {} };
  }
}