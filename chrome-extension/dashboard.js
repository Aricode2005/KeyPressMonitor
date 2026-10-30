// KeyPressMonitor — Interactive Dashboard & Typing Test Controller

const KB_ROWS = [
  ['1','2','3','4','5','6','7','8','9','0','-','='],
  ['Q','W','E','R','T','Y','U','I','O','P','[',']'],
  ['A','S','D','F','G','H','J','K','L',';',"'"],
  ['Z','X','C','V','B','N','M',',','.','/']
];

const THEMES = ['midnight', 'cyberpunk', 'matrix', 'nord'];
const RANKS = ['NOVICE', 'TYPIST', 'PRO', 'MASTER', 'GRANDMASTER'];
const FINGER_NAMES = [
  'L-Pinky', 'L-Ring', 'L-Middle', 'L-Index',
  'R-Index', 'R-Middle', 'R-Ring', 'R-Pinky', 'Thumbs'
];
const ROW_NAMES = [
  'Number Row (1-0)', 'Top Row (QWERTY)', 'Home Row (ASDFG)', 'Bottom Row (ZXCV)', 'Space & Modifiers'
];

const TEST_SENTENCES = {
  STANDARD: [
    'the quick brown fox jumps over the lazy dog',
    'pack my box with five dozen liquor jugs',
    'sphinx of black quartz, judge my vow'
  ],
  QUOTES: [
    'assembly language gives you full control of the machine',
    'every keystroke is counted, classified and drawn in real time',
    'simplicity is prerequisite for reliability in software design'
  ],
  CODE: [
    'mov eax, [ebx+ecx*4] ; invoke WriteConsoleW, hOut, pBuf, n',
    'for (int i = 0; i < n; ++i) { freq[str[i]]++; total += 1; }',
    'const wpm = Math.round((chars / 5) / (elapsedMs / 60000));'
  ],
  NUMBERS: [
    '192.168.1.254:8080 #42 = 100% - $39.95 + (2026 / 4) * 7!',
    '0xFF00AA55 -> [256 * 4] = 1024 bytes @ 60fps (33.3ms/frame)',
    'key #1: 98.6%, key #2: 450ms, total = 1,234,567 (0x12D687)'
  ]
};
const MODE_KEYS = ['STANDARD', 'QUOTES', 'CODE', 'NUMBERS'];

let curState = null;
let viewMode = 0; // 0=Dash, 1=Test, 2=Ergo
let audioCtx = null;

// Typing test state
let ttModeIdx = 0;
let ttSentIdx = 0;
let ttTarget = TEST_SENTENCES.STANDARD[0];
let ttTyped = '';
let ttErrors = 0;
let ttKeys = 0;
let ttStart = 0;
let ttDone = false;

function playClickSound(keyChar) {
  if (!curState || !curState.soundOn) return;
  try {
    if (!audioCtx) audioCtx = new (window.AudioContext || window.webkitAudioContext)();
    const osc = audioCtx.createOscillator();
    const gain = audioCtx.createGain();
    const code = (keyChar && keyChar.charCodeAt(0)) || 65;
    osc.type = 'triangle';
    osc.frequency.setValueAtTime(520 + (code & 31) * 14, audioCtx.currentTime);
    gain.gain.setValueAtTime(0.06, audioCtx.currentTime);
    gain.gain.exponentialRampToValueAtTime(0.001, audioCtx.currentTime + 0.025);
    osc.connect(gain);
    gain.connect(audioCtx.destination);
    osc.start();
    osc.stop(audioCtx.currentTime + 0.028);
  } catch (_) {}
}

function showToast(msg) {
  const el = document.getElementById('statusToast');
  if (el) el.textContent = msg;
}

function formatMMSS(sec) {
  const m = Math.min(99, Math.floor(sec / 60));
  const s = Math.floor(sec % 60);
  return String(m).padStart(2, '0') + ':' + String(s).padStart(2, '0');
}

