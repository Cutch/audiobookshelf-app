import { registerPlugin } from '@capacitor/core';
import { InAppAuthWebViewWeb } from './web';

const InAppAuthWebView = registerPlugin('InAppAuthWebView', {
  web: () => new InAppAuthWebViewWeb(),
});

export { InAppAuthWebView };