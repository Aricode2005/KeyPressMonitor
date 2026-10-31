<div align="center">

# ⌨️ KeyPressMonitor

**A real-time keyboard analytics dashboard, typing trainer & ergonomics suite — built in 32-bit MASM Assembly and packaged with a full Chrome Extension (Manifest V3).**

![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20Chrome%20Extension-0078D6?logo=windows&logoColor=white)
![Language](https://img.shields.io/badge/language-MASM%20x86%20%2B%20JS%20MV3-informational)
![Dependencies](https://img.shields.io/badge/dependencies-kernel32%20only-success)
![License](https://img.shields.io/badge/license-MIT-blue)

![Dashboard while typing](screenshots/dashboard.png)

</div>

Type anywhere in the console (or across any webpage with the Chrome Extension) and watch live statistics: vowels vs. consonants, a per-key frequency histogram, a QWERTY heatmap with key-press ripples, n-gram (bigram/trigram) rankings, hand & finger biomechanics, inter-key rhythm/latency, XP levels & achievements, a multi-mode typing test, and a rolling view of the last N characters. The native MASM build uses **only `kernel32.lib`** — no Irvine32, no MASM32 SDK.

## Table of contents

- [Features](#features) · [Controls](#controls) · [Quick start (MASM)](#quick-start) · [Chrome Extension (Install & Publish)](#chrome-extension-install--publish-guide) · [Sample report](#sample-report) · [How it works](#how-it-works-short) · [Project layout](#project-layout) · [Troubleshooting](#troubleshooting) · [License](#license)

## Features

**Required**

1. Counts **vowels and consonants** (big cards at the top, plus a vowel/consonant mix bar)
2. **Frequency of every key** (A-Z histogram, top-5 table, and the full table in the report)
3. Shows the **last N characters** typed (circular buffer; the newest key is highlighted)

**Extra**

| Feature | How it's done in MASM |
|---------|-----------------------|
| 24-bit colour dashboard | Every cell (Unicode character + RGB foreground + RGB background) is drawn into a 100x30 canvas, then sent as **one** `WriteConsoleW` call of VT escape sequences, so there is no flicker |
| Gradients and rounded panels | Colours are blended per cell (`Lerp`, `Ramp`): gradient header, numbers, bars and heatmap; panels use rounded corners `╭╮╰╯` |
| Works in any console | Windows Terminal gets the full look. The classic console gets the same colours with simpler bar characters (its font lacks 1/8 blocks). Without VT support it falls back to the 16-colour console (`WriteConsoleOutputW`, nearest colour per cell) |
| Big numbers + sparklines | A 3x3 block font with a top-to-bottom gradient; each card has a sparkline of the last 16 seconds |
| A-Z letter histogram | Bars built from 1/8-step blocks (`▁▂▃▄▅▆▇█`, 40 levels) with a vertical gradient; vowels green, consonants amber |
| Keyboard heatmap | QWERTY keycaps on a smooth cold-to-hot colour ramp, by how often each virtual key was pressed |
| Typing speed | Live WPM (keys in the last 5 s), peak WPM, average WPM and a session timer via `GetTickCount` |
| Top 5 keys + N-gram tracker | Counts every letter pair (676-entry table) and letter triple (17,576-entry table) inside words; shows the top 5 keys, bigrams and trigrams side by side |
| Ergonomics & Biomechanics (F6) | Tracks Left vs. Right hand balance %, hand alternations, 8-finger load distribution (`L-Pinky`..`R-Pinky` + `Thumbs`), and keyboard row usage (`Number`, `Top`, `Home`, `Bottom`, `Space`) |
| Rhythm & Cadence analytics | Measures average inter-key latency (ms), fastest key transition (ms), and active typing time (filtering idle pauses >= 2 s) |
| Achievements, Streaks & XP Rank | Tracks live & best error-free key streaks, computes XP & rank (`NOVICE` → `TYPIST` → `PRO` → `MASTER` → `GRANDMASTER`), and unlocks 6 achievement badges |
| Custom Themes (F7) & Sound (F8) | `F7` cycles 4 colour themes (`Midnight`, `Cyberpunk Neon`, `Matrix Hacker`, `Nord Frost`). `F8` toggles synthesized mechanical key clicks via `Beep` |
| Multi-Mode Typing Test (F5 / Tab) | `F5` opens the typing test; `Tab` cycles 4 practice categories (`STANDARD`, `QUOTES`, `CODE`, `NUMBERS`). Tracks live WPM, accuracy %, errors, session best and all-time best |
| Multi-format Export (F2) | Writes `KeyReport.txt`, `KeyReport.html` (with charts, opened in browser), `KeyReport.csv` and `KeyReport.json` |
| Compare with last session | Each session is saved to `KeyStats.dat` on exit. The next run shows `VS LAST` (average and peak WPM with up/down arrows, all-time best) |
| Key-press ripple | The pressed key flashes white on the heatmap and a ring spreads to the keys around it; the card numbers count up at ~30 fps |
| Help overlay (F9) | One screen with every key (with the live autosave, theme and sound state) and what each screen and panel shows |
| Session replay (F10) | Every live key is recorded with its timing (`KeySession.kpm`, written on exit). F10 replays the last session on the dashboard at real speed, so a demo never depends on live typing (pauses over 3 s are shortened) |
| Ghost race | The typing test keeps your best run of each sentence (`KeyGhost.dat`): a ▲ ghost marker moves under the sentence at your old pace, with "you are N chars ahead/behind", and the result says whether you beat it |
| Heatmap modes (Up / Down) | The keyboard heatmap switches between **frequency**, **speed** (average ms to reach each key; slow keys are hot) and **test misses** (keys you got wrong in the typing test). Click the heatmap to cycle too |
| Text analysis (F6 twice) | Shannon entropy of your letters (bits/letter), % overlap with English letter shares, a chi-squared test against English (df 25), and the Caesar shift that makes the text most English-like (it decodes ROT-n). Computed on the x87 FPU (`FYL2X` for log2), also in both reports |
| Self-test (`/selftest`) | `KeyMonitor.exe /selftest` types a known sentence through the real counting code and checks 15 results (vowels, consonants, frequency, last N, words, n-grams...). Prints PASS/FAIL and exits with the number of failures; CI runs it on every push |
| Chrome Extension (Manifest V3) | Full browser extension in `chrome-extension/` with popup & full-tab dashboard, live webpage keystroke telemetry, all 3 views, 4 themes, Web Audio synth clicks, and JSON/CSV export |

## Controls

| Key | Action |
|-----|--------|
| F1 | Reset all counters |
| F2 | Export `KeyReport.txt`, `KeyReport.html`, `KeyReport.csv`, and `KeyReport.json` |
| F3 | Pause / resume counting |
| F4 | Toggle autosave of the reports on exit |
| F5 | Typing test screen / back to dashboard (`Enter` = next sentence, `Tab` = cycle mode) |
| F6 | Biomechanics & achievements screen, press again for text analysis, again for the dashboard |
| F7 | Cycle colour theme (`Midnight` → `Cyberpunk` → `Matrix` → `Nord`) |
| F8 | Toggle mechanical key click sound |
| F9 | Help: every key and screen |
| F10 | Replay the last session (again = stop) |
| Up / Down | Heatmap mode: frequency / speed / test misses |
| Left / Right, mouse wheel | Change N (8 to 64) |
| ESC | Quit and print the final report |

The buttons at the bottom can be clicked with the mouse (F1, F2, F3, F5, F6, F9, ESC); F4, F7 and F8 are listed in the F9 help.

| Typing test (F5) | HTML report (F2) |
|------------------|------------------|
| ![Typing test](screenshots/typing-test.png) | ![HTML report](screenshots/html-report.png) |
| **Ghost race (F5)** | **Text analysis (F6, F6)** |
| ![Ghost race](screenshots/ghost-race.png) | ![Text analysis](screenshots/text-analysis.png) |
| **Biomechanics & XP (F6)** | **Help (F9)** |
| ![Biomechanics](screenshots/biomechanics.png) | ![Help](screenshots/help.png) |

---

## Quick start

### 1. Install the tools (one time only)

1. Download **Visual Studio Community** (free): https://visualstudio.microsoft.com/
2. In the installer, tick **"Desktop development with C++"** and install.
   This gives you `ml.exe` (MASM) and `link.exe`.

### 2. Get the code

```bat
git clone https://github.com/Aricode2005/KeyPressMonitor.git
cd KeyPressMonitor
```

### 3. Build

1. Open the Start menu and search for **"x86 Native Tools Command Prompt for VS"**.
   > It must be **x86** (32-bit), not x64.
2. `cd` into the `KeyPressMonitor` folder.
3. Run:

```bat
build.bat
```

Or build by hand:

```bat
ml /c /coff KeyMonitor.asm
link /subsystem:console KeyMonitor.obj kernel32.lib
```

### 4. Run

```bat
KeyMonitor.exe
```

Check that the counters work (no window needed, prints PASS/FAIL):

```bat
KeyMonitor.exe /selftest
```

**Best in Windows Terminal** (built into Windows 11; free from the Microsoft Store on Windows 10). It also runs in the classic console with slightly simpler bars.
The dashboard needs a console of at least 100 x 30 characters (the default Windows console is 120 x 30).

---

## Chrome Extension (Install & Publish Guide)

The repository includes a complete **Manifest V3 Chrome Extension** in [`chrome-extension/`](chrome-extension/) with the exact same visual dashboard, typing test modes, biomechanics & achievement screens, themes, and CSV/JSON export.

### Load Unpacked in Google Chrome (Developer Mode)
1. Open Google Chrome and navigate to `chrome://extensions/`.
2. Enable **Developer mode** (toggle in the top-right corner).
3. Click **Load unpacked** (top-left button).
4. Select the `chrome-extension` folder inside this repository.
5. Pin **KeyPressMonitor** to your toolbar and click its icon (or click **⛶ Full Tab** inside the popup to open the full-screen analytics dashboard).

### Publish to the Chrome Web Store
1. Run `package-extension.bat` (or zip the contents of `chrome-extension/` into `KeyPressMonitor-Chrome-Extension.zip`).
2. Open the [Chrome Web Store Developer Dashboard](https://chrome.google.com/webstore/devconsole).
3. Click **New Item** and upload `KeyPressMonitor-Chrome-Extension.zip`.
4. Fill in the store listing details (description, screenshots from `screenshots/`, category: **Productivity / Developer Tools**), declare that keystrokes are processed 100% locally in `chrome.storage.local` (never transmitted externally, and password inputs are ignored), and click **Submit for review**.

---

## Sample report

Printed when you press ESC, and saved to `KeyReport.txt` (alongside `.html`, `.csv`, and `.json`) with F2:

```
========== KEY PRESS MONITOR - REPORT ==========
Total keys       : 166
Total Vowels     : 43
Total Consonants : 78
Digits           : 6
Spaces           : 31
Symbols          : 5
Other keys       : 3
Words typed      : 34
Longest word     : 6
Backspaces       : 2
Correction rate %: 1
Peak WPM         : 91
Average WPM      : 70
Typing test best : 57
Left hand keys   : 74
Right hand keys  : 58
Avg latency (ms) : 112
Best key streak  : 84
XP Level         : 4
Badges unlocked  : 3
Session time     : 00:28
Last N chars     : [asy, see you at the demo]
```

## Project layout

```
KeyPressMonitor/
├── KeyMonitor.asm          # 32-bit MASM program: header, INCLUDE list, main loop
├── src/                    # the program's modules, included in this order:
│   ├── defs.inc            #   API prototypes and constants
│   ├── data.inc            #   variables, tables and text
│   ├── render.inc          #   canvas primitives, VT / 16-colour output
│   ├── stats.inc           #   counting: classify, n-grams, biomechanics, WPM
│   ├── session.inc         #   typing test, last-session stats
│   ├── selftest.inc        #   KeyMonitor.exe /selftest
│   ├── dashboard.inc       #   dashboard, typing test, biomechanics, help screens
│   ├── reports.inc         #   text and HTML reports
│   ├── actions.inc         #   actions and keyboard / mouse input
│   └── console.inc         #   console setup and restore
├── build.bat               # one-step MASM build (x86 Native Tools prompt)
├── package-extension.bat   # packs chrome-extension/ into a Web Store .zip
├── chrome-extension/       # Manifest V3 Chrome Extension
│   ├── manifest.json
│   ├── background.js       # service worker (state, n-grams, biomechanics, WPM)
│   ├── content.js          # privacy-safe webpage keystroke listener
│   ├── popup.html          # 3-view dashboard (Main, Typing Test, Bio/XP)
│   ├── dashboard.js        # UI controller, Web Audio synth, CSV/JSON exporter
│   ├── styles.css          # 4 themes (Midnight, Cyberpunk, Matrix, Nord)
│   └── icons/              # 16x16, 48x48, 128x128 extension icons
├── screenshots/            # images used in this README
├── .github/workflows/      # CI: builds KeyMonitor.asm and runs the self-test on every push
├── CONTRIBUTING.md
└── LICENSE
```

## License

Released under the [MIT License](LICENSE).