function heatColor(cnt, maxCnt) {
  if (!cnt || cnt <= 0) return 'var(--offkey)';
  const r = Math.min(1, cnt / Math.max(1, maxCnt));
  const stops = [
    [29, 78, 216],
    [6, 182, 212],
    [16, 185, 129],
    [250, 204, 21],
    [249, 115, 22],
    [225, 29, 72]
  ];
  const pos = r * (stops.length - 1);
  const idx = Math.min(stops.length - 2, Math.floor(pos));
  const f = pos - idx;
  const c1 = stops[idx], c2 = stops[idx + 1];
  const rgb = [
    Math.round(c1[0] + (c2[0] - c1[0]) * f),
    Math.round(c1[1] + (c2[1] - c1[1]) * f),
    Math.round(c1[2] + (c2[2] - c1[2]) * f)
  ];
  return `rgb(${rgb[0]},${rgb[1]},${rgb[2]})`;
}

// Initialize DOM structures for A-Z histogram and QWERTY keyboard
function initStaticDOM() {
  const histBars = document.getElementById('histBars');
  histBars.innerHTML = '';
  for (let i = 0; i < 26; i++) {
    const ch = String.fromCharCode(65 + i);
    const isV = 'AEIOU'.includes(ch);
    const col = document.createElement('div');
    col.className = 'hbar-col';
    col.innerHTML = `<div class="hbar-fill ${isV ? 'vowel' : 'cons'}" id="hbar_${i}" style="height:2px"></div><div class="hbar-lbl" id="hlbl_${i}">${ch}</div>`;
    histBars.appendChild(col);
  }

  const kbWrap = document.getElementById('kbWrap');
  kbWrap.innerHTML = '';
  KB_ROWS.forEach((row) => {
    const rDiv = document.createElement('div');
    rDiv.className = 'kb-row';
    row.forEach((k) => {
      const cap = document.createElement('div');
      cap.className = 'keycap';
      cap.id = 'kcap_' + k;
      cap.textContent = k;
      rDiv.appendChild(cap);
    });
    kbWrap.appendChild(rDiv);
  });
  const spRow = document.createElement('div');
  spRow.className = 'kb-row';
  spRow.innerHTML = `<div class="keycap space" id="kcap_SPC">SPACE</div>`;
  kbWrap.appendChild(spRow);
}

function topEntries(obj, n = 5) {
  return Object.entries(obj || {})
    .filter(([, v]) => v > 0)
    .sort((a, b) => b[1] - a[1])
    .slice(0, n);
}

function computeXPAndBadges(s) {
  const xp = (s.totalKeys || 0) * 3 + (s.words || 0) * 10 + (s.bestStreak || 0) * 2;
  const level = 1 + Math.floor(xp / 250);
  const rank = RANKS[Math.min(RANKS.length - 1, level - 1)];
  const badges = [
    { name: 'First Steps (50+ keys)', ok: s.totalKeys >= 50 },
    { name: 'Speed Demon (60+ Peak WPM)', ok: s.wpmPeak >= 60 },
    { name: 'Hyper Velocity (100+ Peak WPM)', ok: s.wpmPeak >= 100 },
    { name: 'Flawless Streak (100+ streak)', ok: s.bestStreak >= 100 },
    { name: 'Marathon Runner (500+ keys)', ok: s.totalKeys >= 500 },
    { name: 'Polyglot Coder (20+ digits/symbols)', ok: (s.digits + s.symbols) >= 20 }
  ];
  return { xp, level, rank, badges };
}

