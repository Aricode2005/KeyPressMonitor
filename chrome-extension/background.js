// KeyPressMonitor — Background Service Worker (Manifest V3)
// Aggregates real-time keystroke analytics from any webpage or the dashboard.

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
    fingerCnt: [0, 0, 0, 0, 0, 0, 0, 0, 0], // L4..L1, R1..R4, Thumbs
    rowCnt: [0, 0, 0, 0, 0], // Num, Top, Home, Bottom, Space
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

chrome.storage.local.get(['kpmState'], (res) => {
  if (res && res.kpmState) {
    state = Object.assign(defaultState(), res.kpmState);
  }
});

// Auto-inject content.js into already-open tabs when extension installs or reloads
function injectIntoExistingTabs() {
  if (!chrome.scripting || !chrome.tabs) return;
  chrome.tabs.query({}, (tabs) => {
    for (const tab of tabs) {
      if (tab.id && tab.url && /^https?:\/\//i.test(tab.url)) {
        chrome.scripting.executeScript({
          target: { tabId: tab.id },
          files: ['content.js']
        }).catch(() => {});
      }
    }
  });
}

chrome.runtime.onInstalled.addListener(injectIntoExistingTabs);
chrome.runtime.onStartup.addListener(injectIntoExistingTabs);

function saveState() {
  chrome.storage.local.set({ kpmState: state });
  const badgeText = state.paused ? '||' : (state.wpmNow > 0 ? String(state.wpmNow) : (state.totalKeys > 0 ? String(state.totalKeys) : ''));
  chrome.action.setBadgeText({ text: badgeText });
  chrome.action.setBadgeBackgroundColor({ color: state.paused ? '#CA8A04' : '#7C3AED' });
}

function updateLiveWpm(now) {
  state.tsRing = state.tsRing.filter((t) => now - t < 5000);
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

  // Latency & Rhythm
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

  // Determine display label and ASCII
  let disp = key;
  let ascii = key.length === 1 ? key.charCodeAt(0) : 0;
  if (key === ' ') { disp = 'SPC'; ascii = 32; }
  else if (key === 'Enter') { disp = 'ENT'; ascii = 13; }
  else if (key === 'Backspace') { disp = 'BSP'; ascii = 8; }
  else if (key === 'Tab') { disp = 'TAB'; ascii = 9; }

  state.lastKeyName = disp;
  state.lastKeyCode = ascii;

  // Frequency count
  state.freq[disp] = (state.freq[disp] || 0) + 1;

  // Virtual key for heatmap
  const vk = (key.length === 1 ? key.toUpperCase() : disp);
  state.vkFreq[vk] = (state.vkFreq[vk] || 0) + 1;

  // Backspace & Streak
  if (key === 'Backspace') {
    state.bsCount++;
    state.curStreak = 0;
  } else {
    state.curStreak++;
    if (state.curStreak > state.bestStreak) state.bestStreak = state.curStreak;
  }

  // Category classification
  const lower = key.length === 1 ? key.toLowerCase() : '';
  const isLetter = lower >= 'a' && lower <= 'z';
  const isDigit = lower >= '0' && lower <= '9';

  if (isLetter) {
    if (VOWELS.has(lower)) state.vowels++;
    else state.consonants++;

    // N-gram tracking
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

    // Ergonomics: Hand, Finger & Row
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

  // Word counter
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

  // Last N characters circular buffer
  let glyph = key.length === 1 ? key : (key === 'Enter' ? '↵' : (key === 'Backspace' ? '⌫' : (key === 'Tab' ? '⇥' : '•')));
  state.lastChars.push(glyph);
  if (state.lastChars.length > 64) state.lastChars.shift();

  updateLiveWpm(now);
  saveState();
  return state;
}

// Sample WPM history every second
setInterval(() => {
  if (!state.paused) {
    updateLiveWpm(Date.now());
    state.wpmHist.push(state.wpmNow);
    if (state.wpmHist.length > 52) state.wpmHist.shift();
    saveState();
  }
}, 1000);

chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  if (!msg || !msg.type) return false;
  if (msg.type === 'KPM_KEY') {
    sendResponse({ state: recordKeyEvent(msg.payload) });
  } else if (msg.type === 'KPM_GET_STATE') {
    updateLiveWpm(Date.now());
    sendResponse({ state });
  } else if (msg.type === 'KPM_RESET') {
    const keepTheme = state.theme;
    const keepSound = state.soundOn;
    const keepHud = state.hudOn;
    const keepAllWpm = msg.clearAll ? 0 : state.allTimeBestWpm;
    const keepAllTest = msg.clearAll ? 0 : state.allTimeTestBest;
    state = defaultState();
    state.theme = keepTheme;
    state.soundOn = keepSound;
    state.hudOn = keepHud;
    state.allTimeBestWpm = keepAllWpm;
    state.allTimeTestBest = keepAllTest;
    saveState();
    sendResponse({ state });
  } else if (msg.type === 'KPM_TOGGLE_PAUSE') {
    state.paused = !state.paused;
    saveState();
    sendResponse({ state });
  } else if (msg.type === 'KPM_SET_PREFS') {
    if (typeof msg.nView === 'number') state.nView = Math.max(8, Math.min(64, msg.nView));
    if (msg.theme) state.theme = msg.theme;
    if (typeof msg.soundOn === 'boolean') state.soundOn = msg.soundOn;
    if (typeof msg.hudOn === 'boolean') state.hudOn = msg.hudOn;
    if (typeof msg.testBest === 'number') {
      if (msg.testBest > state.testBest) state.testBest = msg.testBest;
      if (msg.testBest > state.allTimeTestBest) state.allTimeTestBest = msg.testBest;
    }
    saveState();
    sendResponse({ state });
  }
  return true;
});
