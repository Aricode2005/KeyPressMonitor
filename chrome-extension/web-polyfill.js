// KeyPressMonitor — Standalone Web App + Chrome Extension Polyfill
// Enables popup.html / dashboard.js to run directly on the web (e.g. deployed on Render)
// using localStorage when Chrome Extension APIs (chrome.runtime / chrome.storage) are unavailable.

(function () {
  if (typeof window.chrome !== 'undefined' && window.chrome.runtime && window.chrome.runtime.id) {
    return; // Running inside actual Chrome Extension — use native MV3 background service worker
  }

  const VOWELS = new Set(['a', 'e', 'i', 'o', 'u']);
  const FINGER_MAP = {
    a: 0, b: 3, c: 2, d: 2, e: 2, f: 3, g: 3, h: 4, i: 5, j: 4,
    k: 5, l: 6, m: 4, n: 4, o: 6, p: 7, q: 0, r: 3, s: 1, t: 3,
    u: 4, v: 3, w: 1, x: 1, y: 4, z: 0
  };
  const ROW_MAP = {
    a: 2, b: 3, c: 3, d: 2, e: 1, f: 2, g: 2, h: 2, i: 1, j: 2,
    k: 2, l: 2, m: 3, n: 3, o: 1, p: 1, q: 1, r: 1, s: 2, t: 1,
    u: 1, v: 3, w: 1, x: 3, y: 1, z: 3
  };

  function defaultState() {
    return {
      paused: false,
      hudOn: true,
      theme: 'midnight',
      soundOn: false,
      nView: 32,
      totalKeys: 0,
      vowels: 0,
      consonants: 0,
      digits: 0,
      spaces: 0,
      symbols: 0,
      others: 0,
      words: 0,
      inWord: false,
      curWordLen: 0,
      longestWord: 0,
      bsCount: 0,
      curStreak: 0,
      bestStreak: 0,
      leftHand: 0,
      rightHand: 0,
      handAlt: 0,
      lastHand: -1,
      fingerCnt: [0, 0, 0, 0, 0, 0, 0, 0, 0],
      rowCnt: [0, 0, 0, 0, 0],
      freq: {},
      vkFreq: {},
      bigrams: {},
      trigrams: {},
      prevL1: '',
      prevL2: '',
      lastChars: [],
      lastKeyName: '-',
      lastKeyCode: 0,
      lastKeyTick: 0,
      latSum: 0,
      latCnt: 0,
      avgLatMs: 0,
      minLatMs: 0,
      activeMs: 0,
      startTick: Date.now(),
      tsRing: [],
      wpmHist: [],
      wpmNow: 0,
      wpmPeak: 0,
      wpmAvg: 0,
      testBest: 0,
      allTimeBestWpm: 0,
      allTimeTestBest: 0
    };
  }

  let state = defaultState();
  try {
    const saved = localStorage.getItem('kpmState');
    if (saved) state = Object.assign(defaultState(), JSON.parse(saved));
  } catch (_) {}

  const changeListeners = [];

  function saveState() {
    try {
      localStorage.setItem('kpmState', JSON.stringify(state));
      changeListeners.forEach((fn) => {
        try { fn({ kpmState: { newValue: state } }, 'local'); } catch (_) {}
      });
    } catch (_) {}
  }

  function updateLiveWpm(now) {
    state.tsRing = (state.tsRing || []).filter((t) => now - t < 5000);
    const keysIn5s = state.tsRing.length;
    state.wpmNow = Math.round((keysIn5s * 12) / 5);
    if (state.wpmNow > state.wpmPeak) state.wpmPeak = state.wpmNow;
    if (state.wpmPeak > state.allTimeBestWpm) state.allTimeBestWpm = state.wpmPeak;

    const elapsedMs = Math.max(1000, now - state.startTick);
    if (elapsedMs >= 1500 && state.totalKeys > 0) {
      state.wpmAvg = Math.round((state.totalKeys * 12000) / elapsedMs);
    }
  }

  function recordKeyEvent(payload) {
    if (state.paused) return state;
    const now = Date.now();
    const key = payload.key || '';

    state.totalKeys++;
    state.tsRing.push(now);

    if (state.lastKeyTick > 0) {
      const dt = now - state.lastKeyTick;
      if (dt > 0 && dt < 2000) {
        state.activeMs += dt;
        state.latSum += dt;
        state.latCnt++;
        state.avgLatMs = Math.round(state.latSum / state.latCnt);
        if (state.minLatMs === 0 || dt < state.minLatMs) state.minLatMs = dt;
      }
    }
    state.lastKeyTick = now;

    let disp = key;
    let ascii = key.length === 1 ? key.charCodeAt(0) : 0;
    if (key === ' ') { disp = 'SPC'; ascii = 32; }
    else if (key === 'Enter') { disp = 'ENT'; ascii = 13; }
    else if (key === 'Backspace') { disp = 'BSP'; ascii = 8; }
    else if (key === 'Tab') { disp = 'TAB'; ascii = 9; }

    state.lastKeyName = disp;
    state.lastKeyCode = ascii;
    state.freq[disp] = (state.freq[disp] || 0) + 1;

    const vk = (key.length === 1 ? key.toUpperCase() : disp);
    state.vkFreq[vk] = (state.vkFreq[vk] || 0) + 1;

    if (key === 'Backspace') {
      state.bsCount++;
      state.curStreak = 0;
    } else {
      state.curStreak++;
      if (state.curStreak > state.bestStreak) state.bestStreak = state.curStreak;
    }

    const lower = key.length === 1 ? key.toLowerCase() : '';
    const isLetter = lower >= 'a' && lower <= 'z';
    const isDigit = lower >= '0' && lower <= '9';

    if (isLetter) {
      if (VOWELS.has(lower)) state.vowels++;
      else state.consonants++;

      if (state.prevL1) {
        const bi = state.prevL1 + lower;
        state.bigrams[bi] = (state.bigrams[bi] || 0) + 1;
        if (state.prevL2) {
          const tri = state.prevL2 + state.prevL1 + lower;
          state.trigrams[tri] = (state.trigrams[tri] || 0) + 1;
        }
      }
      state.prevL2 = state.prevL1;
      state.prevL1 = lower;

      const fIdx = FINGER_MAP[lower] ?? 3;
      const rIdx = ROW_MAP[lower] ?? 2;
      state.fingerCnt[fIdx] = (state.fingerCnt[fIdx] || 0) + 1;
      state.rowCnt[rIdx] = (state.rowCnt[rIdx] || 0) + 1;
      const hand = fIdx < 4 ? 0 : 1;
      if (hand === 0) state.leftHand++;
      else state.rightHand++;
      if (state.lastHand !== -1 && state.lastHand !== hand) state.handAlt++;
      state.lastHand = hand;
    } else {
      state.prevL1 = '';
      state.prevL2 = '';
      if (isDigit) {
        state.digits++;
        state.rowCnt[0]++;
        const d = lower.charCodeAt(0) - 48;
        const hand = (d >= 1 && d <= 5) ? 0 : 1;
        if (hand === 0) { state.leftHand++; state.fingerCnt[2]++; }
        else { state.rightHand++; state.fingerCnt[5]++; }
        if (state.lastHand !== -1 && state.lastHand !== hand) state.handAlt++;
        state.lastHand = hand;
      } else if (key === ' ') {
        state.spaces++;
        state.fingerCnt[8]++;
        state.rowCnt[4]++;
      } else if (key.length === 1) {
        state.symbols++;
        state.rightHand++;
        state.fingerCnt[7]++;
        state.rowCnt[4]++;
      } else {
        state.others++;
        state.rowCnt[4]++;
      }
    }

    if (isLetter || isDigit) {
      if (!state.inWord) {
        state.words++;
        state.inWord = true;
        state.curWordLen = 0;
      }
      state.curWordLen++;
      if (state.curWordLen > state.longestWord) state.longestWord = state.curWordLen;
    } else {
      state.inWord = false;
    }

    let glyph = key.length === 1 ? key : (key === 'Enter' ? '↵' : (key === 'Backspace' ? '⌫' : (key === 'Tab' ? '⇥' : '•')));
    state.lastChars.push(glyph);
    if (state.lastChars.length > 64) state.lastChars.shift();

    updateLiveWpm(now);
    saveState();
    return state;
  }

  setInterval(() => {
    if (!state.paused) {
      updateLiveWpm(Date.now());
      state.wpmHist.push(state.wpmNow);
      if (state.wpmHist.length > 52) state.wpmHist.shift();
      saveState();
    }
  }, 1000);

  window.chrome = {
    runtime: {
      getURL: (p) => p,
      sendMessage: (msg, cb) => {
        let res = { state };
        if (msg && msg.type === 'KPM_KEY') {
          res = { state: recordKeyEvent(msg.payload) };
        } else if (msg && msg.type === 'KPM_GET_STATE') {
          updateLiveWpm(Date.now());
          res = { state };
        } else if (msg && msg.type === 'KPM_RESET') {
          const keepTheme = state.theme;
          const keepSound = state.soundOn;
          const keepHud = state.hudOn;
          state = defaultState();
          state.theme = keepTheme;
          state.soundOn = keepSound;
          state.hudOn = keepHud;
          saveState();
          res = { state };
        } else if (msg && msg.type === 'KPM_TOGGLE_PAUSE') {
          state.paused = !state.paused;
          saveState();
          res = { state };
        } else if (msg && msg.type === 'KPM_SET_PREFS') {
          if (typeof msg.nView === 'number') state.nView = Math.max(8, Math.min(64, msg.nView));
          if (msg.theme) state.theme = msg.theme;
          if (typeof msg.soundOn === 'boolean') state.soundOn = msg.soundOn;
          if (typeof msg.hudOn === 'boolean') state.hudOn = msg.hudOn;
          if (typeof msg.testBest === 'number') {
            if (msg.testBest > state.testBest) state.testBest = msg.testBest;
            if (msg.testBest > state.allTimeTestBest) state.allTimeTestBest = msg.testBest;
          }
          saveState();
          res = { state };
        }
        if (typeof cb === 'function') cb(res);
      }
    },
    tabs: {
      create: ({ url }) => { window.open(url, '_blank'); }
    },
    storage: {
      local: {
        get: (keys, cb) => {
          const out = {};
          (Array.isArray(keys) ? keys : [keys]).forEach((k) => {
            try {
              const v = localStorage.getItem(k);
              if (v) out[k] = JSON.parse(v);
            } catch (_) {}
          });
          if (cb) cb(out);
        },
        set: (obj, cb) => {
          Object.entries(obj || {}).forEach(([k, v]) => {
            try { localStorage.setItem(k, JSON.stringify(v)); } catch (_) {}
          });
          if (cb) cb();
        }
      },
      onChanged: {
        addListener: (fn) => changeListeners.push(fn)
      }
    }
  };
})();