function render(s) {
  curState = s;
  document.documentElement.setAttribute('data-theme', s.theme || 'midnight');
  document.getElementById('lblSound').textContent = s.soundOn ? 'Sound:On' : 'Sound:Off';
  const hudBtn = document.getElementById('lblHud');
  if (hudBtn) hudBtn.textContent = (s.hudOn !== false) ? 'HUD:On' : 'HUD:Off';

  const { xp, level, rank, badges } = computeXPAndBadges(s);
  document.getElementById('hdrLevel').textContent = 'LVL ' + level;
  document.getElementById('hdrRank').textContent = rank;

  const stBadge = document.getElementById('hdrStatus');
  const stTxt = document.getElementById('hdrStatusTxt');
  if (s.paused) {
    stBadge.classList.add('paused');
    stTxt.textContent = 'PAUSED';
    document.getElementById('lblPause').textContent = 'Resume';
  } else {
    stBadge.classList.remove('paused');
    stTxt.textContent = 'LIVE';
    document.getElementById('lblPause').textContent = 'Pause';
  }

  const elapsedSec = Math.floor((Date.now() - (s.startTick || Date.now())) / 1000);
  document.getElementById('hdrTime').textContent = formatMMSS(elapsedSec);

  // Cards
  const letters = Math.max(1, s.vowels + s.consonants);
  document.getElementById('valVowels').textContent = s.vowels;
  document.getElementById('pctVowels').textContent = Math.round((s.vowels * 100) / letters);
  document.getElementById('valCons').textContent = s.consonants;
  document.getElementById('pctCons').textContent = Math.round((s.consonants * 100) / letters);
  document.getElementById('valTotal').textContent = s.totalKeys;
  document.getElementById('valWpm').textContent = s.wpmNow;
  document.getElementById('valPeak').textContent = s.wpmPeak;
  document.getElementById('valAvg').textContent = s.wpmAvg;

  // Chips & Mix Bar
  document.getElementById('chDigits').textContent = s.digits;
  document.getElementById('chSpaces').textContent = s.spaces;
  document.getElementById('chSymbols').textContent = s.symbols;
  document.getElementById('chOthers').textContent = s.others;
  document.getElementById('chWords').textContent = s.words;
  const vPct = (s.vowels + s.consonants) > 0 ? Math.round((s.vowels * 100) / letters) : 50;
  document.getElementById('mixV').style.width = vPct + '%';
  document.getElementById('mixC').style.width = (100 - vPct) + '%';

  // Last N Characters
  document.getElementById('valN').textContent = s.nView || 32;
  const lastNBox = document.getElementById('lastNBox');
  lastNBox.innerHTML = '';
  const slice = (s.lastChars || []).slice(-(s.nView || 32));
  slice.forEach((ch, idx) => {
    const sp = document.createElement('span');
    sp.className = 'char-cell' + (idx === slice.length - 1 ? ' newest' : '');
    sp.textContent = ch === ' ' ? '␣' : ch;
    lastNBox.appendChild(sp);
  });
  document.getElementById('valLastKey').textContent = s.lastKeyName || '-';
  document.getElementById('valLastAscii').textContent = s.lastKeyCode || 0;

  // A-Z Histogram
  let maxLet = 0;
  const letCounts = [];
  for (let i = 0; i < 26; i++) {
    const u = String.fromCharCode(65 + i);
    const l = String.fromCharCode(97 + i);
    const c = (s.freq[u] || 0) + (s.freq[l] || 0);
    letCounts.push(c);
    if (c > maxLet) maxLet = c;
  }
  document.getElementById('histMax').textContent = maxLet;
  for (let i = 0; i < 26; i++) {
    const bar = document.getElementById('hbar_' + i);
    const lbl = document.getElementById('hlbl_' + i);
    const h = maxLet > 0 ? Math.max(2, Math.round((letCounts[i] / maxLet) * 86)) : 2;
    if (bar) bar.style.height = h + 'px';
    if (lbl) {
      const active = (s.lastKeyName || '').toUpperCase() === String.fromCharCode(65 + i);
      lbl.className = 'hbar-lbl' + (active ? ' active' : '');
    }
  }

  // Keyboard Heatmap
  const vkValues = Object.values(s.vkFreq || {});
  const heatMax = Math.max(1, ...vkValues);
  KB_ROWS.flat().forEach((k) => {
    const cap = document.getElementById('kcap_' + k);
    if (!cap) return;
    const cnt = s.vkFreq[k] || 0;
    cap.style.background = heatColor(cnt, heatMax);
    cap.style.color = cnt > 0 ? '#fff' : 'var(--muted)';
  });
  const spCap = document.getElementById('kcap_SPC');
  if (spCap) {
    const spCnt = s.vkFreq['SPC'] || s.vkFreq[' '] || 0;
    spCap.style.background = heatColor(spCnt, heatMax);
    spCap.style.color = spCnt > 0 ? '#fff' : 'var(--muted)';
  }

  // WPM History SVG
  const hist = s.wpmHist || [];
  const wMax = Math.max(20, ...hist);
  document.getElementById('wpmHistMax').textContent = wMax;
  if (hist.length > 0) {
    const pts = hist.map((v, idx) => {
      const x = Math.round(((52 - hist.length + idx) / 51) * 520);
      const y = Math.round(58 - (v / wMax) * 52);
      return `${x},${y}`;
    });
    const startX = Math.round(((52 - hist.length) / 51) * 520);
    document.getElementById('wpmLine').setAttribute('points', pts.join(' '));
    document.getElementById('wpmArea').setAttribute('points', `${startX},60 ${pts.join(' ')} 520,60`);
  }

  // Top 5 Table
  const topK = topEntries(s.freq, 5);
  const topB = topEntries(s.bigrams, 5);
  const topT = topEntries(s.trigrams, 5);
  const tbody = document.getElementById('top5Body');
  tbody.innerHTML = '';
  for (let i = 0; i < 5; i++) {
    const k = topK[i] || ['-', ''];
    const b = topB[i] || ['-', ''];
    const t = topT[i] || ['-', ''];
    const tr = document.createElement('tr');
    tr.innerHTML = `
      <td style="color:var(--gold)">${i + 1}</td>
      <td style="color:var(--cyan)">${k[0]}</td><td class="num">${k[1]}</td>
      <td>${b[0]}</td><td class="num" style="color:var(--purp)">${b[1]}</td>
      <td>${t[0]}</td><td class="num" style="color:var(--green)">${t[1]}</td>
    `;
    tbody.appendChild(tr);
  }

  // Bottom Stats Strip
  const corrRate = s.totalKeys > 0 ? Math.round((s.bsCount * 100) / s.totalKeys) : 0;
  document.getElementById('stLongest').textContent = s.longestWord || 0;
  document.getElementById('stBs').textContent = s.bsCount || 0;
  document.getElementById('stErr').textContent = corrRate + '%';
  document.getElementById('stStreak').textContent = s.bestStreak || 0;
  document.getElementById('stLat').textContent = (s.avgLatMs || 0) + 'ms';

  // Biomechanics & Achievements View (View 2)
  const totH = Math.max(1, (s.leftHand || 0) + (s.rightHand || 0));
  document.getElementById('erLH').textContent = Math.round(((s.leftHand || 0) * 100) / totH) + '%';
  document.getElementById('erLHKeys').textContent = s.leftHand || 0;
  document.getElementById('erRH').textContent = Math.round(((s.rightHand || 0) * 100) / totH) + '%';
  document.getElementById('erRHKeys').textContent = s.rightHand || 0;
  document.getElementById('erAlt').textContent = s.handAlt || 0;
  document.getElementById('erAlt2').textContent = s.handAlt || 0;
  document.getElementById('erLat').textContent = s.avgLatMs || 0;
  document.getElementById('erMinLat').textContent = s.minLatMs || 0;
  document.getElementById('erStreak').textContent = s.curStreak || 0;
  document.getElementById('erBestStreak').textContent = s.bestStreak || 0;
  document.getElementById('erXP').textContent = xp;
  document.getElementById('erActiveTime').textContent = formatMMSS(Math.floor((s.activeMs || 0) / 1000));

  const fBars = document.getElementById('fingerBars');
  fBars.innerHTML = '';
  FINGER_NAMES.forEach((name, idx) => {
    const cnt = (s.fingerCnt && s.fingerCnt[idx]) || 0;
    const pct = s.totalKeys > 0 ? Math.round((cnt * 100) / s.totalKeys) : 0;
    const col = idx < 4 ? 'var(--cyan)' : (idx < 8 ? 'var(--purp)' : 'var(--green)');
    fBars.innerHTML += `<div class="bar-row"><span class="bar-lbl">${name}</span><div class="bar-track"><div class="bar-fill" style="width:${pct}%;background:${col}"></div></div><span style="width:65px;text-align:right">${cnt} (${pct}%)</span></div>`;
  });

  const rBars = document.getElementById('rowBars');
  rBars.innerHTML = '';
  ROW_NAMES.forEach((name, idx) => {
    const cnt = (s.rowCnt && s.rowCnt[idx]) || 0;
    const pct = s.totalKeys > 0 ? Math.round((cnt * 100) / s.totalKeys) : 0;
    rBars.innerHTML += `<div class="bar-row"><span class="bar-lbl" style="width:130px">${name}</span><div class="bar-track"><div class="bar-fill" style="width:${pct}%;background:var(--amber)"></div></div><span style="width:65px;text-align:right">${cnt} (${pct}%)</span></div>`;
  });

  const bGrid = document.getElementById('badgesGrid');
  bGrid.innerHTML = '';
  let unlockedCnt = 0;
  badges.forEach((b) => {
    if (b.ok) unlockedCnt++;
    bGrid.innerHTML += `<div class="badge-item ${b.ok ? 'unlocked' : 'locked'}"><span class="b-tag">${b.ok ? '[UNLOCKED]' : '[LOCKED]'}</span><span>${b.name}</span></div>`;
  });
  document.getElementById('erBadgeSummary').textContent = `${unlockedCnt} / ${badges.length} Unlocked`;
}

