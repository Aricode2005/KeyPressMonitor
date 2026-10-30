// KeyPressMonitor — Content Script
// Captures real-time key presses across web pages (skipping password fields for privacy).

(function () {
  window.addEventListener('keydown', (e) => {
    try {
      // Never log password inputs for security & Chrome Web Store compliance
      const el = e.target;
      if (el && el.tagName === 'INPUT' && el.type === 'password') return;
      if (['Shift', 'Control', 'Alt', 'Meta', 'CapsLock'].includes(e.key)) return;

      chrome.runtime.sendMessage({
        type: 'KPM_KEY',
        payload: {
          key: e.key,
          code: e.code
        }
      });
    } catch (_) {
      // Extension context invalidated on reload
    }
  }, true);
})();
