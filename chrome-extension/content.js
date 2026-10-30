// KeyPressMonitor — Content Script & Floating Mini HUD Widget
// Captures real-time key presses across web pages (skipping password fields for privacy)
// and displays a sleek floating HUD in the bottom-right corner with a 1-click Reset button.

(function () {
  if (window.__kpmContentLoaded) return;
  window.__kpmContentLoaded = true;

  let hudHost = null;
  let hudRefs = {};
  let isTopFrame = false;
  try { isTopFrame = (window.self === window.top); } catch (_) { isTopFrame = false; }

  function createHud() {
    if (!isTopFrame || hudHost || !document.body) return;
    hudHost = document.createElement('div');
    hudHost.id = 'kpm-floating-hud-host';
    hudHost.style.cssText = 'position:fixed;bottom:16px;right:16px;z-index:2147483647;font-family:Segoe UI,system-ui,sans-serif;user-select:none;';
    const shadow = hudHost.attachShadow({ mode: 'open' });

    shadow.innerHTML = `
      <style>
        .hud {
          background: rgba(18, 23, 41, 0.94);
          backdrop-filter: blur(8px);
          border: 1px solid #2A3352;
          border-radius: 12px;
          padding: 7px 11px;
          color: #E2E8F0;
          box-shadow: 0 8px 28px rgba(0,0,0,0.48);
          display: flex;
          align-items: center;
          gap: 10px;
          font-size: 12px;
          transition: opacity 0.2s, transform 0.2s;
        }
        .hud.hidden { display: none !important; }
        .hud.minimized .stats, .hud.minimized .last-key { display: none; }
        .brand {
          display: flex;
          align-items: center;
          gap: 5px;
          font-weight: 700;
          color: #fff;
          cursor: pointer;
          padding-right: 4px;
          border-right: 1px solid #2A3352;
        }
        .dot {
          width: 7px;
          height: 7px;
          border-radius: 50%;
          background: #4ADE80;
          display: inline-block;
        }
        .dot.paused { background: #FACC15; }
        .stats {
          display: flex;
          align-items: center;
          gap: 9px;
          font-family: Consolas, monospace;
          font-size: 11.5px;
        }
        .stat b { font-weight: 700; margin-left: 2px; }
        .v-wpm { color: #C4B5FD; }
        .v-keys { color: #67E8F9; }
        .v-vow { color: #6EE7B7; }
        .v-con { color: #FCD34D; }
        .v-strk { color: #4ADE80; }
        .last-key {
          background: #1C2238;
          border: 1px solid #2A3352;
          border-radius: 5px;
          padding: 1px 6px;
          font-family: Consolas, monospace;
          font-size: 11px;
          color: #67E8F9;
          font-weight: 700;
          min-width: 24px;
          text-align: center;
        }
        .actions { display: flex; align-items: center; gap: 4px; }
        button {
          background: #1C2238;
          color: #E2E8F0;
          border: 1px solid #2A3352;
          border-radius: 6px;
          padding: 2px 6px;
          font-size: 11px;
          cursor: pointer;
          display: inline-flex;
          align-items: center;
          justify-content: center;
          transition: background 0.15s, border-color 0.15s;
        }
        button:hover { background: #2A3352; border-color: #67E8F9; color: #fff; }
        button.reset-btn:hover { background: #E11D48; border-color: #E11D48; }
      </style>
      <div class="hud" id="hudBox">
        <div class="brand" id="btnToggleMin" title="Click to minimize / expand KeyPressMonitor HUD">
          <span class="dot" id="hudDot"></span>
          <span>KP</span>
        </div>
        <div class="stats">
          <span class="stat" title="Live Typing Speed (WPM)">WPM <b class="v-wpm" id="hWpm">0</b></span>
          <span class="stat" title="Total Keys Pressed">Keys <b class="v-keys" id="hKeys">0</b></span>
          <span class="stat" title="Vowels / Consonants">V/C <b class="v-vow" id="hVow">0</b>/<b class="v-con" id="hCon">0</b></span>
          <span class="stat" title="Current Error-Free Streak">Streak <b class="v-strk" id="hStrk">0</b></span>
        </div>
        <div class="last-key" id="hLast" title="Last Key Pressed">-</div>
        <div class="actions">
          <button class="reset-btn" id="btnReset" title="Refresh / Clear all recorded stats (Reset to 0)">↻ Reset</button>
          <button id="btnPause" title="Pause / Resume tracking">⏸</button>
        </div>
      </div>
    `;

    document.body.appendChild(hudHost);

    hudRefs = {
      box: shadow.getElementById('hudBox'),
      dot: shadow.getElementById('hudDot'),
      wpm: shadow.getElementById('hWpm'),
      keys: shadow.getElementById('hKeys'),
      vow: shadow.getElementById('hVow'),
      con: shadow.getElementById('hCon'),
      strk: shadow.getElementById('hStrk'),
      last: shadow.getElementById('hLast'),
      btnPause: shadow.getElementById('btnPause')
    };

    shadow.getElementById('btnToggleMin').addEventListener('click', () => {
      hudRefs.box.classList.toggle('minimized');
    });

    shadow.getElementById('btnReset').addEventListener('click', (e) => {
      e.stopPropagation();
      try {
        chrome.runtime.sendMessage({ type: 'KPM_RESET', clearAll: true }, (res) => {
          if (res && res.state) updateHud(res.state);
        });
      } catch (_) {}
    });

    shadow.getElementById('btnPause').addEventListener('click', (e) => {
      e.stopPropagation();
      try {
        chrome.runtime.sendMessage({ type: 'KPM_TOGGLE_PAUSE' }, (res) => {
          if (res && res.state) updateHud(res.state);
        });
      } catch (_) {}
    });
  }

  function updateHud(s) {
    if (!isTopFrame) return;
    if (!hudHost) createHud();
    if (!hudRefs.box || !s) return;

    if (s.hudOn === false) {
      hudRefs.box.classList.add('hidden');
      return;
    }
    hudRefs.box.classList.remove('hidden');
    hudRefs.dot.className = 'dot' + (s.paused ? ' paused' : '');
    hudRefs.btnPause.textContent = s.paused ? '▶' : '⏸';
    hudRefs.wpm.textContent = s.wpmNow || 0;
    hudRefs.keys.textContent = s.totalKeys || 0;
    hudRefs.vow.textContent = s.vowels || 0;
    hudRefs.con.textContent = s.consonants || 0;
    hudRefs.strk.textContent = s.curStreak || 0;
    hudRefs.last.textContent = s.lastKeyName || '-';
  }

  // Initial state load
  if (isTopFrame) {
    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', createHud);
    } else {
      createHud();
    }
    try {
      chrome.runtime.sendMessage({ type: 'KPM_GET_STATE' }, (res) => {
        if (res && res.state) updateHud(res.state);
      });
    } catch (_) {}
  }

  // Listen to storage updates so HUD updates across all tabs & when reset from popup
  try {
    chrome.storage.onChanged.addListener((changes, area) => {
      if (area === 'local' && changes.kpmState && changes.kpmState.newValue) {
        updateHud(changes.kpmState.newValue);
      }
    });
  } catch (_) {}

  // Capture keystrokes in real-time
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
      }, (res) => {
        if (res && res.state) updateHud(res.state);
      });
    } catch (_) {
      // Extension context invalidated on reload
    }
  }, true);
})();