// Typing Test Logic
function resetTypingTest(nextSent = false) {
  const modeKey = MODE_KEYS[ttModeIdx];
  const list = TEST_SENTENCES[modeKey];
  if (nextSent) ttSentIdx = (ttSentIdx + 1) % list.length;
  ttTarget = list[ttSentIdx];
  ttTyped = '';
  ttErrors = 0;
  ttKeys = 0;
  ttStart = 0;
  ttDone = false;
  document.getElementById('ttModeName').textContent = modeKey;
  renderTypingTest();
}

function renderTypingTest() {
  const box = document.getElementById('ttSentence');
  box.innerHTML = '';
  let correct = 0;
  for (let i = 0; i < ttTarget.length; i++) {
    const sp = document.createElement('span');
    sp.className = 't-ch';
    sp.textContent = ttTarget[i];
    if (i < ttTyped.length) {
      if (ttTyped[i] === ttTarget[i]) {
        sp.classList.add('ok');
        correct++;
      } else {
        sp.classList.add('err');
      }
    } else if (i === ttTyped.length && !ttDone) {
      sp.classList.add('cur');
    }
    box.appendChild(sp);
  }
  const pct = Math.round((ttTyped.length * 100) / ttTarget.length);
  document.getElementById('ttProg').style.width = pct + '%';

  const elapsedMs = ttStart > 0 ? Math.max(500, Date.now() - ttStart) : 0;
  const wpm = elapsedMs > 0 ? Math.round((correct * 12000) / elapsedMs) : 0;
  const acc = ttKeys > 0 ? Math.max(0, Math.round(((ttKeys - ttErrors) * 100) / ttKeys)) : 100;
  document.getElementById('ttWpm').textContent = wpm;
  document.getElementById('ttAcc').textContent = acc;
  document.getElementById('ttErr').textContent = ttErrors;
  document.getElementById('ttTime').textContent = Math.floor(elapsedMs / 1000);
  if (curState) {
    document.getElementById('ttBest').textContent = curState.testBest || 0;
    document.getElementById('ttAllBest').textContent = curState.allTimeTestBest || 0;
  }
}

