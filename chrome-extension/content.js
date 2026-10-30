// KeyPressMonitor — Content Script & Draggable / Resizable Floating Mini HUD
// Captures real-time key presses across web pages (skipping password fields for privacy)
// and displays a sleek, freely draggable and resizable floating HUD with 1-click Reset.

(function () {
  // Remove any stale HUD elements from previous extension reloads in this tab
  document.querySelectorAll('#kpm-floating-hud-host').forEach((el) => el.remove());

  if (window.__kpmCleanup) {
    try { window.__kpmCleanup(); } catch (_) {}
  }

  let hudHost = null;
  let hudRefs = {};
  let isTopFrame = false;
  try { isTopFrame = (window.self === window.top); } catch (_) { isTopFrame = false; }

  let hudLayout = {
    x: null,
    y: null,
    scale: 1.0,
    width: null,
    minimized: false
  };

  function saveLayout() {
    try {
      chrome.storage.local.set({ kpmHudLayout: hudLayout });
    } catch (_) {}
  }

  function applyLayout() {
    if (!hudHost || !hudRefs.box) return;
    if (typeof hudLayout.x === 'number' && typeof hudLayout.y === 'number') {
      const maxX = Math.max(40, window.innerWidth - 80);
      const maxY = Math.max(30, window.innerHeight - 40);
      const clampedX = Math.max(6, Math.min(maxX, hudLayout.x));
      const clampedY = Math.max(6, Math.min(maxY, hudLayout.y));
      hudHost.style.left = clampedX + 'px';
      hudHost.style.top = clampedY + 'px';
      hudHost.style.right = 'auto';
      hudHost.style.bottom = 'auto';
    } else {
      hudHost.style.right = '16px';
      hudHost.style.bottom = '16px';
      hudHost.style.left = 'auto';
      hudHost.style.top = 'auto';
    }

    const sc = Math.max(0.7, Math.min(1.8, hudLayout.scale || 1.0));
    hudRefs.box.style.zoom = String(sc);
    if (hudLayout.width && !hudLayout.minimized) {
      hudRefs.box.style.width = Math.max(260, Math.min(900, hudLayout.width)) + 'px';
    } else {
      hudRefs.box.style.width = 'auto';
    }
    hudRefs.box.classList.toggle('minimized', !!hudLayout.minimized);
  }

  function createHud() {
    if (!isTopFrame || hudHost || !document.body) return;
    // Ensure no duplicate exists in the DOM
    document.querySelectorAll('#kpm-floating-hud-host').forEach((el) => el.remove());
    hudHost = document.createElement('div');
    hudHost.id = 'kpm-floating-hud-host';
    hudHost.style.cssText = 'position:fixed;bottom:16px;right:16px;z-index:2147483647;font-family:Segoe UI,system-ui,sans-serif;user-select:none;touch-action:none;';
    const shadow = hudHost.attachShadow({ mode: 'open' });

    shadow.innerHTML = `
      <style>
        .hud {
          position: relative;
          background: rgba(18, 23, 41, 0.94);
          backdrop-filter: blur(8px);
          border: 1px solid #2A3352;
          border-radius: 12px;
          padding: 7px 14px 7px 10px;
          color: #E2E8F0;
          box-shadow: 0 8px 28px rgba(0,0,0,0.48);
          display: flex;
          align-items: center;
          justify-content: space-between;
          gap: 10px;
          font-size: 12px;
          min-width: 72px;
          box-sizing: border-box;
        }
        .hud.dragging {
          border-color: #67E8F9;
          box-shadow: 0 12px 34px rgba(103, 232, 249, 0.25);
          cursor: grabbing !important;
        }
        .hud.hidden { display: none !important; }
        .hud.minimized .stats, .hud.minimized .last-key, .hud.minimized .resize-grip { display: none; }
        .drag-grip {
          cursor: grab;
          color: #64748B;
          font-size: 13px;
          line-height: 1;
          padding: 2px 3px;
          letter-spacing: -1px;
        }
        .drag-grip:hover { color: #67E8F9; }
        .brand {
          display: flex;
          align-items: center;
          gap: 5px;
          font-weight: 700;
          color: #fff;
          cursor: grab;
          padding-right: 6px;
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
          flex-wrap: wrap;
          cursor: grab;
          flex: 1;
        }
        .stat { white-space: nowrap; }
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
        .actions { display: flex; align-items: center; gap: 4px; flex-shrink: 0; }
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
        .resize-grip {
          position: absolute;
          right: 2px;
          bottom: 2px;
          width: 11px;
          height: 11px;
          cursor: nwse-resize;
          background: linear-gradient(135deg, transparent 50%, #64748B 50%, #64748B 65%, transparent 65%, transparent 80%, #67E8F9 80%);
          border-bottom-right-radius: 8px;
          opacity: 0.75;
        }
        .resize-grip:hover { opacity: 1; }
      </style>
      <div class="hud" id="hudBox" title="Drag anywhere to move • Scroll wheel to zoom • Drag corner to resize">
        <div class="drag-grip" id="dragGrip" title="Drag to move HUD anywhere on screen">⋮⋮</div>
        <div class="brand" id="btnToggleMin" title="Double-click to minimize/expand • Drag to move">
          <span class="dot" id="hudDot"></span>
          <span>KP</span>
        </div>
        <div class="stats" id="hudStats">
          <span class="stat" title="Live Typing Speed (WPM)">WPM <b class="v-wpm" id="hWpm">0</b></span>
          <span class="stat" title="Total Keys Pressed">Keys <b class="v-keys" id="hKeys">0</b></span>
          <span class="stat" title="Vowels / Consonants">V/C <b class="v-vow" id="hVow">0</b>/<b class="v-con" id="hCon">0</b></span>
          <span class="stat" title="Current Error-Free Streak">Streak <b class="v-strk" id="hStrk">0</b></span>
        </div>
        <div class="last-key" id="hLast" title="Last Key Pressed">-</div>
        <div class="actions">
          <button class="reset-btn" id="btnReset" title="Refresh / Clear all recorded stats (Reset to 0)">↻ Reset</button>
          <button id="btnPause" title="Pause / Resume tracking">⏸</button>
          <button id="btnMin" title="Minimize / Expand HUD">_</button>
        </div>
        <div class="resize-grip" id="resizeGrip" title="Drag to resize / scale HUD (double-click to reset size)"></div>
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
      btnPause: shadow.getElementById('btnPause'),
      btnMin: shadow.getElementById('btnMin'),
      resizeGrip: shadow.getElementById('resizeGrip')
    };

    // Load saved position & size
    try {
      chrome.storage.local.get(['kpmHudLayout'], (res) => {
        if (res && res.kpmHudLayout) {
          hudLayout = Object.assign(hudLayout, res.kpmHudLayout);
          applyLayout();
        }
      });
    } catch (_) {}

    // Dragging anywhere on the HUD bar (except buttons & resize handle)
    let isDragging = false;
    let dragOffX = 0;
    let dragOffY = 0;

    hudRefs.box.addEventListener('mousedown', (e) => {
      if (e.button !== 0) return;
      const tag = e.target && e.target.tagName;
      if (tag === 'BUTTON' || e.target === hudRefs.resizeGrip) return;
      isDragging = true;
      const rect = hudHost.getBoundingClientRect();
      dragOffX = e.clientX - rect.left;
      dragOffY = e.clientY - rect.top;
      hudRefs.box.classList.add('dragging');
      e.preventDefault();
    });

    // Corner Resize / Scale handle
    let isResizing = false;
    let resizeStartX = 0;
    let resizeStartY = 0;
    let startWidth = 0;
    let startScale = 1.0;

    hudRefs.resizeGrip.addEventListener('mousedown', (e) => {
      if (e.button !== 0) return;
      e.stopPropagation();
      e.preventDefault();
      isResizing = true;
      resizeStartX = e.clientX;
      resizeStartY = e.clientY;
      startWidth = hudRefs.box.getBoundingClientRect().width / (hudLayout.scale || 1.0);
      startScale = hudLayout.scale || 1.0;
    });

    hudRefs.resizeGrip.addEventListener('dblclick', (e) => {
      e.stopPropagation();
      hudLayout.scale = 1.0;
      hudLayout.width = null;
      applyLayout();
      saveLayout();
    });

    window.addEventListener('mousemove', (e) => {
      if (isDragging) {
        hudLayout.x = Math.max(6, Math.min(window.innerWidth - 60, e.clientX - dragOffX));
        hudLayout.y = Math.max(6, Math.min(window.innerHeight - 36, e.clientY - dragOffY));
        applyLayout();
      } else if (isResizing) {
        const dx = e.clientX - resizeStartX;
        const dy = e.clientY - resizeStartY;
        hudLayout.width = Math.max(260, Math.min(900, Math.round(startWidth + dx)));
        hudLayout.scale = Math.max(0.75, Math.min(1.75, Number((startScale + dy * 0.004).toFixed(2))));
        applyLayout();
      }
    }, true);

    window.addEventListener('mouseup', () => {
      if (isDragging || isResizing) {
        isDragging = false;
        isResizing = false;
        if (hudRefs.box) hudRefs.box.classList.remove('dragging');
        saveLayout();
      }
    }, true);

    // Mouse wheel over HUD scales zoom smoothly
    hudRefs.box.addEventListener('wheel', (e) => {
      e.preventDefault();
      const delta = e.deltaY < 0 ? 0.06 : -0.06;
      hudLayout.scale = Math.max(0.75, Math.min(1.75, Number(((hudLayout.scale || 1.0) + delta).toFixed(2))));
      applyLayout();
      saveLayout();
    }, { passive: false });

    window.addEventListener('resize', applyLayout);

    // Minimize / Expand
    function toggleMinimize(e) {
      e.stopPropagation();
      hudLayout.minimized = !hudLayout.minimized;
      hudRefs.btnMin.textContent = hudLayout.minimized ? '□' : '_';
      applyLayout();
      saveLayout();
    }
    hudRefs.btnMin.addEventListener('click', toggleMinimize);
    shadow.getElementById('btnToggleMin').addEventListener('dblclick', toggleMinimize);

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

  // Listen to storage updates so HUD position, size & stats sync across tabs
  try {
    chrome.storage.onChanged.addListener((changes, area) => {
      if (area === 'local') {
        if (changes.kpmState && changes.kpmState.newValue) {
          updateHud(changes.kpmState.newValue);
        }
        if (changes.kpmHudLayout && changes.kpmHudLayout.newValue) {
          hudLayout = Object.assign(hudLayout, changes.kpmHudLayout.newValue);
          applyLayout();
        }
      }
    });
  } catch (_) {}

  // Capture keystrokes in real-time
  function onKeyDown(e) {
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
      // Extension context invalidated on reload — self-remove stale HUD and listener
      window.removeEventListener('keydown', onKeyDown, true);
      if (hudHost) { hudHost.remove(); hudHost = null; }
    }
  }

  window.addEventListener('keydown', onKeyDown, true);

  window.__kpmCleanup = () => {
    window.removeEventListener('keydown', onKeyDown, true);
    if (hudHost) { hudHost.remove(); hudHost = null; }
  };
})();
