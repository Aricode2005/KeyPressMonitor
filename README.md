# KeyPressMonitor (MASM Assembly)

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
ml /c /coff KeyMonitor.asm
link /subsystem:console KeyMonitor.obj kernel32.lib
```

## 4. Run

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