function switchView(mode) {
  viewMode = mode;
  document.getElementById('viewDash').classList.toggle('hidden', mode !== 0);
  document.getElementById('viewTest').classList.toggle('hidden', mode !== 1);
  document.getElementById('viewErgo').classList.toggle('hidden', mode !== 2);
  document.getElementById('lblTest').textContent = mode === 1 ? 'Dash' : 'Test';
  if (mode === 1) resetTypingTest(false);
}

// Export HTML, CSV and JSON reports
function exportReports() {
  if (!curState) return;
  const s = curState;
  const jsonBlob = new Blob([JSON.stringify(s, null, 2)], { type: 'application/json' });
  const jsonUrl = URL.createObjectURL(jsonBlob);
  const a1 = document.createElement('a');
  a1.href = jsonUrl;
  a1.download = 'KeyReport.json';
  a1.click();

  let csv = 'metric,value\r\n';
  csv += `Total keys,${s.totalKeys}\r\nVowels,${s.vowels}\r\nConsonants,${s.consonants}\r\nWords,${s.words}\r\nPeak WPM,${s.wpmPeak}\r\nAverage WPM,${s.wpmAvg}\r\nAvg Latency ms,${s.avgLatMs}\r\nBest Streak,${s.bestStreak}\r\n\r\nkey,count\r\n`;
  Object.entries(s.freq || {}).forEach(([k, v]) => { csv += `"${k}",${v}\r\n`; });
  const csvBlob = new Blob([csv], { type: 'text/csv' });
  const a2 = document.createElement('a');
  a2.href = URL.createObjectURL(csvBlob);
  a2.download = 'KeyReport.csv';
  a2.click();
  showToast('✓ Exported KeyReport.json and KeyReport.csv');
}

