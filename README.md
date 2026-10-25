<div align="center">

# ⌨️ KeyPressMonitor

**A real-time keyboard analytics dashboard written entirely in 32-bit MASM assembly.**

![Platform](https://img.shields.io/badge/platform-Windows-0078D6?logo=windows&logoColor=white)
![Language](https://img.shields.io/badge/language-MASM%20x86-informational)
![Dependencies](https://img.shields.io/badge/dependencies-kernel32%20only-success)
![License](https://img.shields.io/badge/license-MIT-blue)

![Dashboard while typing](screenshots/dashboard.png)

</div>

Type anywhere in the console and watch live statistics: vowels vs. consonants, a per-key frequency histogram, a keyboard heatmap, typing speed (WPM) and a rolling view of the last N characters. No Irvine32, no MASM32 SDK: just `kernel32.lib`.

## Table of contents

- [Features](#features) · [Controls](#controls) · [Quick start](#quick-start) · [Sample report](#sample-report) · [How it works](#how-it-works-short) · [Project layout](#project-layout) · [Troubleshooting](#troubleshooting) · [License](#license)
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
| Top 5 keys | Selection over the 256-entry frequency table |
| N-gram tracker | Counts every letter pair (676-entry table) and letter triple (17,576-entry table) inside words; shows the top 5 bigrams and trigrams next to the top 5 keys |
| Word counter | A run of letters/digits counts as one word; shown as a WORDS chip and in the report |
| More categories | Separate counters for digits, spaces, symbols and other keys (Enter, Tab, Backspace...) |
| Mouse buttons | `ReadConsoleInputA` mouse events: click Reset / Save / Pause / Quit, buttons highlight on hover |
| Adjustable N | Left/Right arrows or the mouse wheel change N from 8 to 64 |
| Pause | F3 stops counting (shown in the header and the button bar) |
| Save report | F2 writes `KeyReport.txt` with `CreateFileA` / `WriteFile`; the same report is printed on exit |
| Longest word + correction rate | Longest run of letters/digits, Backspace count and Backspace-to-keys ratio |
| WPM history graph | One WPM sample per second kept in a 64-entry ring; the last 52 s drawn as a gradient area chart (24 levels) |
| Autosave on exit | F4 (or its button) toggles saving `KeyReport.txt` automatically when you press ESC; the button turns green when on |

## Controls

| Key | Action |
|-----|--------|
| F1 | Reset all counters |
| F2 | Save report to `KeyReport.txt` |
| F3 | Pause / resume counting |
| F4 | Toggle autosave of the report on exit |
| Left / Right, mouse wheel | Change N |
| ESC | Quit and print the final report |

All buttons can also be clicked with the mouse.

| Start | Paused, N = 24 |
|-------|----------------|
| ![Start](screenshots/start.png) | ![Paused](screenshots/paused.png) |

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

**Best in Windows Terminal** (built into Windows 11; free from the Microsoft Store on Windows 10). It also runs in the classic console with slightly simpler bars.
The dashboard needs a console of at least 100 x 30 characters (the default Windows console is 120 x 30).

## Sample report

Printed when you press ESC, and saved to `KeyReport.txt` with F2:

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
Session time     : 00:28
Last N chars     : [asy, see you at the demo]

Top 5 keys:
  1.  SPC   x 31
  2.  e     x 17
  3.  h     x 9
  4.  o     x 9
  5.  t     x 9

Top 5 bigrams:
  1.  th    x 7
  2.  he    x 6
  3.  as    x 3
  4.  en    x 3
  5.  ck    x 2

Top 5 trigrams:
  1.  the   x 5
  2.  asy   x 2
  3.  eas   x 2
  4.  ack   x 1
  5.  asm   x 1

Key Frequency:
  e    (ASCII 101)  ->  17
  ...
```

## How it works (short)

| Part | What it does |
|------|--------------|
| `SetConsoleMode(hIn, 98h)` | Raw input with mouse events on (QuickEdit off), so keys and clicks arrive instantly |
| `WaitForSingleObject` + `ReadConsoleInputA` | Waits up to 250 ms for input, so the screen keeps updating (timer, WPM) even when idle |
| `freq` (256 DWORDs) | `freq[ascii]++` for every key |
| `vkFreq` (256 DWORDs) | Count per virtual key, used by the keyboard heatmap |
| `lastRing` (64 bytes) | Circular buffer of the last N keys; the index wraps with `AND 63` |
| `tsRing` (128 DWORDs) | Time of each recent key press, used for WPM |
| Vowel check | Converts letter to lowercase, compares with `"aeiou"` |
| `canvas` | 100 x 30 cells (character, foreground, background) drawn every frame |
| `FlushVT` | Turns the canvas into VT escape sequences (`ESC[38;2;r;g;b;48;2;r;g;bm`) and writes the frame with one `WriteConsoleW` |

To change the default N, edit 
View DD 32` in `KeyMonitor.asm` (8 to 64).

## Troubleshooting

- **`'ml' is not recognized`** â€“ you're not in the *x86 Native Tools Command Prompt*.
- **`cannot open file 'kernel32.lib'`** â€“ same reason; use the x86 Native Tools prompt.
- **Dashboard is cut off** â€“ make the console window at least 100 x 30, or maximise it.
- Arrow / function keys don't produce characters, so they are not counted (they're used as controls).

## Project layout

```
KeyPressMonitor/
├── KeyMonitor.asm     # the whole program
├── build.bat          # one-step build (x86 Native Tools prompt)
├── screenshots/       # images used in this README
├── .github/workflows/ # CI: builds the project on every push
├── CONTRIBUTING.md
└── LICENSE
```

## License

Released under the [MIT License](LICENSE).
