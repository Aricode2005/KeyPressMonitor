# KeyPressMonitor (MASM Assembly)

This repo has two programs:

| Program | What it is |
|---------|------------|
| `KeyDashboard.asm` | **Main project.** A full-screen live dashboard with all three requirements plus extra features |
| `KeyMonitor.asm` | The original simple version (prints a status line per key). Kept as a fallback |

Both use only `kernel32.lib` and build with the same `build.bat`.

## KeyDashboard

![Dashboard while typing](screenshots/dashboard.png)

**Required features**

1. Counts **vowels and consonants** (big cards at the top, plus a vowel/consonant mix bar)
2. **Frequency of every key** (A-Z histogram, top-5 table, and the full table in the report)
3. Shows the **last N characters** typed (circular buffer; the newest key is highlighted)

**Extra features**

| Feature | How it's done in MASM |
|---------|-----------------------|
| Flicker-free colour dashboard | Everything is drawn into a 100x30 `CHAR_INFO` array, then copied with one `WriteConsoleOutputA` call |
| Custom colour theme | `SetConsoleScreenBufferInfoEx` replaces the 16 console colours; the original colours are restored on exit |
| Big block-digit numbers | A 3x3 font made of CP437 block characters (`bigFont`) |
| A-Z letter histogram | Bars use full and half blocks for double vertical resolution; vowels green, consonants amber |
| Keyboard heatmap | QWERTY keys coloured cold to hot by how often each virtual key was pressed |
| Typing speed | Live WPM (keys in the last 5 s), peak WPM, average WPM and a session timer via `GetTickCount` |
| Top 5 keys | Selection over the 256-entry frequency table, with bars and percentages |
| More categories | Separate counters for digits, spaces, symbols and other keys (Enter, Tab, Backspace...) |
| Mouse buttons | `ReadConsoleInputA` mouse events: click Reset / Save / Pause / Quit, buttons highlight on hover |
| Adjustable N | Left/Right arrows or the mouse wheel change N from 8 to 64 |
| Pause | F3 stops counting (shown in the header and the button bar) |
| Save report | F2 writes `KeyReport.txt` with `CreateFileA` / `WriteFile`; the same report is printed on exit |

**Controls**

| Key | Action |
|-----|--------|
| F1 | Reset all counters |
| F2 | Save report to `KeyReport.txt` |
| F3 | Pause / resume counting |
| Left / Right, mouse wheel | Change N |
| ESC | Quit and print the final report |

The dashboard needs a console of at least 100 x 30 characters (the default Windows console is 120 x 30).
If the colours look wrong in Windows Terminal, run it in the classic console instead: `conhost KeyDashboard.exe`.

| Start | Paused, N = 24 |
|-------|----------------|
| ![Start](screenshots/start.png) | ![Paused](screenshots/paused.png) |

---

## KeyMonitor (simple version)

A simple 32-bit MASM program for Windows that watches key presses in real time and:

1. Counts how many **vowels** and **consonants** you type
2. Keeps a **frequency count** of every key you press
3. Shows the **last 10 characters** you typed

Press **ESC** to stop. You then get a final report with the frequency of each key.

It only uses `kernel32.lib`, so you **don't** need Irvine32 or the MASM32 SDK.

---

## 1. Install the tools (one time only)

1. Download **Visual Studio Community** (free): https://visualstudio.microsoft.com/
2. In the installer, tick **"Desktop development with C++"** and install.
   This gives you `ml.exe` (MASM) and `link.exe`.

## 2. Get the code

```bat
git clone https://github.com/Hrishikesh-coder/KeyPressMonitor.git
cd KeyPressMonitor
```

## 3. Build

1. Open the Start menu and search for **"x86 Native Tools Command Prompt for VS"**.
   > It must be **x86** (32-bit), not x64.
2. `cd` into the `KeyPressMonitor` folder.
3. Run:

```bat
build.bat
```

Or build by hand:

```bat
ml /c /coff KeyDashboard.asm
link /subsystem:console KeyDashboard.obj kernel32.lib
```

(Replace `KeyDashboard` with `KeyMonitor` for the simple version.)

## 4. Run

```bat
KeyDashboard.exe
```

or the simple version:

```bat
KeyMonitor.exe
```

## Sample output

```
===== Real-Time Key Press Monitor (MASM) =====
Start typing... Press ESC to stop.

Key: h  | Vowels: 0  | Consonants: 1  | Last 10: [         h]
Key: e  | Vowels: 1  | Consonants: 1  | Last 10: [        he]
Key: l  | Vowels: 1  | Consonants: 2  | Last 10: [       hel]
...

========== FINAL REPORT ==========
Total Vowels     : 1
Total Consonants : 2

Key Frequency:
  e      (ASCII 101)  ->  1
  h      (ASCII 104)  ->  1
  l      (ASCII 108)  ->  1
```

Non-printable keys (Enter, Tab, etc.) show as `.` in the "last 10" view and as `code` in the report.

## How it works (short)

| Part | What it does |
|------|--------------|
| `SetConsoleMode(hIn, 0)` | Raw input: each key is read instantly, no Enter needed |
| `ReadConsoleA` | Reads 1 key at a time |
| `freq` (256 DWORDs) | `freq[ascii]++` for every key |
| `lastBuf` (10 bytes) | Shifted left with `rep movsb`, new key added at end |
| Vowel check | Converts letter to lowercase, compares with `"aeiou"` |

To change how many last characters are shown, edit `N EQU 10` at the top of `KeyMonitor.asm`.

## Troubleshooting

- **`'ml' is not recognized`** – you're not in the *x86 Native Tools Command Prompt*.
- **`cannot open file 'kernel32.lib'`** – same reason; use the x86 Native Tools prompt.
- Arrow / function keys don't produce ASCII characters, so they are ignored.