document.addEventListener('DOMContentLoaded', () => {
  initStaticDOM();
  resetTypingTest(false);

  chrome.runtime.sendMessage({ type: 'KPM_GET_STATE' }, (res) => {
    if (res && res.state) render(res.state);
  });

  setInterval(() => {
    chrome.runtime.sendMessage({ type: 'KPM_GET_STATE' }, (res) => {
      if (res && res.state) render(res.state);
    });
    if (viewMode === 1 && ttStart > 0 && !ttDone) renderTypingTest();
  }, 300);

  // Buttons
  function doResetAll() {
    chrome.runtime.sendMessage({ type: 'KPM_RESET', clearAll: true }, (res) => {
      if (res && res.state) render(res.state);
      resetTypingTest(false);
      showToast('✓ All records refreshed & cleared to 0');
    });
  }

  document.getElementById('btnReset').addEventListener('click', doResetAll);
  const hdrReset = document.getElementById('btnHeaderReset');
  if (hdrReset) hdrReset.addEventListener('click', doResetAll);

  const hudToggle = document.getElementById('btnHud');
  if (hudToggle) {
    hudToggle.addEventListener('click', () => {
      const next = (curState && curState.hudOn === false) ? true : false;
      chrome.runtime.sendMessage({ type: 'KPM_SET_PREFS', hudOn: next }, (res) => {
        if (res && res.state) render(res.state);
        showToast(next ? '✓ Floating webpage HUD enabled' : '✗ Floating webpage HUD hidden');
      });
    });
  }

  document.getElementById('btnExport').addEventListener('click', exportReports);

  document.getElementById('btnPause').addEventListener('click', () => {
    chrome.runtime.sendMessage({ type: 'KPM_TOGGLE_PAUSE' }, (res) => {
      if (res && res.state) render(res.state);
    });
  });

  document.getElementById('btnTest').addEventListener('click', () => {
    switchView(viewMode === 1 ? 0 : 1);
  });

  document.getElementById('btnErgo').addEventListener('click', () => {
    switchView(viewMode === 2 ? 0 : 2);
  });

  document.getElementById('btnTheme').addEventListener('click', () => {
    const cur = (curState && curState.theme) || 'midnight';
    const next = THEMES[(THEMES.indexOf(cur) + 1) % THEMES.length];
    chrome.runtime.sendMessage({ type: 'KPM_SET_PREFS', theme: next }, (res) => {
      if (res && res.state) render(res.state);
      showToast('✓ Theme: ' + next.toUpperCase());
    });
  });

  document.getElementById('btnSound').addEventListener('click', () => {
    const next = !(curState && curState.soundOn);
    chrome.runtime.sendMessage({ type: 'KPM_SET_PREFS', soundOn: next }, (res) => {
      if (res && res.state) render(res.state);
      showToast(next ? '✓ Mechanical sound ON' : '✗ Mechanical sound OFF');
    });
  });

  document.getElementById('btnOpenTab').addEventListener('click', () => {
    chrome.tabs.create({ url: chrome.runtime.getURL('popup.html') });
  });

  document.getElementById('btnNDec').addEventListener('click', () => {
    const n = Math.max(8, ((curState && curState.nView) || 32) - 4);
    chrome.runtime.sendMessage({ type: 'KPM_SET_PREFS', nView: n }, (res) => {
      if (res && res.state) render(res.state);
    });
  });

  document.getElementById('btnNInc').addEventListener('click', () => {
    const n = Math.min(64, ((curState && curState.nView) || 32) + 4);
    chrome.runtime.sendMessage({ type: 'KPM_SET_PREFS', nView: n }, (res) => {
      if (res && res.state) render(res.state);
    });
  });

  document.getElementById('btnCycleMode').addEventListener('click', () => {
    ttModeIdx = (ttModeIdx + 1) % MODE_KEYS.length;
    ttSentIdx = 0;
    resetTypingTest(false);
  });

  document.getElementById('btnNextSent').addEventListener('click', () => {
    resetTypingTest(true);
  });

  // Keyboard listener inside the extension popup/tab itself
  window.addEventListener('keydown', (e) => {
    if (e.key === 'F1') { e.preventDefault(); document.getElementById('btnReset').click(); return; }
    if (e.key === 'F2') { e.preventDefault(); exportReports(); return; }
    if (e.key === 'F3') { e.preventDefault(); document.getElementById('btnPause').click(); return; }
    if (e.key === 'F5') { e.preventDefault(); document.getElementById('btnTest').click(); return; }
    if (e.key === 'F6') { e.preventDefault(); document.getElementById('btnErgo').click(); return; }
    if (e.key === 'F7') { e.preventDefault(); document.getElementById('btnTheme').click(); return; }
    if (e.key === 'F8') { e.preventDefault(); document.getElementById('btnSound').click(); return; }

    if (viewMode === 1 && e.key === 'Tab') {
      e.preventDefault();
      document.getElementById('btnCycleMode').click();
      return;
    }

    if (['Shift', 'Control', 'Alt', 'Meta', 'CapsLock'].includes(e.key)) return;

    playClickSound(e.key);

    // Visual ripple on heatmap
    const kId = e.key === ' ' ? 'SPC' : e.key.toUpperCase();
    const cap = document.getElementById('kcap_' + kId);
    if (cap) {
      cap.classList.add('ripple');
      setTimeout(() => cap.classList.remove('ripple'), 220);
    }

    // Send key to background state
    chrome.runtime.sendMessage({
      type: 'KPM_KEY',
      payload: { key: e.key, code: e.code }
    }, (res) => {
      if (res && res.state) render(res.state);
    });

    // If Typing Test view is active, handle sentence input
    if (viewMode === 1) {
      if (ttDone) {
        if (e.key === 'Enter') resetTypingTest(true);
        return;
      }
      if (e.key === 'Backspace') {
        if (ttTyped.length > 0) ttTyped = ttTyped.slice(0, -1);
        renderTypingTest();
        return;
      }
      if (e.key.length === 1) {
        if (ttStart === 0) ttStart = Date.now();
        const expected = ttTarget[ttTyped.length];
        ttTyped += e.key;
        ttKeys++;
        if (e.key !== expected) ttErrors++;
        if (ttTyped.length >= ttTarget.length) {
          ttDone = true;
          renderTypingTest();
          const finalWpm = parseInt(document.getElementById('ttWpm').textContent, 10) || 0;
          chrome.runtime.sendMessage({ type: 'KPM_SET_PREFS', testBest: finalWpm }, (res) => {
            if (res && res.state) render(res.state);
          });
          document.getElementById('ttStatus').innerHTML = `<b style="color:var(--green)">Sentence complete!</b> Speed: <b>${finalWpm} WPM</b> · Press <b>Enter</b> for the next sentence or <b>Tab</b> to switch category.`;
        } else {
          renderTypingTest();
        }
      }
    }
  });
});
