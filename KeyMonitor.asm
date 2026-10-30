; =============================================================
;  KeyMonitor.asm  -  Real-time Key Press Monitor with a live
;                     full-screen dashboard (MASM, 32-bit)
;
;  Required features:
;   1. Counts vowels and consonants typed
;   2. Keeps frequency of every key pressed (ASCII 0-255)
;   3. Shows the last N characters typed (buffered view)
;
;  Extra features:
;   4. Full-screen dashboard in 24-bit colour: drawn off-screen, then
;      sent as one WriteConsoleW call of VT escape sequences (no
;      flicker). Gradients, 1/8-step bars, rounded panels. Falls back
;      to 16 colours if the console has no VT support
;   5. Live A-Z letter histogram (vowels green, consonants amber)
;   6. Keyboard heatmap - QWERTY keys coloured by how often used
;   7. Typing speed: live WPM, peak WPM, average WPM, session timer
;   8. Top-5 keys, plus top-5 bigrams and trigrams (n-gram tracker)
;   9. Digit / space / symbol / word counters, longest word,
;      backspace correction rate
;  10. WPM history graph for the last 52 seconds
;  11. Mouse-clickable buttons, adjustable N, pause, save report,
;      autosave on exit
;  12. Key-press ripple on the heatmap and count-up card numbers
;  13. Typing test screen (F5): live WPM, accuracy, errors, personal best
;  14. HTML / CSV / JSON reports (F2), opened in the browser
;  15. Compare with the last session (saved in KeyStats.dat)
;  16. Ergonomics & Biomechanics screen (F6): left/right hand balance,
;      8-finger load bars, row distribution (number/top/home/bottom/space)
;  17. Rhythm & Cadence analytics: average inter-key latency (ms),
;      burst WPM, active vs. idle time, rhythm consistency %
;  18. Achievements, Streaks & XP Rank system: live streak counter,
;      best streak, XP level & rank badge, 6 unlockable achievements
;  19. Custom Themes (F7: Midnight, Cyberpunk, Matrix, Nord) and
;      Mechanical Key Sound synth toggle (F8 via kernel32 Beep)
;  20. Typing Test categories (Tab cycles Standard, Quotes, Code,
;      Numbers & Symbols)
;
;  Keys:  F1 reset   F2 save reports   F3 pause   F4 autosave
;         F5 typing test   F6 biomechanics   F7 theme   F8 sound
;         Tab test mode    Left/Right (or wheel) change N   ESC quit
;
;  Uses only kernel32.lib (comes with Visual Studio / Windows SDK).
; =============================================================

.386
.model flat, stdcall
option casemap:none

; ---------- Windows API prototypes ----------
GetStdHandle                  PROTO :DWORD
GetConsoleMode                PROTO :DWORD, :DWORD
SetConsoleMode                PROTO :DWORD, :DWORD
ReadConsoleInputA             PROTO :DWORD, :DWORD, :DWORD, :DWORD
GetNumberOfConsoleInputEvents PROTO :DWORD, :DWORD
WaitForSingleObject           PROTO :DWORD, :DWORD
WriteConsoleA                 PROTO :DWORD, :DWORD, :DWORD, :DWORD, :DWORD
WriteConsoleW                 PROTO :DWORD, :DWORD, :DWORD, :DWORD, :DWORD
WriteConsoleOutputW           PROTO :DWORD, :DWORD, :DWORD, :DWORD, :DWORD
GetEnvironmentVariableA       PROTO :DWORD, :DWORD, :DWORD
FillConsoleOutputCharacterA   PROTO :DWORD, :DWORD, :DWORD, :DWORD, :DWORD
FillConsoleOutputAttribute    PROTO :DWORD, :DWORD, :DWORD, :DWORD, :DWORD
SetConsoleCursorPosition      PROTO :DWORD, :DWORD
GetConsoleCursorInfo          PROTO :DWORD, :DWORD
SetConsoleCursorInfo          PROTO :DWORD, :DWORD
GetConsoleScreenBufferInfoEx  PROTO :DWORD, :DWORD
SetConsoleScreenBufferInfoEx  PROTO :DWORD, :DWORD
GetConsoleOutputCP            PROTO
SetConsoleOutputCP            PROTO :DWORD
SetConsoleTitleA              PROTO :DWORD
GetTickCount                  PROTO
CreateFileA                   PROTO :DWORD, :DWORD, :DWORD, :DWORD, :DWORD, :DWORD, :DWORD
WriteFile                     PROTO :DWORD, :DWORD, :DWORD, :DWORD, :DWORD
CloseHandle                   PROTO :DWORD
ExitProcess                   PROTO :DWORD
ReadFile                      PROTO :DWORD, :DWORD, :DWORD, :DWORD, :DWORD
CreateProcessA                PROTO :DWORD, :DWORD, :DWORD, :DWORD, :DWORD, :DWORD, :DWORD, :DWORD, :DWORD, :DWORD
GetLocalTime                  PROTO :DWORD
Beep                          PROTO :DWORD, :DWORD
includelib kernel32.lib

; ---------- procedures used before their definition ----------
Tween                         PROTO :DWORD, :DWORD
RippleSetup                   PROTO
RippleMix                     PROTO :DWORD, :DWORD, :DWORD
DrawCompare                   PROTO

STD_INPUT_HANDLE  EQU -10
STD_OUTPUT_HANDLE EQU -11
IN_MODE           EQU 98h         ; extended flags + mouse + window input (QuickEdit off)
KEY_EVENT         EQU 1
MOUSE_EVENT       EQU 2
MOUSE_WHEELED     EQU 4
DOUBLE_CLICK      EQU 2
VK_ESCAPE         EQU 1Bh
VK_LEFT           EQU 25h
VK_RIGHT          EQU 27h
VK_F1             EQU 70h
VK_F2             EQU 71h
VK_F3             EQU 72h
VK_F4             EQU 73h
VK_F5             EQU 74h
VK_F6             EQU 75h
VK_F7             EQU 76h
VK_F8             EQU 77h
VK_TAB            EQU 09h

SCR_W             EQU 100         ; dashboard size in character cells
SCR_H             EQU 30
NMAX              EQU 64          ; largest N (power of two -> wrap with AND)
NMIN              EQU 8
TS_SIZE           EQU 128         ; key timestamps kept for WPM
HIST_N            EQU 52          ; WPM history: one sample per second, last 52 s
HIST_SIZE         EQU 64          ; ring size (power of two)
WPM_WINDOW        EQU 5000        ; WPM measured over the last 5 seconds
MSG_TIME          EQU 3000        ; status message shown for 3 seconds
BTN_Y             EQU 28          ; row of the button bar
NBTN              EQU 8           ; number of buttons
NSENT             EQU 12          ; typing test sentences (4 modes x 3)
NMODES            EQU 4           ; typing test modes
NTHEMES           EQU 4           ; colour themes
NBADGES           EQU 6           ; unlockable achievements
RIPPLE_MS         EQU 600         ; heatmap ripple length
RIPPLE_STEP       EQU 70          ; ms for the ripple to move one key further
STAT_N            EQU 12          ; DWORDs in KeyStats.dat
STAT_MAGIC        EQU 314D504Bh   ; "KPM1"
ST_TOTAL          EQU 1           ; KeyStats.dat fields (DWORD index)
ST_VOW            EQU 2
ST_CON            EQU 3
ST_WORDS          EQU 4
ST_PEAK           EQU 5
ST_AVG            EQU 6
ST_TIME           EQU 7
ST_BS             EQU 8
ST_BEST           EQU 9           ; best peak WPM of all sessions
ST_TBEST          EQU 10          ; best typing test WPM of all sessions
ST_SESS           EQU 11          ; number of sessions
NG2               EQU 26 * 26     ; possible bigrams (a-z)
NG3               EQU 26 * 26 * 26 ; possible trigrams

CAT_VOWEL         EQU 1
CAT_CONS          EQU 2
CAT_DIGIT         EQU 3
CAT_SPACE         EQU 4
CAT_SYM           EQU 5
CAT_OTHER         EQU 6

VT_OUTPUT         EQU 4           ; ENABLE_VIRTUAL_TERMINAL_PROCESSING
CARD_SIZE         EQU 16          ; per-second samples for the card sparklines
CARD_MASK         EQU CARD_SIZE - 1
A_PAGE            EQU 07h         ; console attribute used to clear the window

; ---------- colours (COLORREF = 00BBGGRRh) ----------
C_KEEP      EQU 0FFFFFFFFh ; leave the cell's colour unchanged
; theme-aware surface colours (updated by ApplyTheme in .data)
C_TEXT      EQU 0F0E8E2h  ; #E2E8F0
C_MUTED     EQU 08B7464h  ; #64748B
C_DIM       EQU 066453Bh  ; #3B4566
C_WHITE     EQU 0FFFFFFh  ; #FFFFFF
C_BLACK     EQU 0000000h  ; #000000
C_GREEN     EQU 0B7E76Eh  ; #6EE7B7
C_GREEN2    EQU 0699605h  ; #059669
C_AMBER     EQU 04DD3FCh  ; #FCD34D
C_AMBER2    EQU 00C58EAh  ; #EA580C
C_CYAN      EQU 0F9E867h  ; #67E8F9
C_CYAN2     EQU 0B29108h  ; #0891B2
C_PURP      EQU 0FDB5C4h  ; #C4B5FD
C_PURP2     EQU 0ED3A7Ch  ; #7C3AED
C_PINK      EQU 0B672F4h  ; #F472B6
C_OK        EQU 080DE4Ah  ; #4ADE80
C_GOLD      EQU 015CCFAh  ; #FACC15
C_BRONZE    EQU 03C92FBh  ; #FB923C
C_RED       EQU 0481DE1h  ; #E11D48
C_BLUE      EQU 0EB6325h  ; #2563EB
C_PAUSEBTN  EQU 0048ACAh  ; #CA8A04
; header gradient colours (updated by ApplyTheme in .data)
C_HDRTXT    EQU 0FED2C7h  ; #C7D2FE

.data
C_PAGE       DD 01A0E0Bh          ; active theme surface colours
C_PANEL      DD 0291712h
C_BORDER     DD 052332Ah
C_TRACK      DD 038221Ch
C_AXIS       DD 0452A23h
C_OFFKEY     DD 040261Fh
C_HDR1       DD 04B1B1Eh
C_HDR2       DD 0B6215Bh
themeIdx     DD 0                 ; 0=Midnight, 1=Cyberpunk, 2=Matrix, 3=Nord
soundOn      DD 0                 ; F8: mechanical key sound synth (Beep)

; 4 themes x 8 colours: PAGE, PANEL, BORDER, TRACK, AXIS, OFFKEY, HDR1, HDR2
themeTable   DD 01A0E0Bh, 0291712h, 052332Ah, 038221Ch, 0452A23h, 040261Fh, 04B1B1Eh, 0B6215Bh ; Midnight
             DD 01A0614h, 02E0B24h, 07A1C5Ch, 03D1030h, 0561644h, 04A123Bh, 06B0F4Ch, 0B000FFh ; Cyberpunk
             DD 0081408h, 00D220Dh, 01E4D1Eh, 0122E12h, 0173B17h, 0143314h, 00F380Fh, 01E7A1Eh ; Matrix
             DD 040342Eh, 052423Bh, 06A564Ch, 0493B34h, 05E4C43h, 056463Eh, 0755E4Ch, 0A1815Eh ; Nord

hIn          DD ?
hOut         DD ?
oldInMode    DD 0
oldCP        DD 0
curOld       DD 0, 0              ; CONSOLE_CURSOR_INFO
curNew       DD 0, 0
havePalette  DD 0
bufW         DD SCR_W
bufH         DD SCR_H
offX         DD 0                 ; dashboard is centred horizontally
writeRegion  DW 0, 0, 0, 0        ; SMALL_RECT
oldOutMode   DD 0
vtOK         DD 0                 ; console understands VT escape sequences
fineGlyphs   DD 0                 ; font has 1/8 blocks (Windows Terminal)
vtLen        DD 0                 ; characters in vtBuf

; ---- statistics ----
vowels       DD 0
consonants   DD 0
digits       DD 0
spaces       DD 0
symbols      DD 0
others       DD 0
totalKeys    DD 0
words        DD 0                 ; words typed (runs of letters/digits)
inWord       DD 0
curCat       DD 0
curWordLen   DD 0                 ; length of the word being typed
longestWord  DD 0                 ; longest word this session
bsCount      DD 0                 ; Backspace presses (typing corrections)
autoSave     DD 0                 ; F4: save the report automatically on exit
wpmHist      DD HIST_SIZE DUP(0)  ; WPM sampled once per second
histHead     DD 0
histCount    DD 0
lastSample   DD 0
cardV        DD CARD_SIZE DUP(0)  ; vowels / consonants / total, once per second
cardC        DD CARD_SIZE DUP(0)
cardT        DD CARD_SIZE DUP(0)
cardHead     DD 0
cardCount    DD 0
freq         DD 256 DUP(0)        ; frequency table, indexed by ASCII code
vkFreq       DD 256 DUP(0)        ; frequency by virtual key (for the heatmap)
lastRing     DB NMAX DUP(0)       ; last N characters, circular buffer
lastHead     DD 0
lastCount    DD 0
nView        DD 32                ; current N
tsRing       DD TS_SIZE DUP(0)    ; tick count of recent key presses
tsHead       DD 0
tsCount      DD 0
lastLetter   DD -1                ; 0-25, highlighted in the histogram
lastKeyCode  DD -1

startTick    DD 0
nowTick      DD 0
elapsedMs    DD 0
elapsedSec   DD 0
wpmNow       DD 0
wpmPeak      DD 0
wpmAvg       DD 0
heatMax      DD 1
top5Key      DD 5 DUP(0)
top5Cnt      DD 5 DUP(0)
top5N        DD 0
bi5Idx       DD 5 DUP(0)          ; top bigrams: index = a*26 + b
bi5Cnt       DD 5 DUP(0)
bi5N         DD 0
tri5Idx      DD 5 DUP(0)          ; top trigrams: index = (a*26 + b)*26 + c
tri5Cnt      DD 5 DUP(0)
tri5N        DD 0
prevL1       DD -1                ; previous letter (0-25), -1 = none
prevL2       DD -1                ; letter before that

viewMode     DD 0                 ; 0 = dashboard, 1 = typing test, 2 = ergonomics & achievements
; ---- ergonomics & biomechanics ----
leftHand     DD 0                 ; keys pressed with left hand
rightHand    DD 0                 ; keys pressed with right hand
fingerCnt    DD 9 DUP(0)          ; 0..3 left pinky..index, 4..7 right index..pinky, 8 thumbs
rowCnt       DD 5 DUP(0)          ; 0=number, 1=top(QWERTY), 2=home(ASDF), 3=bottom(ZXCV), 4=space/other
handAlt      DD 0                 ; hand alternations
lastHand     DD -1                ; 0=left, 1=right

; ---- rhythm & cadence analytics ----
lastKeyTick  DD 0                 ; tick of previous key press
latSum       DD 0                 ; sum of inter-key latencies (< 2000 ms)
latCnt       DD 0                 ; count of inter-key latencies
avgLatMs     DD 0                 ; average inter-key latency in ms
minLatMs     DD 0                 ; fastest inter-key transition (ms)
burstWpm     DD 0                 ; fastest 5-key burst WPM
activeMs     DD 0                 ; active typing time (sum of intervals < 2000 ms)
rhythmScore  DD 100               ; consistency score (0-100%)

; ---- streaks, XP & achievements ----
curStreak    DD 0                 ; keys since last Backspace/mistake
bestStreak   DD 0                 ; best error-free key streak
xpScore      DD 0                 ; total XP earned this session
xpLevel      DD 1                 ; current level (1 + xpScore / 250)
badgesMask   DD 0                 ; bitmask of unlocked achievements (0..5)
badgeCount   DD 0                 ; number of unlocked badges (0..6)
testMode     DD 0                 ; 0=Standard, 1=Quotes, 2=Code, 3=Numbers/Symbols
frameWait    DD 250               ; ms to wait for input (30 while animating)
animating    DD 0
rippleVk     DD -1                ; last key pressed, for the heatmap ripple
rippleTick   DD 0
rippleOn     DD 0
rippleX      DD 0
rippleY      DD 0
rippleAge    DD 0
dispV        DD 0                 ; card numbers as shown (count up to the real value)
dispC        DD 0
dispT        DD 0

; ---- typing test ----
testIdx      DD NSENT - 1         ; sentence index (NewTest moves to the next)
testPtr      DD 0
testLen      DD 0
testPos      DD 0                 ; characters typed
testKeys     DD 0                 ; keys typed (not counting Backspace)
testErrors   DD 0                 ; wrong keys, even if fixed later
testStart    DD 0
testEnd      DD 0
testDone     DD 0
testNewBest  DD 0
testBest     DD 0                 ; best WPM this session
tWpm         DD 0                 ; live numbers from TestLive
tAcc         DD 0
tSec         DD 0
testTyped    DB 128 DUP(0)

; ---- last session (KeyStats.dat) ----
hasLast      DD 0
bestPeakAll  DD 0
bestTestAll  DD 0
lastStats    DD STAT_N DUP(0)
statBuf      DD STAT_N DUP(0)
sysTime      DW 8 DUP(0)          ; SYSTEMTIME for the report date
appBase      DD OFFSET rptBuf     ; buffer the App* builders write to
startInfo    DD 68, 16 DUP(0)     ; STARTUPINFOA (cb = 68)
procInfo     DD 4 DUP(0)          ; PROCESS_INFORMATION

paused       DD 0
quitFlag     DD 0
mouseX       DD -1
mouseY       DD -1
btnX         DD NBTN DUP(0)
btnW         DD NBTN DUP(0)
msgPtr       DD 0
msgTick      DD 0
msgColor     DD 0

nEvents      DD 0
nRead        DD 0
nWritten     DD 0
inRec        DB 20 DUP(0)         ; INPUT_RECORD
numBuf       DB 16 DUP(0)
keyNameBuf   DB 4 DUP(0)
ngBuf        DB 4 DUP(0)
rptLen       DD 0
envBuf       DB 64 DUP(0)

; ---- colours: heatmap ramp, 16-colour fallback palette, rank medals ----
heatStops    DD 0D84E1Dh, 0D4B606h, 081B910h, 015CCFAh, 01673F9h, 0481DE1h   ; cold -> hot
palette      DD 01A0E0Bh, 0291712h, 099D334h, 0EED322h, 0481DE1h, 0FA8BA7h, 00B9EF5h, 0F0E8E2h
             DD 08B7464h, 0EB6325h, 0699605h, 08C1F3Bh, 066443Ah, 0B672F4h, 015CCFAh, 0FFFFFFh   ; 12 = border grey
; ---- CP437 bytes 80h-FFh -> Unicode (used to draw byte strings) ----
cp437W       DW 000C7h, 000FCh, 000E9h, 000E2h, 000E4h, 000E0h, 000E5h, 000E7h
             DW 000EAh, 000EBh, 000E8h, 000EFh, 000EEh, 000ECh, 000C4h, 000C5h
             DW 000C9h, 000E6h, 000C6h, 000F4h, 000F6h, 000F2h, 000FBh, 000F9h
             DW 000FFh, 000D6h, 000DCh, 000A2h, 000A3h, 000A5h, 020A7h, 00192h
             DW 000E1h, 000EDh, 000F3h, 000FAh, 000F1h, 000D1h, 000AAh, 000BAh
             DW 000BFh, 02310h, 000ACh, 000BDh, 000BCh, 000A1h, 000ABh, 000BBh
             DW 02591h, 02592h, 02593h, 02502h, 02524h, 02561h, 02562h, 02556h
             DW 02555h, 02563h, 02551h, 02557h, 0255Dh, 0255Ch, 0255Bh, 02510h
             DW 02514h, 02534h, 0252Ch, 0251Ch, 02500h, 0253Ch, 0255Eh, 0255Fh
             DW 0255Ah, 02554h, 02569h, 02566h, 02560h, 02550h, 0256Ch, 02567h
             DW 02568h, 02564h, 02565h, 02559h, 02558h, 02552h, 02553h, 0256Bh
             DW 0256Ah, 02518h, 0250Ch, 02588h, 02584h, 0258Ch, 02590h, 02580h
             DW 003B1h, 000DFh, 00393h, 003C0h, 003A3h, 003C3h, 000B5h, 003C4h
             DW 003A6h, 00398h, 003A9h, 003B4h, 0221Eh, 003C6h, 003B5h, 02229h
             DW 02261h, 000B1h, 02265h, 02264h, 02320h, 02321h, 000F7h, 02248h
             DW 000B0h, 02219h, 000B7h, 0221Ah, 0207Fh, 000B2h, 025A0h, 000A0h

rankColors   DD C_GOLD, C_TEXT, C_BRONZE, C_MUTED, C_MUTED   ; gold, silver, bronze

; ---- 3x3 block font for the big numbers (CP437 blocks) ----
bigFont      DB 0DBh,0DFh,0DBh, 0DBh,020h,0DBh, 0DFh,0DFh,0DFh   ; 0
             DB 0DFh,0DBh,020h, 020h,0DBh,020h, 0DFh,0DFh,0DFh   ; 1
             DB 0DFh,0DFh,0DBh, 0DBh,0DFh,0DFh, 0DFh,0DFh,0DFh   ; 2
             DB 0DFh,0DFh,0DBh, 020h,0DFh,0DBh, 0DFh,0DFh,0DFh   ; 3
             DB 0DBh,020h,0DBh, 0DFh,0DFh,0DBh, 020h,020h,0DFh   ; 4
             DB 0DBh,0DFh,0DFh, 0DFh,0DFh,0DBh, 0DFh,0DFh,0DFh   ; 5
             DB 0DBh,0DFh,0DFh, 0DBh,0DFh,0DBh, 0DFh,0DFh,0DFh   ; 6
             DB 0DFh,0DFh,0DBh, 020h,020h,0DBh, 020h,020h,0DFh   ; 7
             DB 0DBh,0DFh,0DBh, 0DBh,0DFh,0DBh, 0DFh,0DFh,0DFh   ; 8
             DB 0DBh,0DFh,0DBh, 0DFh,0DFh,0DBh, 0DFh,0DFh,0DFh   ; 9

; ---- keyboard layout: labels, virtual key codes, x, y ----
kbL0         DB "1234567890-=", 0
kbV0         DB "1234567890", 0BDh, 0BBh
kbL1         DB "QWERTYUIOP[]", 0
kbV1         DB "QWERTYUIOP", 0DBh, 0DDh
kbL2         DB "ASDFGHJKL;'", 0
kbV2         DB "ASDFGHJKL", 0BAh, 0DEh
kbL3         DB "ZXCVBNM,./", 0
kbV3         DB "ZXCVBNM", 0BCh, 0BEh, 0BFh
kbRows       DD OFFSET kbL0, OFFSET kbV0, 60, 13
             DD OFFSET kbL1, OFFSET kbV1, 61, 14
             DD OFFSET kbL2, OFFSET kbV2, 62, 15
             DD OFFSET kbL3, OFFSET kbV3, 63, 16

; ---- text ----
vowelList    DB "aeiou", 0
sWinTitle    DB "Key Press Monitor - MASM dashboard", 0
sTitle       DB "KEY PRESS MONITOR", 0
sSubtitle    DB "MASM x86  ", 0FAh, "  real-time keystroke analytics", 0
sLive        DB "LIVE", 0
sPaused      DB "PAUSED", 0
sTime        DB "TIME ", 0
sCardV       DB " VOWELS ", 0
sCardC       DB " CONSONANTS ", 0
sCardT       DB " TOTAL KEYS ", 0
sCardW       DB " SPEED ", 0FAh, " WPM ", 0
sPctLetters  DB "% of letters", 0
sKeysSession DB "keys this session", 0
sPeak        DB "peak ", 0
sAvg         DB "   avg ", 0
sDigits      DB "DIGITS ", 0
sSpaces      DB "SPACES ", 0
sSymbols     DB "SYMBOLS ", 0
sOther       DB "OTHER ", 0
sWords       DB "WORDS ", 0
sLongest     DB "LONGEST WORD ", 0
sBackspaces  DB "   BACKSPACES ", 0
sErrRate     DB "   CORRECTION RATE ", 0
sMsgAutoOn   DB 0FBh, " Report will be saved on exit", 0
sMsgAutoOff  DB "x Autosave off", 0
sBoxLast     DB " LAST N CHARACTERS ", 0
sNEq         DB " N = ", 0
sNHint       DB "  (<- ->  or mouse wheel) ", 0
sLastKey     DB "LAST KEY ", 0
sAscii       DB "  ASCII ", 0
sBoxHist     DB " LETTER FREQUENCY  A-Z ", 0
sVowel       DB "vowel", 0
sConsonant   DB "consonant", 0
sMax         DB "max ", 0
sMaxB        DB " max ", 0           ; on a box border
sBoxHeat     DB " KEYBOARD HEATMAP ", 0
sSpace       DB "SPACE", 0
sCold        DB " cold ", 0
sHot         DB " hot ", 0
sBoxRank     DB " TOP 5 ", 0
sHdrKey      DB "KEY", 0
sHdrBi       DB "BIGRAM", 0
sHdrTri      DB "TRIGRAM", 0
sBoxWpm      DB " WPM HISTORY  last 52 s ", 0
sDash        DB "-", 0
; buttons in screen order: key, name, colour; btnAction maps each to a DoAction id
sBK0         DB " F1 ", 0
sBK1         DB " F2 ", 0
sBK2         DB " F3 ", 0
sBK3         DB " F4 ", 0
sBK4         DB " ESC ", 0
sBK5         DB " F5 ", 0
sBK6         DB " F6 ", 0
sBK7         DB " F7 ", 0
sBN0         DB " Reset ", 0
sBN1         DB " Export ", 0
sBN2         DB " Pause ", 0
sBN2R        DB " Resume ", 0
sBN3         DB " Auto:Off ", 0
sBN3On       DB " Auto:On ", 0
sBN4         DB " Quit ", 0
sBN5         DB " Test ", 0
sBN5B        DB " Dash ", 0
sBN6         DB " Bio/XP ", 0
sBN7         DB " Theme ", 0
btnKeys      DD OFFSET sBK0, OFFSET sBK1, OFFSET sBK2, OFFSET sBK3, OFFSET sBK5, OFFSET sBK6, OFFSET sBK7, OFFSET sBK4
btnNames     DD OFFSET sBN0, OFFSET sBN1, OFFSET sBN2, OFFSET sBN3, OFFSET sBN5, OFFSET sBN6, OFFSET sBN7, OFFSET sBN4
btnColors    DD C_BLUE, C_BLUE, C_BLUE, C_BLUE, C_PURP2, C_CYAN2, C_GREEN2, C_RED
btnAction    DB 0, 1, 2, 4, 5, 6, 7, 3
sHint        DB "Click buttons ", 0FAh, " <-/->: N ", 0FAh
             DB " F5: Test  F6: Bio/XP  F7: Theme  F8: Sound  Tab: Mode", 0
sMsgReset    DB 0FBh, " Counters reset", 0
sMsgSaved    DB 0FBh, " Exported TXT, HTML, CSV and JSON reports", 0
sMsgErgo     DB 0FBh, " Biomechanics, Rhythm & Achievements (F6 = dashboard)", 0
sMsgTheme0   DB 0FBh, " Theme: Midnight", 0
sMsgTheme1   DB 0FBh, " Theme: Cyberpunk Neon", 0
sMsgTheme2   DB 0FBh, " Theme: Matrix Hacker", 0
sMsgTheme3   DB 0FBh, " Theme: Nord Frost", 0
themeMsgs    DD OFFSET sMsgTheme0, OFFSET sMsgTheme1, OFFSET sMsgTheme2, OFFSET sMsgTheme3
sMsgSndOn    DB 0FBh, " Mechanical key sound ON (F8)", 0
sMsgSndOff   DB "x Mechanical key sound OFF (F8)", 0
sCsvFile     DB "KeyReport.csv", 0
sJsonFile    DB "KeyReport.json", 0
sMsgFail     DB "x Could not write the report files", 0
sMsgTest     DB 0FBh, " Typing test - start typing (F5 = back)", 0
sMsgDash     DB 0FBh, " Dashboard", 0
sMsgWelcome  DB 0FBh, " Welcome back - last session loaded (see VS LAST)", 0
sMsgPause    DB "|| Paused - typing is not counted", 0
sMsgResume   DB 0FBh, " Live again", 0
sReportFile  DB "KeyReport.txt", 0
sHtmlFile    DB "KeyReport.html", 0
sStatsFile   DB "KeyStats.dat", 0
sNoBrowser   DB "KPM_NO_BROWSER", 0          ; set it to stop F2 opening the browser
sOpenCmd     DB 'cmd.exe /c start "" "KeyReport.html"', 0
sSPC         DB "SPC", 0
sENT         DB "ENT", 0
sTAB         DB "TAB", 0
sBSP         DB "BSP", 0
sEXT         DB "EXT", 0
sWtEnv       DB "WT_SESSION", 0        ; set when running inside Windows Terminal

; ---- VT escape sequences ----
vtCsi        DB 27, "[", 0
vtFg         DB "38;2;", 0
vtBg         DB ";48;2;", 0
vtFrame      DB 27, "[?2026h", 27, "[?25l", 0     ; begin synchronised frame, hide cursor
vtFrameEnd   DB 27, "[?2026l", 0
vtClear      DB 27, "[48;2;11;14;26m", 27, "[2J", 0 ; fill the window with the page colour
vtReset      DB 27, "[0m", 27, "[2J", 27, "[H", 27, "[?25h", 0

; ---- typing test sentences (4 modes x 3 sentences = 12) ----
sent0        DB "the quick brown fox jumps over the lazy dog", 0
sent1        DB "pack my box with five dozen liquor jugs", 0
sent2        DB "sphinx of black quartz, judge my vow", 0
sent3        DB "assembly language gives you full control of the machine", 0
sent4        DB "every keystroke is counted, classified and drawn in real time", 0
sent5        DB "simplicity is prerequisite for reliability in software design", 0
sent6        DB "mov eax, [ebx+ecx*4] ; invoke WriteConsoleW, hOut, pBuf, n", 0
sent7        DB "for (int i = 0; i < n; ++i) { freq[str[i]]++; total += 1; }", 0
sent8        DB "const wpm = Math.round((chars / 5) / (elapsedMs / 60000));", 0
sent9        DB "192.168.1.254:8080 #42 = 100% - $39.95 + (2026 / 4) * 7!", 0
sent10       DB "0xFF00AA55 -> [256 * 4] = 1024 bytes @ 60fps (33.3ms/frame)", 0
sent11       DB "key #1: 98.6%, key #2: 450ms, total = 1,234,567 (0x12D687)", 0
sentences    DD OFFSET sent0, OFFSET sent1, OFFSET sent2, OFFSET sent3, OFFSET sent4, OFFSET sent5
             DD OFFSET sent6, OFFSET sent7, OFFSET sent8, OFFSET sent9, OFFSET sent10, OFFSET sent11
sMode0       DB "STANDARD", 0
sMode1       DB "QUOTES", 0
sMode2       DB "CODE", 0
sMode3       DB "NUMBERS", 0
modeNames    DD OFFSET sMode0, OFFSET sMode1, OFFSET sMode2, OFFSET sMode3
sCardTW      DB " SPEED ", 0FAh, " WPM ", 0
sCardAcc     DB " ACCURACY % ", 0
sCardErr     DB " ERRORS ", 0
sCardTime    DB " TIME  s ", 0
sBestSess    DB "best ", 0
sAllTime     DB "  all-time ", 0
sPctCorrect  DB "keys typed right", 0
sErrSub      DB "wrong keys typed", 0
sSecSub      DB "seconds", 0
sBoxTest     DB " TYPING TEST  ", 0FAh, "  type this sentence ", 0
sSentence    DB " sentence ", 0
sOfSix       DB " of 6 ", 0
sBoxResult   DB " RESULT ", 0
sHow1        DB "Type the sentence above. The timer starts with your first key.", 0
sHow2        DB "Green = correct   Red = mistake   Backspace = fix it   Enter = next sentence", 0
sHow3        DB "Every key typed here also counts on the dashboard.   F5 = back to the dashboard.", 0
sGoing       DB "Keep going ", 0FAh, " ", 0
sChars       DB " characters", 0
sWpmWord     DB "WPM", 0
sResAcc      DB "ACCURACY   ", 0
sResErr      DB "ERRORS     ", 0
sResTime     DB "TIME       ", 0
sResBest     DB "BEST       ", 0
sResAll      DB "   ALL-TIME ", 0
sNewBest     DB " NEW PERSONAL BEST! ", 0
sAgain       DB "Enter = next sentence  ", 0FAh, "  Tab = change mode  ", 0FAh, "  F5 = dashboard", 0
sModeLbl     DB " MODE: ", 0
sTabHint     DB " (Tab) ", 0

; ---- ergonomics, rhythm & achievements strings ----
sHdrLvl      DB "LVL ", 0
sRank0       DB "NOVICE", 0
sRank1       DB "TYPIST", 0
sRank2       DB "PRO", 0
sRank3       DB "MASTER", 0
sRank4       DB "GRANDMASTER", 0
rankNames    DD OFFSET sRank0, OFFSET sRank1, OFFSET sRank2, OFFSET sRank3, OFFSET sRank4
sStreakSt    DB "  STREAK ", 0
sLatSt       DB "  LATENCY ", 0
sMsUnit      DB "ms", 0

sCardLH      DB " LEFT HAND % ", 0
sCardRH      DB " RIGHT HAND % ", 0
sCardLat     DB " AVG LATENCY ms ", 0
sCardStrk    DB " KEY STREAK ", 0
sSubKeys     DB "keys: ", 0
sSubAlt      DB "alt: ", 0
sSubMinLat   DB "min ", 0
sSubRhythm   DB "ms  rhythm ", 0
sSubBestSt   DB "best ", 0
sSubBadges   DB "  badges ", 0

sBoxFinger   DB " FINGER LOAD & HAND BALANCE ", 0
sBoxRows     DB " KEYBOARD ROW & RHYTHM ANALYTICS ", 0
sBoxBadges   DB " ACHIEVEMENTS, XP & RANK PROGRESS ", 0
sFnL4        DB "L-Pinky ", 0
sFnL3        DB "L-Ring  ", 0
sFnL2        DB "L-Middle", 0
sFnL1        DB "L-Index ", 0
sFnR1        DB "R-Index ", 0
sFnR2        DB "R-Middle", 0
sFnR3        DB "R-Ring  ", 0
sFnR4        DB "R-Pinky ", 0
sFnTh        DB "Thumbs  ", 0
fingerNames  DD OFFSET sFnL4, OFFSET sFnL3, OFFSET sFnL2, OFFSET sFnL1
             DD OFFSET sFnR1, OFFSET sFnR2, OFFSET sFnR3, OFFSET sFnR4, OFFSET sFnTh
sRowNum      DB "Number Row (1-0) ", 0
sRowTop      DB "Top Row (QWERTY) ", 0
sRowHome     DB "Home Row (ASDFG) ", 0
sRowBot      DB "Bottom Row (ZXCV)", 0
sRowSpc      DB "Space & Modifiers", 0
rowNames     DD OFFSET sRowNum, OFFSET sRowTop, OFFSET sRowHome, OFFSET sRowBot, OFFSET sRowSpc
sRhyActive   DB "Active Typing Time : ", 0
sRhyBurst    DB "Peak Burst Speed   : ", 0
sRhyCons     DB "Rhythm Consistency : ", 0
sRhyAlt      DB "Hand Alternations  : ", 0

sBdg0        DB "First Steps (50+ keys)", 0
sBdg1        DB "Speed Demon (60+ Peak WPM)", 0
sBdg2        DB "Hyper Velocity (100+ Peak WPM)", 0
sBdg3        DB "Flawless Streak (100+ streak)", 0
sBdg4        DB "Marathon Runner (500+ keys)", 0
sBdg5        DB "Polyglot Coder (20+ symbols/digits)", 0
badgeNames   DD OFFSET sBdg0, OFFSET sBdg1, OFFSET sBdg2, OFFSET sBdg3, OFFSET sBdg4, OFFSET sBdg5
sXpLbl       DB "XP ", 0
sUnlocked    DB "[UNLOCKED]", 0
sLocked      DB "[LOCKED]  ", 0

; letter 'a'..'z' -> finger index (0..3 = L pinky..index, 4..7 = R index..pinky)
letterFinger DB 0, 3, 2, 2, 2, 3, 3, 4, 5, 4, 5, 6, 4, 4, 6, 7, 0, 3, 1, 3, 4, 3, 1, 1, 4, 0
; letter 'a'..'z' -> row index (1 = top, 2 = home, 3 = bottom)
letterRow    DB 2, 3, 3, 2, 1, 2, 2, 2, 1, 2, 2, 2, 3, 3, 1, 1, 1, 1, 2, 1, 1, 3, 1, 3, 1, 3

; report & export extra strings
rpLeftH      DB "Left hand keys   : ", 0
rpRightH     DB "Right hand keys  : ", 0
rpAvgLat     DB "Avg latency (ms) : ", 0
rpBestStrk   DB "Best key streak  : ", 0
rpXpLvl      DB "XP Level         : ", 0
rpBadges     DB "Badges unlocked  : ", 0
csvHdr       DB "metric,value", 13, 10, 0
csvKeyHdr    DB 13, 10, "ascii,key,count", 13, 10, 0
jsOpen       DB "{", 13, 10, '  "totalKeys": ', 0
jsVow        DB ',', 13, 10, '  "vowels": ', 0
jsCon        DB ',', 13, 10, '  "consonants": ', 0
jsWds        DB ',', 13, 10, '  "words": ', 0
jsPeak       DB ',', 13, 10, '  "peakWpm": ', 0
jsAvg        DB ',', 13, 10, '  "avgWpm": ', 0
jsLat        DB ',', 13, 10, '  "avgLatencyMs": ', 0
jsStrk       DB ',', 13, 10, '  "bestStreak": ', 0
jsLH         DB ',', 13, 10, '  "leftHand": ', 0
jsRH         DB ',', 13, 10, '  "rightHand": ', 0
jsXP         DB ',', 13, 10, '  "xpScore": ', 0
jsBadges     DB ',', 13, 10, '  "badgesUnlocked": ', 0
jsClose      DB 13, 10, "}", 13, 10, 0

; ---- last-session comparison ----
sVsLast      DB "VS LAST  ", 0
sFirstRun    DB "first session - saved on exit", 0
sCmpAvg      DB "avg ", 0
sCmpPeak     DB "  peak ", 0
sCmpBest     DB "  best ", 0

; ---- HTML report pieces ----
hexDigits    DB "0123456789abcdef"
hEscLt       DB "&lt;", 0
hEscGt       DB "&gt;", 0
hEscAmp      DB "&amp;", 0
hEscQuot     DB "&quot;", 0
hHead        DB '<!doctype html><html lang="en"><head><meta charset="utf-8">', 13, 10
             DB '<meta name="viewport" content="width=device-width,initial-scale=1">', 13, 10
             DB '<title>Key Press Monitor - report</title><style>', 13, 10
             DB 'body{background:#0b0e1a;color:#e2e8f0;font:15px/1.5 "Segoe UI",system-ui,sans-serif;margin:0;padding:32px}', 13, 10
             DB '.wrap{max-width:1100px;margin:auto}h1{margin:0;font-size:28px;font-weight:600}', 13, 10
             DB '.sub{color:#64748b;margin:2px 0 22px}.lbl{color:#64748b;font-size:12px;letter-spacing:.08em;text-transform:uppercase}', 13, 10
             DB '.grid{display:grid;grid-template-columns:repeat(4,1fr);gap:14px;margin-bottom:14px}', 13, 10
             DB '.row{display:grid;grid-template-columns:1fr 1fr;gap:14px;margin-bottom:14px}', 13, 10
             DB '.card{background:#121729;border:1px solid #2a3352;border-radius:14px;padding:16px 18px}', 13, 10
             DB '.card b{display:block;font-size:34px;font-weight:600;line-height:1.2}', 13, 10
             DB '.bars{display:flex;align-items:flex-end;gap:5px;height:180px;margin-top:10px}', 13, 10
             DB '.bar{flex:1;display:flex;flex-direction:column;justify-content:flex-end;align-items:center;font-size:11px;color:#94a3b8}', 13, 10
             DB '.bar i{display:block;width:100%;border-radius:4px 4px 0 0;margin:3px 0}', 13, 10
             DB '.kb>div{display:flex;gap:5px;margin:6px 0}', 13, 10
             DB '.kb span{min-width:32px;height:32px;border-radius:7px;display:flex;align-items:center;justify-content:center;font-weight:600}', 13, 10
             DB 'table{width:100%;border-collapse:collapse;margin-top:8px}td,th{padding:5px 8px;text-align:left}', 13, 10
             DB 'th{color:#64748b;font-weight:500;font-size:12px}td.n{color:#94a3b8;text-align:right}', 13, 10
             DB '.up{color:#4ade80}.down{color:#f43f5e}.same{color:#64748b}', 13, 10
             DB '.freq{display:flex;flex-wrap:wrap;gap:6px;margin-top:10px}', 13, 10
             DB '.freq span{background:#1c2238;border-radius:6px;padding:2px 9px;font-family:Consolas,monospace}.freq b{display:inline;font-size:inherit;color:#67e8f9}', 13, 10
             DB 'footer{color:#64748b;margin-top:22px;font-size:12px}', 13, 10
             DB '@media(max-width:800px){.grid{grid-template-columns:1fr 1fr}.row{grid-template-columns:1fr}}', 13, 10
             DB '</style></head><body><div class="wrap"><h1>Key Press Monitor</h1><div class="sub">Session report &middot; ', 0
hDot         DB " &middot; ", 0
hSubEnd      DB ' of typing</div><div class="grid">', 13, 10, 0
hCard1       DB '<div class="card"><div class="lbl">', 0
hCard2       DB '</div><b style="color:', 0
hCard3       DB '">', 0
hCard4       DB '</b><div class="lbl">', 0
hCardEnd     DB '</div></div>', 13, 10, 0
hGridNext    DB '</div><div class="grid">', 13, 10, 0
hGridEnd     DB '</div>', 13, 10, 0
hlTotal      DB "Total keys", 0
hlKeysSess   DB "keys this session", 0
hlVowels     DB "Vowels", 0
hlPctLetters DB "% of letters", 0
hlCons       DB "Consonants", 0
hlAvg        DB "Average WPM", 0
hlPeak       DB "peak ", 0
hlPeakW      DB "Peak WPM", 0
hlWords      DB "Words", 0
hlLongest    DB "longest word ", 0
hlBs         DB "Backspaces", 0
hlCorr       DB "% correction rate", 0
hlSpaces     DB "Spaces", 0
hlDigits     DB "digits ", 0
hlSymbols    DB ", symbols ", 0
hlTest       DB "Typing test best WPM", 0
hlAllTime    DB "all-time best ", 0
hCmpHead     DB '<div class="card" style="margin-bottom:14px"><div class="lbl">Compared with the last session</div>'
             DB '<table><tr><th></th><th>This session</th><th>Last session</th><th>Change</th></tr>', 13, 10, 0
hCmpEnd      DB '</table></div>', 13, 10, 0
hTrTd        DB '<tr><td>', 0
hTdTd        DB '</td><td>', 0
hTdNum       DB '</td><td class="n">', 0
hTdTrEnd     DB '</td></tr>', 13, 10, 0
hTdUp        DB '</td><td class="up">&#9650; ', 0
hTdDown      DB '</td><td class="down">&#9660; ', 0
hTdSame      DB '</td><td class="same">=', 0
hBarsHead    DB '<div class="row"><div class="card"><div class="lbl">Letter frequency A-Z</div><div class="bars">', 13, 10, 0
hBar1        DB '<div class="bar">', 0
hBar2        DB '<i style="height:', 0
hBar3        DB 'px;background:', 0
hBar4        DB '"></i>', 0
hBar5        DB '</div>', 0
hKbHead      DB '</div></div><div class="card"><div class="lbl">Keyboard heatmap</div><div class="kb">', 13, 10, 0
hKbRow       DB '<div style="margin-left:', 0
hKbRow2      DB 'px">', 0
hKey1        DB '<span style="background:', 0
hKey2        DB ';color:', 0
hKey3        DB '">', 0
hKey4        DB '</span>', 0
hDivEnd      DB '</div>', 13, 10, 0
hSpace1      DB '<div style="margin-left:78px"><span style="width:220px;background:', 0
hSpace2      DB '">SPACE</span></div></div></div></div>', 13, 10, 0
hWpmHead     DB '<div class="row"><div class="card"><div class="lbl">WPM history, last 52 s</div>'
             DB '<svg viewBox="0 0 520 125" width="100%" style="margin-top:10px">'
             DB '<line x1="0" y1="120" x2="520" y2="120" stroke="#2a3352"/>', 13, 10, 0
hPoly1       DB '<polygon fill="#7c3aed" fill-opacity="0.3" points="', 0
hBase        DB ",120 ", 0
hBaseEnd     DB ',120"/>', 0
hPoly2       DB '<polyline fill="none" stroke="#c4b5fd" stroke-width="2.5" stroke-linejoin="round" points="', 0
hPolyEnd     DB '"/>', 0
hWpmEnd      DB '</svg></div>', 13, 10, 0
hTopHead     DB '<div class="card"><div class="lbl">Top 5</div><table><tr><th>#</th><th>Key</th><th></th>'
             DB '<th>Bigram</th><th></th><th>Trigram</th><th></th></tr>', 13, 10, 0
hTopEnd      DB '</table></div></div>', 13, 10, 0
hFreqHead    DB '<div class="card"><div class="lbl">Every key pressed</div><div class="freq">', 13, 10, 0
hFreq1       DB '<span>', 0
hFreq2       DB ' <b>', 0
hFreq3       DB '</b></span>', 0
hFoot        DB '</div></div><footer>Generated by KeyMonitor.asm &middot; MASM x86 &middot; kernel32 only</footer>'
             DB '</div></body></html>', 13, 10, 0

; ---- report text (saved with F2 and printed on exit) ----
rpTitle      DB 13, 10, "========== KEY PRESS MONITOR - REPORT ==========", 13, 10, 0
rpTotal      DB "Total keys       : ", 0
rpVow        DB "Total Vowels     : ", 0
rpCon        DB "Total Consonants : ", 0
rpDig        DB "Digits           : ", 0
rpSpc        DB "Spaces           : ", 0
rpSym        DB "Symbols          : ", 0
rpOth        DB "Other keys       : ", 0
rpWords      DB "Words typed      : ", 0
rpLong       DB "Longest word     : ", 0
rpBs         DB "Backspaces       : ", 0
rpErr        DB "Correction rate %: ", 0
rpPeak       DB "Peak WPM         : ", 0
rpAvg        DB "Average WPM      : ", 0
rpTest       DB "Typing test best : ", 0
rpLastAvg    DB "Last session avg : ", 0
rpLastPeak   DB "Last session peak: ", 0
rpTime       DB "Session time     : ", 0
rpLast       DB "Last N chars     : [", 0
rpLastEnd    DB "]", 13, 10, 0
rpTop        DB 13, 10, "Top 5 keys:", 13, 10, 0
rpBi         DB 13, 10, "Top 5 bigrams:", 13, 10, 0
rpTri        DB 13, 10, "Top 5 trigrams:", 13, 10, 0
rpFreq       DB 13, 10, "Key Frequency:", 13, 10, 0
rpIndent     DB "  ", 0
rpDot        DB ".  ", 0
rpAsciiTxt   DB "(ASCII ", 0
rpArrow      DB ")  ->  ", 0
rpTimes      DB " x ", 0
crlf         DB 13, 10, 0
sBye         DB 13, 10, "Press any key to exit...", 0

.data?
canvas       DD SCR_W * SCR_H * 3 DUP(?) ; cells: Unicode char, foreground, background
vtBuf        DW 131072 DUP(?)          ; one frame of VT output (UTF-16)
legacyBuf    DD SCR_W * SCR_H DUP(?)   ; CHAR_INFO cells for the 16-colour fallback
csbiOld      DB 96 DUP(?)              ; CONSOLE_SCREEN_BUFFER_INFOEX
csbiNew      DB 96 DUP(?)
rptBuf       DB 16384 DUP(?)
htmlBuf      DB 65536 DUP(?)          ; KeyReport.html
bigrams      DD NG2 DUP(?)            ; count of every letter pair
trigrams     DD NG3 DUP(?)            ; count of every letter triple

.code

; =============================================================
;  Canvas primitives - everything is drawn into 'canvas' first.
;  A cell is 3 DWORDs: Unicode character, foreground colour and
;  background colour (COLORREF 00BBGGRRh). C_KEEP leaves a colour
;  unchanged, so text can be drawn over a panel or gradient.
; =============================================================

; ---- put one character with colours (clipped to the canvas) ----
Cell PROC px:DWORD, py:DWORD, chv:DWORD, fg:DWORD, bg:DWORD
    mov  eax, px
    cmp  eax, SCR_W
    jae  ce_done
    mov  edx, py
    cmp  edx, SCR_H
    jae  ce_done
    imul edx, edx, SCR_W
    add  edx, eax
    lea  edx, [edx+edx*2]           ; 3 DWORDs per cell
    mov  eax, chv
    mov  canvas[edx*4], eax
    mov  eax, fg
    cmp  eax, C_KEEP
    je   ce_bg
    mov  canvas[edx*4+4], eax
ce_bg:
    mov  eax, bg
    cmp  eax, C_KEEP
    je   ce_done
    mov  canvas[edx*4+8], eax
ce_done:
    ret
Cell ENDP

; ---- CP437 byte (as used in our strings) -> Unicode character ----
GlyphW PROC b:DWORD
    mov  eax, b
    and  eax, 0FFh
    cmp  eax, 80h
    jb   gw_done
    movzx eax, cp437W[eax*2 - 100h]
gw_done:
    ret
GlyphW ENDP

; ---- fill a rectangle with one character / colours ----
Fill PROC USES ebx esi px:DWORD, py:DWORD, wd:DWORD, ht:DWORD, chv:DWORD, fg:DWORD, bg:DWORD
    xor  esi, esi
fi_row:
    cmp  esi, ht
    jae  fi_done
    xor  ebx, ebx
fi_col:
    cmp  ebx, wd
    jae  fi_next
    mov  eax, px
    add  eax, ebx
    mov  edx, py
    add  edx, esi
    invoke Cell, eax, edx, chv, fg, bg
    inc  ebx
    jmp  fi_col
fi_next:
    inc  esi
    jmp  fi_row
fi_done:
    ret
Fill ENDP

; ---- zero-terminated byte string; returns eax = x after the text ----
Text PROC USES ebx esi px:DWORD, py:DWORD, pStr:DWORD, fg:DWORD, bg:DWORD
    mov  esi, pStr
    mov  ebx, px
tx_loop:
    movzx eax, BYTE PTR [esi]
    test eax, eax
    jz   tx_done
    invoke GlyphW, eax
    invoke Cell, ebx, py, eax, fg, bg
    inc  esi
    inc  ebx
    jmp  tx_loop
tx_done:
    mov  eax, ebx
    ret
Text ENDP

; ---- length of zero-terminated string ----
StrLen PROC pStr:DWORD
    mov  edx, pStr
    xor  eax, eax
sl_loop:
    cmp  BYTE PTR [edx+eax], 0
    je   sl_done
    inc  eax
    jmp  sl_loop
sl_done:
    ret
StrLen ENDP

; ---- unsigned number -> decimal text; eax = pointer, ecx = length ----
NumToStr PROC USES ebx edi val:DWORD
    lea  edi, numBuf + 15
    mov  BYTE PTR [edi], 0
    mov  eax, val
    mov  ebx, 10
nts_loop:
    dec  edi
    xor  edx, edx
    div  ebx
    add  dl, '0'
    mov  [edi], dl
    test eax, eax
    jnz  nts_loop
    lea  ecx, numBuf + 15
    sub  ecx, edi
    mov  eax, edi
    ret
NumToStr ENDP

; ---- number, left aligned; returns eax = x after the text ----
Num PROC px:DWORD, py:DWORD, val:DWORD, fg:DWORD
    invoke NumToStr, val
    invoke Text, px, py, eax, fg, C_KEEP
    ret
Num ENDP

; ---- number, right aligned so its last digit is at column pxr ----
NumR PROC pxr:DWORD, py:DWORD, val:DWORD, fg:DWORD
    invoke NumToStr, val
    mov  edx, pxr
    sub  edx, ecx
    inc  edx
    invoke Text, edx, py, eax, fg, C_KEEP
    ret
NumR ENDP

; ---- two digits with leading zero (0-99) ----
Two PROC px:DWORD, py:DWORD, val:DWORD, fg:DWORD
    mov  eax, val
    xor  edx, edx
    mov  ecx, 10
    div  ecx
    push edx
    add  eax, '0'
    invoke Cell, px, py, eax, fg, C_KEEP
    pop  edx
    add  edx, '0'
    mov  eax, px
    inc  eax
    invoke Cell, eax, py, edx, fg, C_KEEP
    ret
Two ENDP

; ---- seconds as mm:ss ----
TimeMS PROC px:DWORD, py:DWORD, secs:DWORD, fg:DWORD
    mov  eax, secs
    xor  edx, edx
    mov  ecx, 60
    div  ecx
    cmp  eax, 99
    jbe  tm_ok
    mov  eax, 99
tm_ok:
    push edx
    invoke Two, px, py, eax, fg
    mov  eax, px
    add  eax, 2
    invoke Cell, eax, py, ':', fg, C_KEEP
    pop  edx
    mov  eax, px
    add  eax, 3
    invoke Two, eax, py, edx, fg
    ret
TimeMS ENDP

; ---- blend two colours: c1 + (c2 - c1) * t / tmax, per channel ----
Lerp PROC USES ebx esi edi c1:DWORD, c2:DWORD, t:DWORD, tmax:DWORD
    mov  eax, c1                    ; empty range -> first colour
    cmp  tmax, 0
    jle  lp_ret
    mov  eax, t                     ; clamp t to 0..tmax
    cmp  eax, tmax
    jle  lp_lo
    mov  eax, tmax
lp_lo:
    test eax, eax
    jns  lp_t
    xor  eax, eax
lp_t:
    mov  t, eax
    xor  edi, edi                   ; result
    xor  esi, esi                   ; channel shift: 0, 8, 16
lp_ch:
    mov  ecx, esi
    mov  eax, c1
    shr  eax, cl
    and  eax, 0FFh
    mov  ebx, c2
    shr  ebx, cl
    and  ebx, 0FFh
    sub  ebx, eax                   ; signed difference
    push eax
    mov  eax, ebx
    imul t
    idiv tmax
    pop  ebx
    add  eax, ebx
    and  eax, 0FFh
    mov  ecx, esi
    shl  eax, cl
    or   edi, eax
    add  esi, 8
    cmp  esi, 24
    jb   lp_ch
    mov  eax, edi
lp_ret:
    ret
Lerp ENDP

; ---- colour at position t/tmax along a list of colour stops ----
Ramp PROC USES ebx pStops:DWORD, nStops:DWORD, t:DWORD, tmax:DWORD
    mov  eax, nStops
    dec  eax
    mul  t                          ; segment position = t * (n-1)
    div  tmax                       ; eax = stop index, edx = remainder
    mov  ecx, nStops
    sub  ecx, 2
    cmp  eax, ecx
    jbe  rp_ok
    mov  eax, ecx                   ; t = tmax -> end of the last segment
    mov  edx, tmax
rp_ok:
    mov  ebx, pStops
    invoke Lerp, DWORD PTR [ebx+eax*4], DWORD PTR [ebx+eax*4+4], edx, tmax
    ret
Ramp ENDP

; ---- panel with a rounded border and a title in the top edge ----
RBox PROC USES ebx esi edi px:DWORD, py:DWORD, wd:DWORD, ht:DWORD, pTitle:DWORD, bc:DWORD, tc:DWORD
    invoke Fill, px, py, wd, ht, ' ', C_TEXT, C_PANEL
    mov  esi, px
    add  esi, wd
    dec  esi                        ; esi = right column
    mov  edi, py
    add  edi, ht
    dec  edi                        ; edi = bottom row
    mov  ebx, px
rb_h:
    cmp  ebx, esi
    ja   rb_v0
    invoke Cell, ebx, py, 2500h, bc, C_KEEP
    invoke Cell, ebx, edi, 2500h, bc, C_KEEP
    inc  ebx
    jmp  rb_h
rb_v0:
    mov  ebx, py
rb_v:
    cmp  ebx, edi
    ja   rb_c
    invoke Cell, px, ebx, 2502h, bc, C_KEEP
    invoke Cell, esi, ebx, 2502h, bc, C_KEEP
    inc  ebx
    jmp  rb_v
rb_c:
    invoke Cell, px, py, 256Dh, bc, C_KEEP      ; rounded corners
    invoke Cell, esi, py, 256Eh, bc, C_KEEP
    invoke Cell, px, edi, 2570h, bc, C_KEEP
    invoke Cell, esi, edi, 256Fh, bc, C_KEEP
    cmp  pTitle, 0
    je   rb_done
    mov  eax, px
    add  eax, 2
    invoke Text, eax, py, pTitle, tc, C_KEEP
rb_done:
    ret
RBox ENDP

; ---- big 3-row number; colour fades from c1 (top) to c2 (bottom) ----
BigNum PROC USES ebx esi edi px:DWORD, py:DWORD, val:DWORD, c1:DWORD, c2:DWORD
    LOCAL row:DWORD, col:DWORD, rc:DWORD
    invoke NumToStr, val
    mov  esi, eax
    mov  ebx, px
bn_digit:
    movzx eax, BYTE PTR [esi]
    test eax, eax
    jz   bn_done
    sub  eax, '0'
    imul edi, eax, 9
    add  edi, OFFSET bigFont
    mov  row, 0
bn_row:
    invoke Lerp, c1, c2, row, 2
    mov  rc, eax
    mov  col, 0
bn_col:
    movzx eax, BYTE PTR [edi]
    cmp  eax, ' '
    je   bn_skip
    invoke GlyphW, eax
    mov  ecx, ebx
    add  ecx, col
    mov  edx, py
    add  edx, row
    invoke Cell, ecx, edx, eax, rc, C_KEEP
bn_skip:
    inc  edi
    inc  col
    cmp  col, 3
    jb   bn_col
    inc  row
    cmp  row, 3
    jb   bn_row
    add  ebx, 4
    inc  esi
    jmp  bn_digit
bn_done:
    ret
BigNum ENDP

; ---- vertical bar cell: e = filled eighths (1-8) -> block character ----
Eighth PROC e:DWORD
    mov  eax, e
    cmp  eax, 8
    jb   eg_part
    mov  eax, 2588h                 ; full block
    ret
eg_part:
    add  eax, 2580h                 ; U+2581..U+2587 lower blocks
    ret
Eighth ENDP

; ---- sparkline of the newest wd samples of a ring buffer ----
Spark PROC USES ebx esi edi px:DWORD, py:DWORD, wd:DWORD, pRing:DWORD, rmask:DWORD, head:DWORD, cnt:DWORD, c1:DWORD, c2:DWORD
    LOCAL n:DWORD, mx:DWORD, last:DWORD
    mov  eax, cnt
    cmp  eax, wd
    jbe  sk_n
    mov  eax, wd
sk_n:
    mov  n, eax
    test eax, eax
    jz   sk_done
    dec  eax
    jnz  sk_last
    inc  eax
sk_last:
    mov  last, eax                  ; max(n-1, 1) for the colour fade
    mov  mx, 1
    mov  ebx, pRing
    xor  esi, esi
sk_max:
    cmp  esi, n
    jae  sk_draw
    mov  eax, head
    sub  eax, n
    add  eax, esi
    and  eax, rmask
    mov  eax, [ebx+eax*4]
    cmp  eax, mx
    jbe  sk_mnext
    mov  mx, eax
sk_mnext:
    inc  esi
    jmp  sk_max
sk_draw:
    xor  esi, esi
sk_loop:
    cmp  esi, n
    jae  sk_done
    mov  eax, head
    sub  eax, n
    add  eax, esi
    and  eax, rmask
    mov  eax, [ebx+eax*4]
    mov  edx, 7                     ; level 0-7
    mul  edx
    div  mx
    lea  edi, [eax+2581h]
    invoke Lerp, c2, c1, esi, last
    mov  ecx, px
    add  ecx, wd
    sub  ecx, n
    add  ecx, esi
    invoke Cell, ecx, py, edi, eax, C_KEEP
    inc  esi
    jmp  sk_loop
sk_done:
    ret
Spark ENDP

; =============================================================
;  Output: true colour through VT sequences, or the 16-colour
;  console as a fallback
; =============================================================

; ---- characters the classic console font does not have ----
FineGlyph PROC chv:DWORD
    mov  eax, chv
    cmp  fineGlyphs, 0
    jne  fg_done
    cmp  eax, 25C6h                 ; diamond -> square
    jne  fg_low
    mov  eax, 25A0h
    ret
fg_low:
    cmp  eax, 2581h                 ; lower 1/8 .. 7/8 blocks
    jb   fg_done
    cmp  eax, 2587h
    ja   fg_left
    cmp  eax, 2582h
    ja   fg_half
    mov  eax, '_'
    ret
fg_half:
    cmp  eax, 2585h
    ja   fg_full
    mov  eax, 2584h
    ret
fg_left:
    cmp  eax, 2589h                 ; left 7/8 .. 1/8 blocks
    jb   fg_done
    cmp  eax, 258Fh
    ja   fg_done
    cmp  eax, 258Ch
    je   fg_done
    jb   fg_full
    mov  eax, 258Ch
    ret
fg_full:
    mov  eax, 2588h
fg_done:
    ret
FineGlyph ENDP

; ---- append to the VT output buffer ----
EmitW PROC chv:DWORD
    mov  edx, vtLen
    mov  eax, chv
    mov  vtBuf[edx*2], ax
    inc  vtLen
    ret
EmitW ENDP

EmitA PROC USES esi pStr:DWORD
    mov  esi, pStr
ea_loop:
    movzx eax, BYTE PTR [esi]
    test eax, eax
    jz   ea_done
    invoke EmitW, eax
    inc  esi
    jmp  ea_loop
ea_done:
    ret
EmitA ENDP

EmitNum PROC val:DWORD
    invoke NumToStr, val
    invoke EmitA, eax
    ret
EmitNum ENDP

; ---- "r;g;b" of a colour ----
EmitRGB PROC USES ebx clr:DWORD
    mov  ebx, clr
    movzx eax, bl
    invoke EmitNum, eax
    invoke EmitW, ';'
    movzx eax, bh
    invoke EmitNum, eax
    invoke EmitW, ';'
    shr  ebx, 16
    movzx eax, bl
    invoke EmitNum, eax
    ret
EmitRGB ENDP

; ---- ESC[38;2;r;g;b;48;2;r;g;bm : set foreground and background ----
EmitSgr PROC fg:DWORD, bg:DWORD
    invoke EmitA, ADDR vtCsi
    invoke EmitA, ADDR vtFg
    invoke EmitRGB, fg
    invoke EmitA, ADDR vtBg
    invoke EmitRGB, bg
    invoke EmitW, 'm'
    ret
EmitSgr ENDP

; ---- whole frame as one WriteConsoleW call ----
FlushVT PROC USES ebx esi edi
    LOCAL row:DWORD, lastFg:DWORD, lastBg:DWORD
    mov  vtLen, 0
    invoke EmitA, ADDR vtFrame
    mov  row, 0
fv_row:
    cmp  row, SCR_H
    jae  fv_end
    invoke EmitA, ADDR vtCsi        ; move to the start of the row
    mov  eax, row
    inc  eax
    invoke EmitNum, eax
    invoke EmitW, ';'
    mov  eax, offX
    inc  eax
    invoke EmitNum, eax
    invoke EmitW, 'H'
    mov  lastFg, -2
    mov  lastBg, -2
    imul esi, row, SCR_W * 12
    add  esi, OFFSET canvas
    xor  ebx, ebx
fv_col:
    cmp  ebx, SCR_W
    jae  fv_next
    mov  eax, [esi+4]
    mov  edx, [esi+8]
    cmp  eax, lastFg                ; colours only when they change
    jne  fv_sgr
    cmp  edx, lastBg
    je   fv_ch
fv_sgr:
    mov  lastFg, eax
    mov  lastBg, edx
    invoke EmitSgr, eax, edx
fv_ch:
    invoke FineGlyph, DWORD PTR [esi]
    invoke EmitW, eax
    add  esi, 12
    inc  ebx
    jmp  fv_col
fv_next:
    inc  row
    jmp  fv_row
fv_end:
    invoke EmitA, ADDR vtFrameEnd
    invoke WriteConsoleW, hOut, ADDR vtBuf, vtLen, ADDR nWritten, 0
    ret
FlushVT ENDP

; ---- nearest of the 16 console colours (fallback output) ----
Nearest PROC USES ebx esi edi clr:DWORD
    LOCAL best:DWORD, bestD:DWORD
    mov  bestD, 7FFFFFFFh
    mov  best, 0
    xor  esi, esi
nr_loop:
    cmp  esi, 16
    jae  nr_done
    xor  edi, edi                   ; squared distance
    xor  ecx, ecx
nr_ch:
    mov  eax, clr
    shr  eax, cl
    and  eax, 0FFh
    mov  ebx, palette[esi*4]
    shr  ebx, cl
    and  ebx, 0FFh
    sub  eax, ebx
    imul eax, eax
    add  edi, eax
    add  ecx, 8
    cmp  ecx, 24
    jb   nr_ch
    cmp  edi, bestD
    jae  nr_next
    mov  bestD, edi
    mov  best, esi
nr_next:
    inc  esi
    jmp  nr_loop
nr_done:
    mov  eax, best
    ret
Nearest ENDP

FlushLegacy PROC USES ebx esi edi
    lea  esi, canvas
    lea  edi, legacyBuf
    xor  ebx, ebx
fl_loop:
    cmp  ebx, SCR_W * SCR_H
    jae  fl_write
    invoke Nearest, DWORD PTR [esi+8]
    shl  eax, 4
    push eax
    invoke Nearest, DWORD PTR [esi+4]
    pop  edx
    or   eax, edx
    shl  eax, 16                    ; attribute in the high word
    push eax
    invoke FineGlyph, DWORD PTR [esi]
    pop  edx
    and  eax, 0FFFFh
    or   eax, edx
    mov  [edi], eax
    add  esi, 12
    add  edi, 4
    inc  ebx
    jmp  fl_loop
fl_write:
    mov  eax, offX
    mov  writeRegion, ax
    mov  writeRegion+2, 0
    add  eax, SCR_W - 1
    mov  writeRegion+4, ax
    mov  writeRegion+6, SCR_H - 1
    invoke WriteConsoleOutputW, hOut, ADDR legacyBuf, (SCR_H SHL 16) OR SCR_W, 0, ADDR writeRegion
    ret
FlushLegacy ENDP

Flush PROC
    cmp  vtOK, 0
    je   fl_legacy
    invoke FlushVT
    ret
fl_legacy:
    invoke FlushLegacy
    ret
Flush ENDP

; =============================================================
;  Counting logic
; =============================================================

; ---- category of a character (CAT_xxx) ----
Classify PROC kc:DWORD
    mov  eax, kc
    cmp  eax, ' '
    je   cl_space
    cmp  eax, 33
    jb   cl_other
    cmp  eax, 126
    ja   cl_other
    cmp  eax, '0'
    jb   cl_sym
    cmp  eax, '9'
    jbe  cl_digit
    cmp  eax, 'A'
    jb   cl_sym
    cmp  eax, 'Z'
    jbe  cl_letter
    cmp  eax, 'a'
    jb   cl_sym
    cmp  eax, 'z'
    jbe  cl_letter
    jmp  cl_sym
cl_letter:
    or   al, 20h                  ; to lowercase
    lea  edx, vowelList
cl_scan:
    mov  cl, [edx]
    test cl, cl
    jz   cl_cons
    cmp  al, cl
    je   cl_vowel
    inc  edx
    jmp  cl_scan
cl_vowel:
    mov  eax, CAT_VOWEL
    ret
cl_cons:
    mov  eax, CAT_CONS
    ret
cl_digit:
    mov  eax, CAT_DIGIT
    ret
cl_space:
    mov  eax, CAT_SPACE
    ret
cl_sym:
    mov  eax, CAT_SYM
    ret
cl_other:
    mov  eax, CAT_OTHER
    ret
Classify ENDP

; ---- n-gram tracker: count letter pairs and triples inside words ----
TrackNgram PROC cat:DWORD, kc:DWORD
    mov  eax, cat
    cmp  eax, CAT_VOWEL
    je   tn_letter
    cmp  eax, CAT_CONS
    je   tn_letter
    mov  prevL1, -1                 ; anything else ends the word
    mov  prevL2, -1
    ret
tn_letter:
    mov  eax, kc
    or   eax, 20h
    sub  eax, 'a'                   ; eax = letter 0-25
    mov  ecx, prevL1
    cmp  ecx, -1
    je   tn_shift
    imul edx, ecx, 26               ; bigram index = prev*26 + cur
    add  edx, eax
    inc  bigrams[edx*4]
    mov  edx, prevL2
    cmp  edx, -1
    je   tn_shift
    imul edx, edx, 26               ; trigram index = (prev2*26 + prev)*26 + cur
    add  edx, ecx
    imul edx, edx, 26
    add  edx, eax
    inc  trigrams[edx*4]
tn_shift:
    mov  edx, prevL1
    mov  prevL2, edx
    mov  prevL1, eax
    ret
TrackNgram ENDP

; ---- apply colour theme (themeIdx 0..3) ----
ApplyTheme PROC USES esi edi
    mov  eax, themeIdx
    and  eax, 3
    shl  eax, 5                     ; 8 DWORDs (32 bytes) per theme
    lea  esi, themeTable[eax]
    lea  edi, C_PAGE
    mov  ecx, 8
    cld
    rep  movsd
    ret
ApplyTheme ENDP

; ---- evaluate unlockable achievements and XP level ----
UpdateBadges PROC USES ebx
    mov  eax, totalKeys
    imul eax, eax, 3
    mov  edx, words
    imul edx, edx, 10
    add  eax, edx
    mov  edx, bestStreak
    shl  edx, 1
    add  eax, edx
    mov  xpScore, eax
    xor  edx, edx
    mov  ecx, 250
    div  ecx
    inc  eax
    mov  xpLevel, eax

    xor  ebx, ebx                   ; badge bitmask
    xor  ecx, ecx                   ; unlocked count
    cmp  totalKeys, 50
    jb   ub_1
    or   ebx, 1
    inc  ecx
ub_1:
    cmp  wpmPeak, 60
    jb   ub_2
    or   ebx, 2
    inc  ecx
ub_2:
    cmp  wpmPeak, 100
    jb   ub_3
    or   ebx, 4
    inc  ecx
ub_3:
    cmp  bestStreak, 100
    jb   ub_4
    or   ebx, 8
    inc  ecx
ub_4:
    cmp  totalKeys, 500
    jb   ub_5
    or   ebx, 16
    inc  ecx
ub_5:
    mov  eax, digits
    add  eax, symbols
    cmp  eax, 20
    jb   ub_done
    or   ebx, 32
    inc  ecx
ub_done:
    mov  badgesMask, ebx
    mov  badgeCount, ecx
    ret
UpdateBadges ENDP

; ---- track hand, finger, row, latency and streak for a key press ----
TrackErgo PROC USES ebx esi kc:DWORD
    ; 1. Streak tracking
    mov  ebx, kc
    cmp  ebx, 8                     ; Backspace resets current streak
    jne  te_strk
    mov  curStreak, 0
    jmp  te_lat
te_strk:
    inc  curStreak
    mov  eax, curStreak
    cmp  eax, bestStreak
    jbe  te_lat
    mov  bestStreak, eax

te_lat:                             ; 2. Inter-key latency & active time
    invoke GetTickCount
    mov  esi, eax
    cmp  lastKeyTick, 0
    je   te_settick
    sub  eax, lastKeyTick
    cmp  eax, 2000                  ; ignore pauses >= 2 seconds
    jae  te_settick
    test eax, eax
    jz   te_settick
    add  activeMs, eax
    add  latSum, eax
    inc  latCnt
    mov  ecx, eax
    cmp  minLatMs, 0
    je   te_setmin
    cmp  ecx, minLatMs
    jae  te_avg
te_setmin:
    mov  minLatMs, ecx
te_avg:
    mov  eax, latSum
    xor  edx, edx
    div  latCnt
    mov  avgLatMs, eax
te_settick:
    mov  lastKeyTick, esi

    ; 3. Hand, Finger & Row classification
    mov  eax, ebx
    cmp  eax, ' '
    jne  te_notspc
    inc  fingerCnt[8*4]             ; thumb
    inc  rowCnt[4*4]                ; space row
    jmp  te_snd
te_notspc:
    cmp  eax, '0'
    jb   te_chklet
    cmp  eax, '9'
    ja   te_chklet
    inc  rowCnt[0*4]                ; number row
    cmp  eax, '5'
    ja   te_numr
    cmp  eax, '0'
    je   te_numr
    inc  leftHand
    inc  fingerCnt[2*4]
    mov  ecx, 0
    jmp  te_alt
te_numr:
    inc  rightHand
    inc  fingerCnt[5*4]
    mov  ecx, 1
    jmp  te_alt
te_chklet:
    mov  eax, ebx
    or   eax, 20h
    sub  eax, 'a'
    cmp  eax, 25
    ja   te_other
    movzx ecx, letterRow[eax]
    inc  rowCnt[ecx*4]
    movzx ecx, letterFinger[eax]
    inc  fingerCnt[ecx*4]
    cmp  ecx, 4
    jae  te_letr
    inc  leftHand
    mov  ecx, 0
    jmp  te_alt
te_letr:
    inc  rightHand
    mov  ecx, 1
te_alt:
    cmp  lastHand, -1
    je   te_sethand
    cmp  lastHand, ecx
    je   te_sethand
    inc  handAlt
te_sethand:
    mov  lastHand, ecx
    jmp  te_snd
te_other:
    inc  rowCnt[4*4]
    inc  rightHand
    inc  fingerCnt[7*4]

te_snd:                             ; 4. Optional mechanical key click sound
    cmp  soundOn, 0
    je   te_done
    mov  eax, ebx
    and  eax, 1Fh
    shl  eax, 4
    add  eax, 600
    invoke Beep, eax, 8
te_done:
    ret
TrackErgo ENDP

; ---- count one typed character (kc = ASCII, vk = virtual key) ----
CountChar PROC USES ebx kc:DWORD, vk:DWORD
    mov  ebx, kc
    and  ebx, 0FFh
    inc  totalKeys
    inc  freq[ebx*4]                ; requirement (b)
    mov  eax, vk
    and  eax, 0FFh
    inc  vkFreq[eax*4]
    mov  rippleVk, eax
    mov  lastKeyCode, ebx
    cmp  ebx, 8                     ; Backspace = a correction
    jne  cc_nobs
    inc  bsCount
cc_nobs:

    invoke Classify, ebx            ; requirement (a)
    mov  curCat, eax
    cmp  eax, CAT_VOWEL
    jne  cc_cons
    inc  vowels
    jmp  cc_letter
cc_cons:
    cmp  eax, CAT_CONS
    jne  cc_digit
    inc  consonants
cc_letter:
    mov  eax, ebx
    or   eax, 20h
    sub  eax, 'a'
    mov  lastLetter, eax
    jmp  cc_glyph
cc_digit:
    cmp  eax, CAT_DIGIT
    jne  cc_space
    inc  digits
    jmp  cc_glyph
cc_space:
    cmp  eax, CAT_SPACE
    jne  cc_sym
    inc  spaces
    jmp  cc_glyph
cc_sym:
    cmp  eax, CAT_SYM
    jne  cc_other
    inc  symbols
    jmp  cc_glyph
cc_other:
    inc  others

cc_glyph:
    invoke TrackNgram, curCat, ebx  ; bigrams / trigrams
    invoke TrackErgo, ebx           ; biomechanics, latency, streak & sound
                                    ; word counter: a run of letters/digits is one word
    mov  eax, curCat
    cmp  eax, CAT_VOWEL
    je   cc_inword
    cmp  eax, CAT_CONS
    je   cc_inword
    cmp  eax, CAT_DIGIT
    je   cc_inword
    mov  inWord, 0
    jmp  cc_shown
cc_inword:
    cmp  inWord, 0
    jne  cc_wlen
    inc  words
    mov  inWord, 1
    mov  curWordLen, 0
cc_wlen:                            ; longest word of the session
    inc  curWordLen
    mov  eax, curWordLen
    cmp  eax, longestWord
    jbe  cc_shown
    mov  longestWord, eax
cc_shown:                          ; character shown in the last-N view
    mov  eax, ebx
    cmp  eax, 32
    jb   cc_ctrl
    cmp  eax, 126
    jbe  cc_push
    mov  eax, 0FEh
    jmp  cc_push
cc_ctrl:
    mov  edx, eax
    mov  eax, 0D9h                  ; Enter
    cmp  edx, 13
    je   cc_push
    mov  eax, 0AFh                  ; Tab
    cmp  edx, 9
    je   cc_push
    mov  eax, 0AEh                  ; Backspace
    cmp  edx, 8
    je   cc_push
    mov  eax, 0FEh
cc_push:                            ; requirement (c): circular buffer
    mov  ecx, lastHead
    mov  lastRing[ecx], al
    inc  ecx
    and  ecx, NMAX - 1
    mov  lastHead, ecx
    cmp  lastCount, NMAX
    jae  cc_time
    inc  lastCount

cc_time:                            ; remember when the key was pressed
    invoke GetTickCount
    mov  rippleTick, eax
    mov  ecx, tsHead
    mov  tsRing[ecx*4], eax
    inc  ecx
    and  ecx, TS_SIZE - 1
    mov  tsHead, ecx
    cmp  tsCount, TS_SIZE
    jae  cc_done
    inc  tsCount
cc_done:
    ret
CountChar ENDP

; ---- part * 100 / whole (0 if whole is 0) ----
Percent PROC part:DWORD, whole:DWORD
    mov  ecx, whole
    test ecx, ecx
    jz   pc_zero
    mov  eax, part
    mov  edx, 100
    mul  edx
    div  ecx
    ret
pc_zero:
    xor  eax, eax
    ret
Percent ENDP

; ---- pick the 5 most frequent keys from freq[] ----
; ---- pick the 5 largest entries of a DWORD table; returns eax = how many ----
TopFive PROC USES ebx esi edi pTab:DWORD, nEnt:DWORD, pIdx:DWORD, pCnt:DWORD
    LOCAL best:DWORD, bestCnt:DWORD
    xor  ebx, ebx                   ; ebx = rank being filled
tf_rank:
    cmp  ebx, 5
    jae  tf_done
    mov  best, -1
    mov  bestCnt, 0
    xor  esi, esi
tf_scan:
    cmp  esi, nEnt
    jae  tf_pick
    mov  edx, pTab
    mov  eax, [edx+esi*4]
    cmp  eax, bestCnt
    jbe  tf_next
    mov  edi, pIdx                  ; already picked?
    xor  ecx, ecx
tf_check:
    cmp  ecx, ebx
    jae  tf_take
    cmp  [edi+ecx*4], esi
    je   tf_next
    inc  ecx
    jmp  tf_check
tf_take:
    mov  best, esi
    mov  bestCnt, eax
tf_next:
    inc  esi
    jmp  tf_scan
tf_pick:
    cmp  best, -1
    je   tf_done
    mov  edi, pIdx
    mov  eax, best
    mov  [edi+ebx*4], eax
    mov  edi, pCnt
    mov  eax, bestCnt
    mov  [edi+ebx*4], eax
    inc  ebx
    jmp  tf_rank
tf_done:
    mov  eax, ebx
    ret
TopFive ENDP

; ---- top 5 keys, bigrams and trigrams ----
ComputeTop5 PROC
    invoke TopFive, ADDR freq, 256, ADDR top5Key, ADDR top5Cnt
    mov  top5N, eax
    invoke TopFive, ADDR bigrams, NG2, ADDR bi5Idx, ADDR bi5Cnt
    mov  bi5N, eax
    invoke TopFive, ADDR trigrams, NG3, ADDR tri5Idx, ADDR tri5Cnt
    mov  tri5N, eax
    ret
ComputeTop5 ENDP

; ---- timer, WPM and top 5 (called before every redraw) ----
UpdateStats PROC USES ebx esi
    invoke GetTickCount
    mov  nowTick, eax
    mov  ebx, eax
    sub  eax, startTick
    mov  elapsedMs, eax
    xor  edx, edx
    mov  ecx, 1000
    div  ecx
    mov  elapsedSec, eax

    xor  esi, esi                   ; keys pressed in the last WPM_WINDOW ms
    xor  ecx, ecx
us_loop:
    cmp  esi, tsCount
    jae  us_calc
    mov  eax, ebx
    sub  eax, tsRing[esi*4]
    cmp  eax, WPM_WINDOW
    jae  us_next
    inc  ecx
us_next:
    inc  esi
    jmp  us_loop
us_calc:                            ; WPM = keys per minute / 5
    imul eax, ecx, 60000 / WPM_WINDOW
    xor  edx, edx
    mov  ecx, 5
    div  ecx
    mov  wpmNow, eax
    cmp  eax, wpmPeak
    jbe  us_avg
    mov  wpmPeak, eax
us_avg:
    mov  wpmAvg, 0
    mov  ecx, elapsedMs
    cmp  ecx, WPM_WINDOW
    jb   us_top
    mov  eax, totalKeys
    mov  edx, 12000                 ; 60000 ms / 5 chars per word
    mul  edx
    div  ecx
    mov  wpmAvg, eax
us_top:                             ; one WPM sample per second for the history graph
    mov  eax, nowTick
    sub  eax, lastSample
    cmp  eax, 1000
    jb   us_top5
    mov  eax, nowTick
    mov  lastSample, eax
    mov  ecx, histHead
    mov  eax, wpmNow
    mov  wpmHist[ecx*4], eax
    inc  ecx
    and  ecx, HIST_SIZE - 1
    mov  histHead, ecx
    cmp  histCount, HIST_N
    jae  us_cards
    inc  histCount
us_cards:                           ; samples for the card sparklines
    mov  ecx, cardHead
    mov  eax, vowels
    mov  cardV[ecx*4], eax
    mov  eax, consonants
    mov  cardC[ecx*4], eax
    mov  eax, totalKeys
    mov  cardT[ecx*4], eax
    inc  ecx
    and  ecx, CARD_MASK
    mov  cardHead, ecx
    cmp  cardCount, CARD_SIZE
    jae  us_top5
    inc  cardCount
us_top5:
    invoke ComputeTop5
    invoke UpdateBadges
    ret
UpdateStats ENDP

; ---- short printable name for a key code ----
KeyName PROC kc:DWORD
    mov  eax, kc
    cmp  eax, 32
    jne  kn_ent
    mov  eax, OFFSET sSPC
    ret
kn_ent:
    cmp  eax, 13
    jne  kn_tab
    mov  eax, OFFSET sENT
    ret
kn_tab:
    cmp  eax, 9
    jne  kn_bsp
    mov  eax, OFFSET sTAB
    ret
kn_bsp:
    cmp  eax, 8
    jne  kn_ctl
    mov  eax, OFFSET sBSP
    ret
kn_ctl:
    cmp  eax, 32
    jae  kn_print
    mov  keyNameBuf, '^'            ; Ctrl+letter -> ^C etc.
    add  al, '@'
    mov  keyNameBuf+1, al
    mov  keyNameBuf+2, 0
    mov  eax, OFFSET keyNameBuf
    ret
kn_print:
    cmp  eax, 126
    ja   kn_ext
    mov  keyNameBuf, al
    mov  keyNameBuf+1, 0
    mov  eax, OFFSET keyNameBuf
    ret
kn_ext:
    mov  eax, OFFSET sEXT
    ret
KeyName ENDP

; ---- n-gram index -> lowercase letters (nlen = 2 or 3) ----
NgramName PROC idx:DWORD, nlen:DWORD
    mov  eax, idx
    mov  ecx, nlen
    mov  ngBuf[ecx], 0
ng_loop:
    dec  ecx
    xor  edx, edx
    push ecx
    mov  ecx, 26
    div  ecx
    pop  ecx
    add  dl, 'a'
    mov  ngBuf[ecx], dl
    test ecx, ecx
    jnz  ng_loop
    mov  eax, OFFSET ngBuf
    ret
NgramName ENDP

; =============================================================
;  Typing test and last-session statistics
; =============================================================

; ---- start the next sentence of the typing test ----
NewTest PROC
    mov  eax, testIdx
    inc  eax
    xor  edx, edx
    mov  ecx, 3
    div  ecx                        ; edx = (testIdx + 1) mod 3
    mov  eax, testMode
    imul eax, eax, 3
    add  eax, edx
    mov  testIdx, eax
    mov  eax, sentences[eax*4]
    mov  testPtr, eax
    invoke StrLen, eax
    mov  testLen, eax
    xor  eax, eax
    mov  testPos, eax
    mov  testKeys, eax
    mov  testErrors, eax
    mov  testStart, eax
    mov  testEnd, eax
    mov  testDone, eax
    mov  testNewBest, eax
    ret
NewTest ENDP

; ---- live (or final) test numbers: tWpm, tAcc, tSec ----
TestLive PROC USES ebx esi edi
    xor  eax, eax
    mov  tWpm, eax
    mov  tSec, eax
    mov  tAcc, 100
    cmp  testStart, 0
    je   tl_done
    mov  eax, nowTick
    cmp  testDone, 0
    je   tl_t
    mov  eax, testEnd
tl_t:
    sub  eax, testStart
    jnz  tl_ms
    inc  eax
tl_ms:
    mov  ebx, eax                   ; ebx = milliseconds
    xor  edx, edx
    mov  ecx, 1000
    div  ecx
    mov  tSec, eax
    xor  ecx, ecx                   ; correct characters so far
    xor  esi, esi
    mov  edi, testPtr
tl_cnt:
    cmp  esi, testPos
    jae  tl_wpm
    mov  al, testTyped[esi]
    cmp  al, [edi+esi]
    jne  tl_next
    inc  ecx
tl_next:
    inc  esi
    jmp  tl_cnt
tl_wpm:
    mov  eax, ecx                   ; WPM = (correct chars / 5) per minute
    mov  edx, 12000
    mul  edx
    div  ebx
    mov  tWpm, eax
    mov  ecx, testKeys              ; accuracy = keys typed right / keys typed
    test ecx, ecx
    jz   tl_done
    mov  eax, ecx
    sub  eax, testErrors
    mov  edx, 100
    mul  edx
    div  ecx
    mov  tAcc, eax
tl_done:
    ret
TestLive ENDP

; ---- one typed character while the typing test is on screen ----
TestKey PROC USES ebx kc:DWORD
    mov  eax, kc
    cmp  testDone, 0
    je   tk_live
    cmp  eax, 13                    ; finished: Enter starts the next sentence
    jne  tk_done
    invoke NewTest
    ret
tk_live:
    cmp  eax, 8                     ; Backspace steps back to fix a mistake
    jne  tk_char
    cmp  testPos, 0
    je   tk_done
    dec  testPos
    ret
tk_char:
    cmp  eax, 32
    jb   tk_done
    cmp  eax, 126
    ja   tk_done
    cmp  testStart, 0               ; the timer starts on the first key
    jne  tk_store
    push eax
    invoke GetTickCount
    mov  testStart, eax
    pop  eax
tk_store:
    mov  ebx, testPos
    mov  testTyped[ebx], al
    inc  testKeys
    mov  edx, testPtr
    cmp  al, [edx+ebx]
    je   tk_ok
    inc  testErrors
tk_ok:
    inc  ebx
    mov  testPos, ebx
    cmp  ebx, testLen
    jb   tk_done
    invoke GetTickCount             ; sentence finished
    mov  testEnd, eax
    mov  testDone, 1
    invoke TestLive
    mov  eax, tWpm
    cmp  eax, testBest
    jbe  tk_all
    mov  testBest, eax
tk_all:
    cmp  eax, bestTestAll
    jbe  tk_done
    mov  bestTestAll, eax
    mov  testNewBest, 1
tk_done:
    ret
TestKey ENDP

; ---- read the previous session from KeyStats.dat (if there is one) ----
LoadStats PROC USES ebx
    invoke CreateFileA, ADDR sStatsFile, 80000000h, 1, 0, 3, 80h, 0   ; read, OPEN_EXISTING
    cmp  eax, -1
    je   ls_done
    mov  ebx, eax
    invoke ReadFile, ebx, ADDR lastStats, STAT_N * 4, ADDR nRead, 0
    invoke CloseHandle, ebx
    cmp  nRead, STAT_N * 4
    jne  ls_done
    cmp  lastStats, STAT_MAGIC
    jne  ls_done
    mov  hasLast, 1
    mov  eax, lastStats[ST_BEST*4]
    mov  bestPeakAll, eax
    mov  eax, lastStats[ST_TBEST*4]
    mov  bestTestAll, eax
ls_done:
    ret
LoadStats ENDP

; ---- write this session to KeyStats.dat (kept if nothing was typed) ----
SaveStats PROC USES ebx
    cmp  totalKeys, 0
    je   sv_done
    invoke UpdateStats
    mov  statBuf, STAT_MAGIC
    mov  eax, totalKeys
    mov  statBuf[ST_TOTAL*4], eax
    mov  eax, vowels
    mov  statBuf[ST_VOW*4], eax
    mov  eax, consonants
    mov  statBuf[ST_CON*4], eax
    mov  eax, words
    mov  statBuf[ST_WORDS*4], eax
    mov  eax, wpmPeak
    mov  statBuf[ST_PEAK*4], eax
    mov  eax, wpmAvg
    mov  statBuf[ST_AVG*4], eax
    mov  eax, elapsedSec
    mov  statBuf[ST_TIME*4], eax
    mov  eax, bsCount
    mov  statBuf[ST_BS*4], eax
    mov  eax, wpmPeak               ; all-time best peak WPM
    cmp  eax, bestPeakAll
    jae  sv_best
    mov  eax, bestPeakAll
sv_best:
    mov  statBuf[ST_BEST*4], eax
    mov  eax, bestTestAll
    mov  statBuf[ST_TBEST*4], eax
    mov  eax, lastStats[ST_SESS*4]
    inc  eax
    mov  statBuf[ST_SESS*4], eax
    invoke CreateFileA, ADDR sStatsFile, 40000000h, 0, 0, 2, 80h, 0   ; write, CREATE_ALWAYS
    cmp  eax, -1
    je   sv_done
    mov  ebx, eax
    invoke WriteFile, ebx, ADDR statBuf, STAT_N * 4, ADDR nWritten, 0
    invoke CloseHandle, ebx
sv_done:
    ret
SaveStats ENDP

; =============================================================
;  Dashboard sections
; =============================================================

; ---- title bar: gradient, name, LIVE/PAUSED badge and session timer ----
DrawHeader PROC USES ebx
    xor  ebx, ebx
dh_grad:
    invoke Lerp, C_HDR1, C_HDR2, ebx, SCR_W - 1
    invoke Cell, ebx, 0, ' ', C_WHITE, eax
    inc  ebx
    cmp  ebx, SCR_W
    jb   dh_grad
    invoke Cell, 2, 0, 25C6h, C_CYAN, C_KEEP
    invoke Text, 4, 0, ADDR sTitle, C_WHITE, C_KEEP
    invoke Text, 23, 0, ADDR sSubtitle, C_HDRTXT, C_KEEP
    invoke Text, 59, 0, ADDR sHdrLvl, C_GOLD, C_KEEP
    invoke Num, eax, 0, xpLevel, C_WHITE
    mov  eax, xpLevel
    dec  eax
    cmp  eax, 4
    jbe  dh_rnk
    mov  eax, 4
dh_rnk:
    mov  eax, rankNames[eax*4]
    invoke Text, 66, 0, eax, C_CYAN, C_KEEP
    cmp  paused, 0
    je   dh_live
    invoke Cell, 74, 0, 25CFh, C_GOLD, C_KEEP
    invoke Text, 76, 0, ADDR sPaused, C_GOLD, C_KEEP
    jmp  dh_time
dh_live:
    mov  eax, C_OK                  ; blinking dot
    test nowTick, 512
    jz   dh_dot
    mov  eax, C_HDRTXT
dh_dot:
    invoke Cell, 74, 0, 25CFh, eax, C_KEEP
    invoke Text, 76, 0, ADDR sLive, C_OK, C_KEEP
dh_time:
    invoke Text, 86, 0, ADDR sTime, C_HDRTXT, C_KEEP
    invoke TimeMS, 91, 0, elapsedSec, C_WHITE
    ret
DrawHeader ENDP

; ---- one stat card: rounded box, gradient number, sparkline ----
Card PROC USES ebx esi px:DWORD, pTitle:DWORD, val:DWORD, c1:DWORD, c2:DWORD, pRing:DWORD, rmask:DWORD, head:DWORD, cnt:DWORD
    invoke Lerp, c2, C_BORDER, 35, 100
    invoke RBox, px, 2, 23, 6, pTitle, eax, c1
    mov  eax, px
    add  eax, 2
    invoke BigNum, eax, 3, val, c1, c2
    invoke NumToStr, val            ; sparkline fills the space after the digits
    lea  ebx, [ecx*4]
    mov  esi, 17
    sub  esi, ebx                   ; width = 17 - 4 * digits
    jle  cd_done
    mov  eax, px
    add  eax, ebx
    add  eax, 3
    invoke Spark, eax, 5, esi, pRing, rmask, head, cnt, c1, c2
cd_done:
    ret
Card ENDP

DrawCards PROC USES ebx
    mov  ebx, vowels
    add  ebx, consonants            ; ebx = letters typed
    invoke Tween, ADDR dispV, vowels
    invoke Tween, ADDR dispC, consonants
    invoke Tween, ADDR dispT, totalKeys

    invoke Card, 2, ADDR sCardV, dispV, C_GREEN, C_GREEN2, ADDR cardV, CARD_MASK, cardHead, cardCount
    invoke Percent, vowels, ebx
    invoke Num, 4, 6, eax, C_GREEN
    invoke Text, eax, 6, ADDR sPctLetters, C_MUTED, C_KEEP

    invoke Card, 26, ADDR sCardC, dispC, C_AMBER, C_AMBER2, ADDR cardC, CARD_MASK, cardHead, cardCount
    invoke Percent, consonants, ebx
    invoke Num, 28, 6, eax, C_AMBER
    invoke Text, eax, 6, ADDR sPctLetters, C_MUTED, C_KEEP

    invoke Card, 50, ADDR sCardT, dispT, C_CYAN, C_CYAN2, ADDR cardT, CARD_MASK, cardHead, cardCount
    invoke Text, 52, 6, ADDR sKeysSession, C_MUTED, C_KEEP

    invoke Card, 74, ADDR sCardW, wpmNow, C_PURP, C_PURP2, ADDR wpmHist, HIST_SIZE - 1, histHead, histCount
    invoke Text, 76, 6, ADDR sPeak, C_MUTED, C_KEEP
    invoke Num, eax, 6, wpmPeak, C_WHITE
    invoke Text, eax, 6, ADDR sAvg, C_MUTED, C_KEEP
    invoke Num, eax, 6, wpmAvg, C_WHITE
    ret
DrawCards ENDP

; ---- small "pill" counter on row 8; returns eax = next x ----
Chip PROC USES ebx px:DWORD, pLabel:DWORD, val:DWORD, fg:DWORD
    invoke Cell, px, 8, ' ', C_TEXT, C_PANEL
    mov  eax, px
    inc  eax
    invoke Text, eax, 8, pLabel, C_MUTED, C_PANEL
    mov  ebx, eax
    invoke NumToStr, val
    invoke Text, ebx, 8, eax, fg, C_PANEL
    mov  ebx, eax
    invoke Cell, ebx, 8, ' ', C_TEXT, C_PANEL
    lea  eax, [ebx+2]
    ret
Chip ENDP

; ---- counters (digits, spaces, symbols, other, words) and the mix bar ----
DrawChips PROC USES ebx esi edi
    invoke Chip, 2, ADDR sDigits, digits, C_CYAN
    invoke Chip, eax, ADDR sSpaces, spaces, C_TEXT
    invoke Chip, eax, ADDR sSymbols, symbols, C_PURP
    invoke Chip, eax, ADDR sOther, others, C_TEXT
    invoke Chip, eax, ADDR sWords, words, C_GREEN

    ; vowel / consonant mix bar (columns 62-95), green fading into amber
    invoke Cell, 60, 8, 'V', C_GREEN, C_KEEP
    invoke Cell, 97, 8, 'C', C_AMBER, C_KEEP
    mov  ecx, vowels
    add  ecx, consonants
    test ecx, ecx
    jnz  dc_bar
    invoke Fill, 62, 8, 34, 1, ' ', C_TEXT, C_TRACK
    ret
dc_bar:
    mov  eax, vowels
    mov  edx, 34
    mul  edx
    div  ecx
    mov  edi, eax                   ; edi = vowel part length
    xor  esi, esi
dc_cell:
    cmp  esi, 34
    jae  dc_done
    cmp  esi, edi
    jae  dc_cons
    invoke Lerp, C_GREEN2, C_GREEN, esi, 33
    jmp  dc_put
dc_cons:
    mov  ecx, esi
    sub  ecx, edi
    mov  edx, 33
    sub  edx, edi
    invoke Lerp, C_AMBER, C_AMBER2, ecx, edx
dc_put:
    lea  ecx, [esi+62]
    invoke Cell, ecx, 8, 2588h, eax, C_PAGE
    inc  esi
    jmp  dc_cell
dc_done:
    ret
DrawChips ENDP

; ---- "last N characters" panel: older keys fade out, newest highlighted ----
DrawLastN PROC USES ebx esi edi
    LOCAL show:DWORD, firstIdx:DWORD
    invoke RBox, 2, 9, 96, 3, ADDR sBoxLast, C_BORDER, C_TEXT
    invoke Text, 24, 9, ADDR sNEq, C_TEXT, C_KEEP
    invoke Num, eax, 9, nView, C_CYAN
    invoke Text, eax, 9, ADDR sNHint, C_MUTED, C_KEEP

    mov  eax, lastCount             ; show = min(lastCount, N)
    cmp  eax, nView
    jbe  ln_n
    mov  eax, nView
ln_n:
    mov  show, eax
    mov  edx, lastHead
    sub  edx, eax
    and  edx, NMAX - 1
    mov  firstIdx, edx

    xor  esi, esi                   ; oldest -> newest
ln_loop:
    cmp  esi, show
    jae  ln_empty
    mov  eax, firstIdx
    add  eax, esi
    and  eax, NMAX - 1
    movzx eax, lastRing[eax]
    invoke GlyphW, eax
    mov  edi, eax
    mov  ebx, show                  ; age 0 = newest
    dec  ebx
    sub  ebx, esi
    lea  ecx, [esi+4]
    test ebx, ebx
    jnz  ln_old
    invoke Cell, ecx, 10, edi, C_PAGE, C_CYAN
    jmp  ln_next
ln_old:
    push ecx
    invoke Lerp, C_WHITE, C_DIM, ebx, 24
    pop  ecx
    invoke Cell, ecx, 10, edi, eax, C_KEEP
ln_next:
    inc  esi
    jmp  ln_loop
ln_empty:                           ; free slots shown as dots
    cmp  esi, nView
    jae  ln_cursor
    lea  eax, [esi+4]
    invoke Cell, eax, 10, 00B7h, C_DIM, C_KEEP
    inc  esi
    jmp  ln_empty
ln_cursor:
    mov  eax, show
    cmp  eax, nView
    jae  ln_key
    test nowTick, 512
    jnz  ln_key
    add  eax, 4
    invoke Cell, eax, 10, 258Fh, C_CYAN, C_KEEP

ln_key:
    invoke Text, 70, 10, ADDR sLastKey, C_MUTED, C_KEEP
    cmp  lastKeyCode, -1
    jne  ln_has
    invoke Text, eax, 10, ADDR sDash, C_MUTED, C_KEEP
    ret
ln_has:
    mov  ebx, eax
    invoke KeyName, lastKeyCode
    invoke Text, ebx, 10, eax, C_WHITE, C_KEEP
    invoke Text, eax, 10, ADDR sAscii, C_MUTED, C_KEEP
    invoke Num, eax, 10, lastKeyCode, C_CYAN
    ret
DrawLastN ENDP

; ---- A-Z letter histogram: 5 rows of 1/8-step bars with a vertical gradient ----
DrawHistogram PROC USES ebx esi edi
    LOCAL maxL:DWORD, realMax:DWORD, cnt:DWORD, h8:DWORD, col:DWORD, lo:DWORD, hi:DWORD
    invoke RBox, 2, 12, 56, 10, ADDR sBoxHist, C_BORDER, C_TEXT
    invoke Cell, 4, 13, 25CFh, C_GREEN, C_KEEP
    invoke Text, 6, 13, ADDR sVowel, C_MUTED, C_KEEP
    invoke Cell, 13, 13, 25CFh, C_AMBER, C_KEEP
    invoke Text, 15, 13, ADDR sConsonant, C_MUTED, C_KEEP

    mov  realMax, 0                 ; tallest bar (upper + lower case)
    xor  esi, esi
hg_max:
    mov  eax, freq[esi*4 + 'A'*4]
    add  eax, freq[esi*4 + 'a'*4]
    cmp  eax, realMax
    jbe  hg_mnext
    mov  realMax, eax
hg_mnext:
    inc  esi
    cmp  esi, 26
    jb   hg_max
    mov  eax, realMax
    test eax, eax
    jnz  hg_m1
    inc  eax
hg_m1:
    mov  maxL, eax
    invoke Text, 47, 13, ADDR sMax, C_MUTED, C_KEEP
    invoke Num, eax, 13, realMax, C_WHITE

    invoke Fill, 4, 19, 52, 1, 2500h, C_AXIS, C_KEEP

    xor  esi, esi                   ; esi = letter 0-25
hg_col:
    mov  eax, esi
    shl  eax, 1
    add  eax, 4
    mov  col, eax
    mov  eax, freq[esi*4 + 'A'*4]
    add  eax, freq[esi*4 + 'a'*4]
    mov  cnt, eax

    mov  eax, esi
    add  eax, 'a'
    invoke Classify, eax
    mov  lo, C_AMBER2
    mov  hi, C_AMBER
    cmp  eax, CAT_VOWEL
    jne  hg_lbl
    mov  lo, C_GREEN2
    mov  hi, C_GREEN
hg_lbl:
    lea  edi, [esi+'A']
    cmp  esi, lastLetter
    jne  hg_l1
    invoke Cell, col, 20, edi, C_PAGE, C_CYAN
    jmp  hg_bars
hg_l1:
    mov  eax, C_TEXT
    cmp  cnt, 0
    jne  hg_l2
    mov  eax, C_DIM
hg_l2:
    invoke Cell, col, 20, edi, eax, C_KEEP

hg_bars:
    cmp  cnt, 0
    je   hg_next
    mov  eax, cnt                   ; height in eighths (1-40), rounded up
    mov  edx, 40
    mul  edx
    add  eax, maxL
    dec  eax
    div  maxL
    mov  h8, eax
    xor  edi, edi                   ; edi = row from the bottom
hg_bar:
    cmp  edi, 5
    jae  hg_next
    mov  eax, edi
    shl  eax, 3
    mov  ebx, h8
    sub  ebx, eax                   ; eighths left for this row
    jle  hg_next
    cmp  ebx, 8
    jbe  hg_e
    mov  ebx, 8
hg_e:
    invoke Lerp, lo, hi, edi, 4
    push eax
    invoke Eighth, ebx
    pop  edx
    mov  ecx, 18
    sub  ecx, edi
    invoke Cell, col, ecx, eax, edx, C_KEEP
    inc  edi
    jmp  hg_bar
hg_next:
    inc  esi
    cmp  esi, 26
    jb   hg_col
    ret
DrawHistogram ENDP

; ---- key colour on the cold -> hot ramp (cnt 0 = unused key) ----
HeatColor PROC cnt:DWORD
    cmp  cnt, 0
    jne  hc_ramp
    mov  eax, C_OFFKEY
    ret
hc_ramp:
    invoke Ramp, ADDR heatStops, 6, cnt, heatMax
    ret
HeatColor ENDP

; ---- label colour that stays readable on a key of that heat ----
HeatText PROC cnt:DWORD
    mov  eax, cnt
    test eax, eax
    jnz  ht_on
    mov  eax, C_MUTED
    ret
ht_on:
    imul eax, eax, 10               ; bright keys (> 30% of max) get dark text
    mov  ecx, heatMax
    imul ecx, ecx, 3
    cmp  eax, ecx
    jbe  ht_light
    mov  eax, C_PAGE
    ret
ht_light:
    mov  eax, C_WHITE
    ret
HeatText ENDP

; ---- one key: half blocks on both sides give it a keycap shape ----
Keycap PROC USES ebx px:DWORD, py:DWORD, lbl:DWORD, cnt:DWORD
    invoke HeatColor, cnt
    mov  ebx, eax
    mov  ecx, px                    ; ripple from the last key pressed
    inc  ecx
    invoke RippleMix, ecx, py, ebx
    mov  ebx, eax
    invoke Cell, px, py, 2590h, ebx, C_PANEL
    invoke HeatText, cnt
    mov  ecx, px
    inc  ecx
    invoke Cell, ecx, py, lbl, eax, ebx
    mov  ecx, px
    add  ecx, 2
    invoke Cell, ecx, py, 258Ch, ebx, C_PANEL
    ret
Keycap ENDP

; ---- QWERTY keyboard coloured cold to hot by key usage ----
DrawHeatmap PROC USES ebx esi edi
    LOCAL rowI:DWORD, kx:DWORD, ky:DWORD, pVk:DWORD
    invoke RBox, 59, 12, 39, 7, ADDR sBoxHeat, C_BORDER, C_TEXT
    invoke RippleSetup

    mov  heatMax, 1
    xor  ecx, ecx
hm_max:
    mov  eax, vkFreq[ecx*4]
    cmp  eax, heatMax
    jbe  hm_mnext
    mov  heatMax, eax
hm_mnext:
    inc  ecx
    cmp  ecx, 256
    jb   hm_max

    mov  rowI, 0
hm_row:
    mov  eax, rowI
    shl  eax, 4
    lea  ebx, kbRows[eax]
    mov  esi, [ebx]
    mov  edx, [ebx+4]
    mov  pVk, edx
    mov  edx, [ebx+8]
    mov  kx, edx
    mov  edx, [ebx+12]
    mov  ky, edx
hm_key:
    movzx edi, BYTE PTR [esi]
    test edi, edi
    jz   hm_nextrow
    mov  edx, pVk
    movzx eax, BYTE PTR [edx]
    invoke Keycap, kx, ky, edi, vkFreq[eax*4]
    add  kx, 3
    inc  esi
    inc  pVk
    jmp  hm_key
hm_nextrow:
    inc  rowI
    cmp  rowI, 4
    jb   hm_row

    invoke HeatColor, vkFreq[20h*4] ; space bar
    invoke RippleMix, 74, 17, eax
    mov  ebx, eax
    invoke HeatText, vkFreq[20h*4]
    mov  esi, eax
    invoke Cell, 65, 17, 2590h, ebx, C_PANEL
    invoke Fill, 66, 17, 18, 1, ' ', esi, ebx
    invoke Text, 72, 17, ADDR sSpace, esi, C_KEEP
    invoke Cell, 84, 17, 258Ch, ebx, C_PANEL

    invoke Text, 69, 18, ADDR sCold, C_MUTED, C_KEEP   ; legend in the bottom edge
    xor  esi, esi
hm_leg:
    invoke Ramp, ADDR heatStops, 6, esi, 11
    lea  ecx, [esi+75]
    invoke Cell, ecx, 18, 2588h, eax, C_KEEP
    inc  esi
    cmp  esi, 12
    jb   hm_leg
    invoke Text, 87, 18, ADDR sHot, C_MUTED, C_KEEP
    ret
DrawHeatmap ENDP

; ---- top 5 table: keys, bigrams and trigrams side by side ----
DrawRanks PROC USES ebx esi edi
    LOCAL ky:DWORD
    invoke RBox, 59, 19, 39, 8, ADDR sBoxRank, C_BORDER, C_TEXT
    invoke Text, 61, 20, ADDR sHdrKey, C_MUTED, C_KEEP
    invoke Text, 74, 20, ADDR sHdrBi, C_MUTED, C_KEEP
    invoke Text, 86, 20, ADDR sHdrTri, C_MUTED, C_KEEP
    invoke Cell, 72, 19, 252Ch, C_BORDER, C_KEEP   ; column separators
    invoke Cell, 84, 19, 252Ch, C_BORDER, C_KEEP
    invoke Cell, 72, 26, 2534h, C_BORDER, C_KEEP
    invoke Cell, 84, 26, 2534h, C_BORDER, C_KEEP
    mov  ebx, 20
dr_sep:
    cmp  ebx, 26
    jae  dr_rows
    invoke Cell, 72, ebx, 2502h, C_BORDER, C_KEEP
    invoke Cell, 84, ebx, 2502h, C_BORDER, C_KEEP
    inc  ebx
    jmp  dr_sep
dr_rows:
    xor  esi, esi
dr_loop:
    cmp  esi, 5
    jae  dr_done
    lea  eax, [esi+21]
    mov  ky, eax
    lea  eax, [esi+'1']
    invoke Cell, 60, ky, eax, rankColors[esi*4], C_KEEP

    cmp  esi, top5N                 ; keys, coloured by category
    jae  dr_k0
    mov  ebx, top5Key[esi*4]
    invoke Classify, ebx
    mov  edi, C_CYAN
    cmp  eax, CAT_VOWEL
    jne  dr_c1
    mov  edi, C_GREEN
dr_c1:
    cmp  eax, CAT_CONS
    jne  dr_c2
    mov  edi, C_AMBER
dr_c2:
    invoke KeyName, ebx
    invoke Text, 62, ky, eax, edi, C_KEEP
    invoke NumR, 70, ky, top5Cnt[esi*4], C_WHITE
    jmp  dr_bi
dr_k0:
    invoke Text, 62, ky, ADDR sDash, C_DIM, C_KEEP

dr_bi:
    cmp  esi, bi5N
    jae  dr_b0
    invoke NgramName, bi5Idx[esi*4], 2
    invoke Text, 74, ky, eax, C_TEXT, C_KEEP
    invoke NumR, 82, ky, bi5Cnt[esi*4], C_PURP
    jmp  dr_tri
dr_b0:
    invoke Text, 74, ky, ADDR sDash, C_DIM, C_KEEP

dr_tri:
    cmp  esi, tri5N
    jae  dr_t0
    invoke NgramName, tri5Idx[esi*4], 3
    invoke Text, 86, ky, eax, C_TEXT, C_KEEP
    invoke NumR, 95, ky, tri5Cnt[esi*4], C_CYAN
    jmp  dr_next
dr_t0:
    invoke Text, 86, ky, ADDR sDash, C_DIM, C_KEEP
dr_next:
    inc  esi
    jmp  dr_loop
dr_done:
    ret
DrawRanks ENDP

; ---- WPM history: gradient area chart, one column per second ----
DrawWpmHistory PROC USES ebx esi edi
    LOCAL mx:DWORD, h8:DWORD, newest:DWORD
    invoke RBox, 2, 22, 56, 5, ADDR sBoxWpm, C_BORDER, C_TEXT

    mov  mx, 20                     ; scale: at least 20 WPM
    xor  esi, esi
wh_max:
    cmp  esi, histCount
    jae  wh_scale
    mov  eax, histHead
    sub  eax, esi
    dec  eax
    and  eax, HIST_SIZE - 1
    mov  eax, wpmHist[eax*4]
    cmp  eax, mx
    jbe  wh_mnext
    mov  mx, eax
wh_mnext:
    inc  esi
    jmp  wh_max
wh_scale:
    invoke Text, 45, 22, ADDR sMaxB, C_MUTED, C_KEEP
    invoke Num, eax, 22, mx, C_WHITE
    invoke Cell, eax, 22, ' ', C_TEXT, C_KEEP

    xor  esi, esi                   ; esi = column 0 (oldest) .. HIST_N-1 (now)
wh_col:
    cmp  esi, HIST_N
    jae  wh_done
    lea  ebx, [esi+4]               ; x position
    mov  ecx, HIST_N
    sub  ecx, histCount
    cmp  esi, ecx
    jae  wh_have
wh_dot:
    invoke Cell, ebx, 25, 00B7h, C_BORDER, C_KEEP     ; no sample / 0 WPM
    jmp  wh_next
wh_have:
    mov  eax, histHead              ; sample index = head - (HIST_N - esi)
    add  eax, esi
    sub  eax, HIST_N
    and  eax, HIST_SIZE - 1
    mov  eax, wpmHist[eax*4]
    mov  edx, 24                    ; height in eighths (0-24), rounded up
    mul  edx
    add  eax, mx
    dec  eax
    div  mx
    test eax, eax
    jz   wh_dot
    mov  h8, eax
    mov  newest, 0
    cmp  esi, HIST_N - 1
    jne  wh_rows
    mov  newest, 1
wh_rows:
    xor  edi, edi                   ; edi = row from the bottom
wh_row:
    cmp  edi, 3
    jae  wh_next
    mov  eax, edi
    shl  eax, 3
    mov  ecx, h8
    sub  ecx, eax                   ; eighths left for this row
    jle  wh_next
    cmp  ecx, 8
    jbe  wh_e
    mov  ecx, 8
wh_e:
    push ecx
    add  eax, ecx                   ; colour by height: purple -> pink
    mov  edx, C_WHITE
    cmp  newest, 0
    jne  wh_c
    invoke Lerp, C_PURP2, C_PINK, eax, 24
    mov  edx, eax
wh_c:
    pop  ecx
    push edx
    invoke Eighth, ecx
    pop  edx
    mov  ecx, 25
    sub  ecx, edi
    invoke Cell, ebx, ecx, eax, edx, C_KEEP
    inc  edi
    jmp  wh_row
wh_next:
    inc  esi
    jmp  wh_col
wh_done:
    ret
DrawWpmHistory ENDP

; ---- one line of session stats under the panels ----
DrawStatsLine PROC USES ebx
    invoke Text, 2, 27, ADDR sLongest, C_MUTED, C_KEEP
    invoke Num, eax, 27, longestWord, C_AMBER
    invoke Text, eax, 27, ADDR sBackspaces, C_MUTED, C_KEEP
    invoke Num, eax, 27, bsCount, C_AMBER
    invoke Text, eax, 27, ADDR sErrRate, C_MUTED, C_KEEP
    mov  ebx, eax
    invoke Percent, bsCount, totalKeys
    invoke Num, ebx, 27, eax, C_AMBER
    invoke Cell, eax, 27, '%', C_AMBER, C_KEEP
    inc  eax
    invoke Text, eax, 27, ADDR sStreakSt, C_MUTED, C_KEEP
    invoke Num, eax, 27, bestStreak, C_GREEN
    invoke Text, eax, 27, ADDR sLatSt, C_MUTED, C_KEEP
    invoke Num, eax, 27, avgLatMs, C_CYAN
    invoke Text, eax, 27, ADDR sMsUnit, C_MUTED, C_KEEP
    invoke DrawCompare
    ret
DrawStatsLine ENDP

; ---- two-tone pill buttons, hover highlight and status message ----
DrawButtons PROC USES ebx esi edi
    LOCAL bw:DWORD, col:DWORD, dark:DWORD, pName:DWORD
    mov  ebx, 2                     ; x of the next button
    xor  esi, esi
bt_loop:
    cmp  esi, NBTN
    jae  bt_msg
    mov  eax, btnNames[esi*4]
    mov  pName, eax
    mov  eax, btnColors[esi*4]
    mov  col, eax
    cmp  esi, 2                     ; pause button while paused
    jne  bt_auto
    cmp  paused, 0
    je   bt_size
    mov  pName, OFFSET sBN2R
    mov  col, C_PAUSEBTN
    jmp  bt_size
bt_auto:
    cmp  esi, 3                     ; autosave button when on
    jne  bt_view
    cmp  autoSave, 0
    je   bt_size
    mov  pName, OFFSET sBN3On
    mov  col, C_GREEN2
    jmp  bt_size
bt_view:
    cmp  esi, 4                     ; typing test button while the test is shown
    jne  bt_size
    cmp  viewMode, 0
    je   bt_size
    mov  pName, OFFSET sBN5B
bt_size:
    invoke StrLen, btnKeys[esi*4]   ; width = edges + key + name
    mov  edi, eax
    invoke StrLen, pName
    lea  eax, [eax+edi+2]
    mov  bw, eax
    mov  btnX[esi*4], ebx
    mov  btnW[esi*4], eax

    cmp  mouseY, BTN_Y              ; mouse hovering this button?
    jne  bt_draw
    mov  eax, mouseX
    cmp  eax, ebx
    jl   bt_draw
    mov  edx, ebx
    add  edx, bw
    cmp  eax, edx
    jge  bt_draw
    invoke Lerp, col, C_WHITE, 25, 100
    mov  col, eax
bt_draw:
    invoke Lerp, col, C_BLACK, 35, 100
    mov  dark, eax
    invoke Cell, ebx, BTN_Y, 2590h, dark, C_PAGE
    lea  eax, [ebx+1]
    invoke Text, eax, BTN_Y, btnKeys[esi*4], C_WHITE, dark
    invoke Text, eax, BTN_Y, pName, C_WHITE, col
    invoke Cell, eax, BTN_Y, 258Ch, col, C_PAGE
    add  ebx, bw
    add  ebx, 2
    inc  esi
    jmp  bt_loop

bt_msg:
    cmp  msgPtr, 0
    je   bt_hint
    mov  eax, nowTick
    sub  eax, msgTick
    cmp  eax, MSG_TIME
    jae  bt_hint
    invoke Text, 2, 29, msgPtr, msgColor, C_KEEP     ; message replaces the hint
    ret
bt_hint:
    invoke Text, 2, 29, ADDR sHint, C_MUTED, C_KEEP
    ret
DrawButtons ENDP

; ---- move a shown number one step towards its real value (count-up) ----
Tween PROC USES ebx pDisp:DWORD, actual:DWORD
    mov  ebx, pDisp
    mov  eax, actual
    sub  eax, [ebx]
    jbe  tw_set                     ; going down (reset) or equal: jump there
    add  eax, 2                     ; step = ceil(gap / 3)
    xor  edx, edx
    mov  ecx, 3
    div  ecx
    add  [ebx], eax
    mov  animating, 1
    ret
tw_set:
    mov  eax, actual
    mov  [ebx], eax
    ret
Tween ENDP

; ---- find the heatmap position of the last key pressed (ripple centre) ----
RippleSetup PROC USES ebx esi edi
    mov  rippleOn, 0
    cmp  rippleVk, -1
    je   ri_done
    mov  eax, nowTick
    sub  eax, rippleTick
    cmp  eax, RIPPLE_MS
    jae  ri_done
    mov  rippleAge, eax
    mov  eax, rippleVk
    cmp  eax, 20h                   ; space bar
    jne  ri_rows
    mov  rippleX, 74
    mov  rippleY, 17
    jmp  ri_on
ri_rows:
    xor  ecx, ecx                   ; ecx = keyboard row
ri_row:
    cmp  ecx, 4
    jae  ri_done
    mov  ebx, ecx
    shl  ebx, 4
    add  ebx, OFFSET kbRows
    mov  esi, [ebx]                 ; labels
    mov  edi, [ebx+4]               ; virtual key codes
    xor  edx, edx
ri_key:
    cmp  BYTE PTR [esi+edx], 0
    je   ri_nextrow
    cmp  [edi+edx], al
    je   ri_found
    inc  edx
    jmp  ri_key
ri_nextrow:
    inc  ecx
    jmp  ri_row
ri_found:
    lea  edx, [edx+edx*2]           ; label column = x + 3*index + 1
    add  edx, [ebx+8]
    inc  edx
    mov  rippleX, edx
    mov  eax, [ebx+12]
    mov  rippleY, eax
ri_on:
    mov  rippleOn, 1
    mov  animating, 1
ri_done:
    ret
RippleSetup ENDP

; ---- key colour during a ripple: white flash on the key, a ring spreading out ----
RippleMix PROC px:DWORD, py:DWORD, clr:DWORD
    mov  eax, clr
    cmp  rippleOn, 0
    je   rm_done
    mov  eax, px                    ; distance in keys: |dx| / 3 + |dy|
    sub  eax, rippleX
    cdq
    xor  eax, edx
    sub  eax, edx
    inc  eax
    xor  edx, edx
    mov  ecx, 3
    div  ecx
    mov  ecx, eax
    mov  eax, py
    sub  eax, rippleY
    cdq
    xor  eax, edx
    sub  eax, edx
    add  ecx, eax
    test ecx, ecx
    jnz  rm_ring
    invoke Lerp, C_WHITE, clr, rippleAge, RIPPLE_MS     ; the pressed key
    ret
rm_ring:
    push ecx
    mov  eax, rippleAge             ; ring radius grows with age
    xor  edx, edx
    mov  ecx, RIPPLE_STEP
    div  ecx
    pop  ecx
    cmp  eax, ecx
    jne  rm_keep
    mov  eax, RIPPLE_MS             ; fainter as it spreads
    sub  eax, rippleAge
    invoke Lerp, clr, C_WHITE, eax, RIPPLE_MS * 2
    ret
rm_keep:
    mov  eax, clr
rm_done:
    ret
RippleMix ENDP

; ---- arrow and difference (green up, red down); returns eax = next x ----
Delta PROC USES ebx px:DWORD, py:DWORD, cur:DWORD, prev:DWORD
    mov  eax, cur
    sub  eax, prev
    jz   de_same
    js   de_down
    mov  ebx, eax
    invoke Cell, px, py, 25B2h, C_OK, C_KEEP
    mov  eax, px
    inc  eax
    invoke Num, eax, py, ebx, C_OK
    ret
de_down:
    neg  eax
    mov  ebx, eax
    invoke Cell, px, py, 25BCh, C_RED, C_KEEP
    mov  eax, px
    inc  eax
    invoke Num, eax, py, ebx, C_RED
    ret
de_same:
    invoke Cell, px, py, '=', C_MUTED, C_KEEP
    mov  eax, px
    inc  eax
    ret
Delta ENDP

; ---- this session against the last one (right half of the stats line) ----
DrawCompare PROC USES ebx
    invoke Text, 68, 27, ADDR sVsLast, C_MUTED, C_KEEP
    cmp  hasLast, 0
    jne  dcm_have
    invoke Text, eax, 27, ADDR sFirstRun, C_DIM, C_KEEP
    ret
dcm_have:
    invoke Text, eax, 27, ADDR sCmpAvg, C_MUTED, C_KEEP
    invoke Delta, eax, 27, wpmAvg, lastStats[ST_AVG*4]
    invoke Text, eax, 27, ADDR sCmpPeak, C_MUTED, C_KEEP
    invoke Delta, eax, 27, wpmPeak, lastStats[ST_PEAK*4]
    invoke Text, eax, 27, ADDR sCmpBest, C_MUTED, C_KEEP
    mov  ebx, eax
    mov  eax, wpmPeak
    cmp  eax, bestPeakAll
    jae  dcm_best
    mov  eax, bestPeakAll
dcm_best:
    invoke Num, ebx, 27, eax, C_GOLD
    ret
DrawCompare ENDP

; ---- typing test screen (F5): cards, the sentence, progress, result ----
DrawTestView PROC USES ebx esi edi
    LOCAL x0:DWORD
    invoke TestLive
    invoke Card, 2, ADDR sCardTW, tWpm, C_PURP, C_PURP2, 0, 0, 0, 0
    invoke Text, 4, 6, ADDR sBestSess, C_MUTED, C_KEEP
    invoke Num, eax, 6, testBest, C_WHITE
    invoke Text, eax, 6, ADDR sAllTime, C_MUTED, C_KEEP
    invoke Num, eax, 6, bestTestAll, C_GOLD
    invoke Card, 26, ADDR sCardAcc, tAcc, C_GREEN, C_GREEN2, 0, 0, 0, 0
    invoke Text, 28, 6, ADDR sPctCorrect, C_MUTED, C_KEEP
    invoke Card, 50, ADDR sCardErr, testErrors, C_AMBER, C_AMBER2, 0, 0, 0, 0
    invoke Text, 52, 6, ADDR sErrSub, C_MUTED, C_KEEP
    invoke Card, 74, ADDR sCardTime, tSec, C_CYAN, C_CYAN2, 0, 0, 0, 0
    invoke Text, 76, 6, ADDR sSecSub, C_MUTED, C_KEEP

    ; ---- the sentence: green = right, red = wrong, cyan = next ----
    invoke RBox, 2, 9, 96, 7, ADDR sBoxTest, C_BORDER, C_TEXT
    invoke Text, 68, 9, ADDR sModeLbl, C_MUTED, C_KEEP
    mov  ecx, testMode
    mov  edx, modeNames[ecx*4]
    invoke Text, eax, 9, edx, C_GOLD, C_KEEP
    invoke Text, eax, 9, ADDR sTabHint, C_MUTED, C_KEEP
    mov  eax, 92
    sub  eax, testLen
    shr  eax, 1
    add  eax, 4
    mov  x0, eax
    xor  esi, esi
tv_ch:
    cmp  esi, testLen
    jae  tv_bar
    mov  edx, testPtr
    movzx edi, BYTE PTR [edx+esi]   ; target character
    mov  ecx, x0
    add  ecx, esi
    cmp  esi, testPos
    jae  tv_rest
    mov  al, testTyped[esi]
    cmp  al, [edx+esi]
    jne  tv_wrong
    invoke Cell, ecx, 11, edi, C_GREEN, C_KEEP
    jmp  tv_next
tv_wrong:
    cmp  edi, ' '                   ; a missed space shows as a dot
    jne  tv_w2
    mov  edi, 00B7h
tv_w2:
    invoke Cell, ecx, 11, edi, C_WHITE, C_RED
    jmp  tv_next
tv_rest:
    jne  tv_todo
    cmp  testDone, 0
    jne  tv_todo
    invoke Cell, ecx, 11, edi, C_PAGE, C_CYAN
    jmp  tv_next
tv_todo:
    invoke Cell, ecx, 11, edi, C_TEXT, C_KEEP
tv_next:
    inc  esi
    jmp  tv_ch

tv_bar:                             ; progress bar, columns 6-85
    mov  eax, testPos
    mov  edx, 80
    mul  edx
    div  testLen
    mov  ebx, eax
    xor  esi, esi
tv_pb:
    cmp  esi, 80
    jae  tv_pct
    lea  ecx, [esi+6]
    cmp  esi, ebx
    jae  tv_pe
    push ecx
    invoke Lerp, C_CYAN2, C_CYAN, esi, 79
    pop  ecx
    invoke Cell, ecx, 13, 2584h, eax, C_KEEP
    jmp  tv_pn
tv_pe:
    invoke Cell, ecx, 13, 2584h, C_TRACK, C_KEEP
tv_pn:
    inc  esi
    jmp  tv_pb
tv_pct:
    mov  eax, testPos
    mov  edx, 100
    mul  edx
    div  testLen
    invoke Num, 88, 13, eax, C_CYAN
    invoke Cell, eax, 13, '%', C_CYAN, C_KEEP

    ; ---- instructions while typing, result when finished ----
    invoke RBox, 2, 17, 96, 10, ADDR sBoxResult, C_BORDER, C_TEXT
    cmp  testDone, 0
    jne  tv_res
    cmp  testPos, 0
    jne  tv_going
    invoke Text, 5, 19, ADDR sHow1, C_TEXT, C_KEEP
    invoke Text, 5, 21, ADDR sHow2, C_MUTED, C_KEEP
    invoke Text, 5, 23, ADDR sHow3, C_MUTED, C_KEEP
    ret
tv_going:
    invoke Text, 5, 19, ADDR sGoing, C_TEXT, C_KEEP
    invoke Num, eax, 19, testPos, C_CYAN
    mov  ebx, eax
    invoke Cell, ebx, 19, '/', C_MUTED, C_KEEP
    lea  eax, [ebx+1]
    invoke Num, eax, 19, testLen, C_TEXT
    invoke Text, eax, 19, ADDR sChars, C_MUTED, C_KEEP
    invoke Text, 5, 21, ADDR sHow2, C_MUTED, C_KEEP
    ret
tv_res:
    invoke BigNum, 5, 19, tWpm, C_PURP, C_PURP2
    invoke NumToStr, tWpm
    lea  eax, [ecx*4+5]
    invoke Text, eax, 21, ADDR sWpmWord, C_PURP, C_KEEP
    invoke Text, 26, 19, ADDR sResAcc, C_MUTED, C_KEEP
    invoke Num, eax, 19, tAcc, C_GREEN
    invoke Cell, eax, 19, '%', C_GREEN, C_KEEP
    invoke Text, 26, 20, ADDR sResErr, C_MUTED, C_KEEP
    invoke Num, eax, 20, testErrors, C_AMBER
    invoke Text, 26, 21, ADDR sResTime, C_MUTED, C_KEEP
    invoke TimeMS, eax, 21, tSec, C_CYAN
    invoke Text, 26, 22, ADDR sResBest, C_MUTED, C_KEEP
    invoke Num, eax, 22, testBest, C_WHITE
    invoke Text, eax, 22, ADDR sResAll, C_MUTED, C_KEEP
    invoke Num, eax, 22, bestTestAll, C_GOLD
    cmp  testNewBest, 0
    je   tv_again
    inc  eax
    invoke Text, eax, 22, ADDR sNewBest, C_GOLD, C_KEEP
tv_again:
    invoke Text, 5, 25, ADDR sAgain, C_MUTED, C_KEEP
    ret
DrawTestView ENDP

; ---- biomechanics, rhythm & achievements screen (F6) ----
DrawErgoView PROC USES ebx esi edi
    LOCAL totH:DWORD, yRow:DWORD
    mov  ebx, leftHand
    add  ebx, rightHand
    mov  totH, ebx

    ; 4 top cards: Left Hand %, Right Hand %, Avg Latency ms, Key Streak
    invoke Percent, leftHand, totH
    invoke Card, 2, ADDR sCardLH, eax, C_CYAN, C_CYAN2, 0, 0, 0, 0
    invoke Text, 4, 6, ADDR sSubKeys, C_MUTED, C_KEEP
    invoke Num, eax, 6, leftHand, C_WHITE

    invoke Percent, rightHand, totH
    invoke Card, 26, ADDR sCardRH, eax, C_PURP, C_PURP2, 0, 0, 0, 0
    invoke Text, 28, 6, ADDR sSubKeys, C_MUTED, C_KEEP
    invoke Num, eax, 6, rightHand, C_WHITE
    invoke Text, 40, 6, ADDR sSubAlt, C_MUTED, C_KEEP
    invoke Num, eax, 6, handAlt, C_GREEN

    invoke Card, 50, ADDR sCardLat, avgLatMs, C_AMBER, C_AMBER2, 0, 0, 0, 0
    invoke Text, 52, 6, ADDR sSubMinLat, C_MUTED, C_KEEP
    invoke Num, eax, 6, minLatMs, C_WHITE
    invoke Text, eax, 6, ADDR sMsUnit, C_MUTED, C_KEEP

    invoke Card, 74, ADDR sCardStrk, curStreak, C_GREEN, C_GREEN2, 0, 0, 0, 0
    invoke Text, 76, 6, ADDR sSubBestSt, C_MUTED, C_KEEP
    invoke Num, eax, 6, bestStreak, C_GOLD
    invoke Text, eax, 6, ADDR sSubBadges, C_MUTED, C_KEEP
    invoke Num, eax, 6, badgeCount, C_CYAN

    ; Left panel: Finger Load (9 rows: L-Pinky..L-Index, R-Index..R-Pinky, Thumbs)
    invoke RBox, 2, 9, 47, 12, ADDR sBoxFinger, C_BORDER, C_TEXT
    xor  esi, esi
de_floop:
    cmp  esi, 9
    jae  de_rows
    lea  eax, [esi+11]
    mov  yRow, eax
    mov  eax, fingerNames[esi*4]
    invoke Text, 4, yRow, eax, C_TEXT, C_KEEP
    invoke Fill, 14, yRow, 22, 1, 2500h, C_TRACK, C_KEEP
    invoke Percent, fingerCnt[esi*4], totalKeys
    mov  edi, eax                   ; edi = percent
    imul eax, eax, 22
    xor  edx, edx
    mov  ecx, 100
    div  ecx
    cmp  eax, 22
    jbe  de_fbar
    mov  eax, 22
de_fbar:
    mov  ebx, C_CYAN
    cmp  esi, 4
    jb   de_fcol
    mov  ebx, C_PURP
    cmp  esi, 8
    jb   de_fcol
    mov  ebx, C_GREEN
de_fcol:
    test eax, eax
    jz   de_fnum
    invoke Fill, 14, yRow, eax, 1, 2588h, ebx, C_KEEP
de_fnum:
    invoke NumR, 40, yRow, fingerCnt[esi*4], C_WHITE
    invoke NumR, 45, yRow, edi, C_MUTED
    invoke Cell, 46, yRow, '%', C_MUTED, C_KEEP
    inc  esi
    jmp  de_floop

de_rows:
    ; Right panel: Row Distribution + Rhythm & Cadence stats
    invoke RBox, 51, 9, 47, 12, ADDR sBoxRows, C_BORDER, C_TEXT
    xor  esi, esi
de_rloop:
    cmp  esi, 5
    jae  de_rhy
    lea  eax, [esi+11]
    mov  yRow, eax
    mov  eax, rowNames[esi*4]
    invoke Text, 53, yRow, eax, C_TEXT, C_KEEP
    invoke Percent, rowCnt[esi*4], totalKeys
    mov  edi, eax
    invoke Fill, 72, yRow, 14, 1, 2500h, C_TRACK, C_KEEP
    imul eax, edi, 14
    xor  edx, edx
    mov  ecx, 100
    div  ecx
    test eax, eax
    jz   de_rnum
    invoke Fill, 72, yRow, eax, 1, 2588h, C_AMBER, C_KEEP
de_rnum:
    invoke NumR, 91, yRow, rowCnt[esi*4], C_WHITE
    invoke NumR, 95, yRow, edi, C_MUTED
    invoke Cell, 96, yRow, '%', C_MUTED, C_KEEP
    inc  esi
    jmp  de_rloop

de_rhy:
    invoke Text, 53, 17, ADDR sRhyActive, C_MUTED, C_KEEP
    mov  ebx, eax
    mov  eax, activeMs
    xor  edx, edx
    mov  ecx, 1000
    div  ecx
    invoke TimeMS, ebx, 17, eax, C_CYAN
    invoke Text, 53, 18, ADDR sRhyBurst, C_MUTED, C_KEEP
    invoke Num, eax, 18, wpmPeak, C_PURP
    invoke Text, 53, 19, ADDR sRhyAlt, C_MUTED, C_KEEP
    invoke Num, eax, 19, handAlt, C_GREEN

    ; Bottom panel: Achievements & XP Badges (2 columns x 3 rows)
    invoke RBox, 2, 21, 96, 6, ADDR sBoxBadges, C_BORDER, C_TEXT
    invoke Text, 78, 21, ADDR sXpLbl, C_MUTED, C_KEEP
    invoke Num, eax, 21, xpScore, C_GOLD
    xor  esi, esi
de_bloop:
    cmp  esi, 6
    jae  de_done
    mov  eax, esi
    and  eax, 1
    imul ebx, eax, 47
    add  ebx, 4                     ; x = 4 or 51
    mov  eax, esi
    shr  eax, 1
    add  eax, 22                    ; y = 22, 23, 24
    mov  yRow, eax
    mov  ecx, esi
    mov  eax, 1
    shl  eax, cl
    test badgesMask, eax
    jz   de_locked
    invoke Text, ebx, yRow, ADDR sUnlocked, C_OK, C_KEEP
    mov  edx, badgeNames[esi*4]
    add  ebx, 11
    invoke Text, ebx, yRow, edx, C_WHITE, C_KEEP
    jmp  de_bnext
de_locked:
    invoke Text, ebx, yRow, ADDR sLocked, C_DIM, C_KEEP
    mov  edx, badgeNames[esi*4]
    add  ebx, 11
    invoke Text, ebx, yRow, edx, C_MUTED, C_KEEP
de_bnext:
    inc  esi
    jmp  de_bloop
de_done:
    ret
DrawErgoView ENDP

; ---- redraw every panel into the canvas, then flush once ----
RenderAll PROC
    mov  animating, 0
    invoke UpdateStats
    invoke Fill, 0, 0, SCR_W, SCR_H, ' ', C_TEXT, C_PAGE
    invoke DrawHeader
    cmp  viewMode, 1
    je   ra_test
    cmp  viewMode, 2
    je   ra_ergo
    invoke DrawCards
    invoke DrawChips
    invoke DrawLastN
    invoke DrawHistogram
    invoke DrawHeatmap
    invoke DrawRanks
    invoke DrawWpmHistory
    jmp  ra_bottom
ra_test:
    invoke DrawTestView
    jmp  ra_bottom
ra_ergo:
    invoke DrawErgoView
ra_bottom:
    invoke DrawStatsLine
    invoke DrawButtons
    invoke Flush
    mov  frameWait, 250             ; about 30 fps only while something moves
    cmp  animating, 0
    je   ra_done
    mov  frameWait, 30
ra_done:
    ret
RenderAll ENDP

; =============================================================
;  Report (F2 saves it, ESC prints it)
; =============================================================

; ---- report builder: append a zero-terminated string ----
AppStr PROC USES esi edi pStr:DWORD
    mov  esi, pStr
    mov  edi, appBase
    add  edi, rptLen
as_loop:
    mov  al, [esi]
    test al, al
    jz   as_done
    mov  [edi], al
    inc  esi
    inc  edi
    jmp  as_loop
as_done:
    sub  edi, appBase
    mov  rptLen, edi
    ret
AppStr ENDP

; ---- report builder: append one character ----
AppCh PROC chv:DWORD
    mov  edx, rptLen
    add  edx, appBase
    mov  eax, chv
    mov  [edx], al
    inc  rptLen
    ret
AppCh ENDP

; ---- report builder: append an unsigned decimal number ----
AppNum PROC val:DWORD
    invoke NumToStr, val
    invoke AppStr, eax
    ret
AppNum ENDP

; ---- report builder: append "label value" and a line break ----
AppLine PROC pLabel:DWORD, val:DWORD
    invoke AppStr, pLabel
    invoke AppNum, val
    invoke AppStr, ADDR crlf
    ret
AppLine ENDP

; ---- string padded with spaces to 5 columns ----
AppPadded PROC USES ebx pStr:DWORD
    invoke AppStr, pStr
    invoke StrLen, pStr
    mov  ebx, eax
ap_pad:
    cmp  ebx, 5
    jae  ap_done
    invoke AppCh, ' '
    inc  ebx
    jmp  ap_pad
ap_done:
    ret
AppPadded ENDP

; ---- report builder: append two digits with a leading zero ----
AppTwo PROC val:DWORD
    mov  eax, val
    xor  edx, edx
    mov  ecx, 10
    div  ecx
    push edx
    add  eax, '0'
    invoke AppCh, eax
    pop  edx
    add  edx, '0'
    invoke AppCh, edx
    ret
AppTwo ENDP

; ---- assemble the full text report into rptBuf ----
BuildReport PROC USES ebx esi edi
    mov  appBase, OFFSET rptBuf
    mov  rptLen, 0
    invoke UpdateStats
    invoke AppStr, ADDR rpTitle
    invoke AppLine, ADDR rpTotal, totalKeys
    invoke AppLine, ADDR rpVow, vowels
    invoke AppLine, ADDR rpCon, consonants
    invoke AppLine, ADDR rpDig, digits
    invoke AppLine, ADDR rpSpc, spaces
    invoke AppLine, ADDR rpSym, symbols
    invoke AppLine, ADDR rpOth, others
    invoke AppLine, ADDR rpWords, words
    invoke AppLine, ADDR rpLong, longestWord
    invoke AppLine, ADDR rpBs, bsCount
    invoke Percent, bsCount, totalKeys
    invoke AppLine, ADDR rpErr, eax
    invoke AppLine, ADDR rpPeak, wpmPeak
    invoke AppLine, ADDR rpAvg, wpmAvg
    invoke AppLine, ADDR rpTest, testBest
    invoke AppLine, ADDR rpLeftH, leftHand
    invoke AppLine, ADDR rpRightH, rightHand
    invoke AppLine, ADDR rpAvgLat, avgLatMs
    invoke AppLine, ADDR rpBestStrk, bestStreak
    invoke AppLine, ADDR rpXpLvl, xpLevel
    invoke AppLine, ADDR rpBadges, badgeCount
    cmp  hasLast, 0
    je   br_nolast
    invoke AppLine, ADDR rpLastAvg, lastStats[ST_AVG*4]
    invoke AppLine, ADDR rpLastPeak, lastStats[ST_PEAK*4]
br_nolast:

    invoke AppStr, ADDR rpTime      ; mm:ss
    mov  eax, elapsedSec
    xor  edx, edx
    mov  ecx, 60
    div  ecx
    mov  ebx, edx
    cmp  eax, 99
    jbe  br_min
    mov  eax, 99
br_min:
    invoke AppTwo, eax
    invoke AppCh, ':'
    invoke AppTwo, ebx
    invoke AppStr, ADDR crlf

    invoke AppStr, ADDR rpLast      ; last N characters
    mov  ebx, lastCount
    cmp  ebx, nView
    jbe  br_n
    mov  ebx, nView
br_n:
    mov  esi, lastHead
    sub  esi, ebx
    xor  edi, edi
br_last:
    cmp  edi, ebx
    jae  br_lastend
    mov  eax, esi
    add  eax, edi
    and  eax, NMAX - 1
    movzx eax, lastRing[eax]
    cmp  eax, 127
    jb   br_lc
    mov  eax, '.'
br_lc:
    invoke AppCh, eax
    inc  edi
    jmp  br_last
br_lastend:
    invoke AppStr, ADDR rpLastEnd

    invoke AppStr, ADDR rpTop       ; top 5
    xor  esi, esi
br_top:
    cmp  esi, top5N
    jae  br_freq
    invoke AppStr, ADDR rpIndent
    lea  eax, [esi+'1']
    invoke AppCh, eax
    invoke AppStr, ADDR rpDot
    invoke KeyName, top5Key[esi*4]
    invoke AppPadded, eax
    invoke AppStr, ADDR rpTimes
    invoke AppNum, top5Cnt[esi*4]
    invoke AppStr, ADDR crlf
    inc  esi
    jmp  br_top

br_freq:                            ; top bigrams and trigrams
    invoke AppStr, ADDR rpBi
    xor  esi, esi
br_bi:
    cmp  esi, bi5N
    jae  br_tri0
    invoke AppStr, ADDR rpIndent
    lea  eax, [esi+'1']
    invoke AppCh, eax
    invoke AppStr, ADDR rpDot
    invoke NgramName, bi5Idx[esi*4], 2
    invoke AppPadded, eax
    invoke AppStr, ADDR rpTimes
    invoke AppNum, bi5Cnt[esi*4]
    invoke AppStr, ADDR crlf
    inc  esi
    jmp  br_bi
br_tri0:
    invoke AppStr, ADDR rpTri
    xor  esi, esi
br_tri:
    cmp  esi, tri5N
    jae  br_table
    invoke AppStr, ADDR rpIndent
    lea  eax, [esi+'1']
    invoke AppCh, eax
    invoke AppStr, ADDR rpDot
    invoke NgramName, tri5Idx[esi*4], 3
    invoke AppPadded, eax
    invoke AppStr, ADDR rpTimes
    invoke AppNum, tri5Cnt[esi*4]
    invoke AppStr, ADDR crlf
    inc  esi
    jmp  br_tri

br_table:                           ; full frequency table                            ; full frequency table
    invoke AppStr, ADDR rpFreq
    xor  esi, esi
br_fl:
    cmp  freq[esi*4], 0
    je   br_fnext
    invoke AppStr, ADDR rpIndent
    invoke KeyName, esi
    invoke AppPadded, eax
    invoke AppStr, ADDR rpAsciiTxt
    invoke AppNum, esi
    invoke AppStr, ADDR rpArrow
    invoke AppNum, freq[esi*4]
    invoke AppStr, ADDR crlf
br_fnext:
    inc  esi
    cmp  esi, 256
    jb   br_fl
    ret
BuildReport ENDP

; =============================================================
;  HTML report (F2): a styled page with charts, opened in the browser
; =============================================================

; ---- report builder: append text with HTML special characters escaped ----
AppEsc PROC USES esi pStr:DWORD
    mov  esi, pStr
ae_loop:
    movzx eax, BYTE PTR [esi]
    test eax, eax
    jz   ae_done
    cmp  eax, '<'
    jne  ae_gt
    invoke AppStr, ADDR hEscLt
    jmp  ae_next
ae_gt:
    cmp  eax, '>'
    jne  ae_amp
    invoke AppStr, ADDR hEscGt
    jmp  ae_next
ae_amp:
    cmp  eax, '&'
    jne  ae_quot
    invoke AppStr, ADDR hEscAmp
    jmp  ae_next
ae_quot:
    cmp  eax, 22h
    jne  ae_ch
    invoke AppStr, ADDR hEscQuot
    jmp  ae_next
ae_ch:
    invoke AppCh, eax
ae_next:
    inc  esi
    jmp  ae_loop
ae_done:
    ret
AppEsc ENDP

; ---- report builder: one byte as two hex digits ----
AppByteHex PROC b:DWORD
    mov  eax, b
    shr  eax, 4
    and  eax, 0Fh
    movzx eax, hexDigits[eax]
    invoke AppCh, eax
    mov  eax, b
    and  eax, 0Fh
    movzx eax, hexDigits[eax]
    invoke AppCh, eax
    ret
AppByteHex ENDP

; ---- report builder: colour as #rrggbb ----
AppHex PROC USES ebx clr:DWORD
    mov  ebx, clr
    invoke AppCh, '#'
    movzx eax, bl
    invoke AppByteHex, eax
    movzx eax, bh
    invoke AppByteHex, eax
    shr  ebx, 16
    movzx eax, bl
    invoke AppByteHex, eax
    ret
AppHex ENDP

; ---- report builder: seconds as mm:ss ----
AppMMSS PROC USES ebx secs:DWORD
    mov  eax, secs
    xor  edx, edx
    mov  ecx, 60
    div  ecx
    mov  ebx, edx
    cmp  eax, 99
    jbe  am_min
    mov  eax, 99
am_min:
    invoke AppTwo, eax
    invoke AppCh, ':'
    invoke AppTwo, ebx
    ret
AppMMSS ENDP

; ---- stat card: label and big value; the caller adds the small line and hCardEnd ----
AppCardOpen PROC pLabel:DWORD, val:DWORD, clr:DWORD
    invoke AppStr, ADDR hCard1
    invoke AppStr, pLabel
    invoke AppStr, ADDR hCard2
    invoke AppHex, clr
    invoke AppStr, ADDR hCard3
    invoke AppNum, val
    invoke AppStr, ADDR hCard4
    ret
AppCardOpen ENDP

; ---- table row: this session, last session, change ----
AppCmpRow PROC pLabel:DWORD, cur:DWORD, prev:DWORD
    invoke AppStr, ADDR hTrTd
    invoke AppStr, pLabel
    invoke AppStr, ADDR hTdTd
    invoke AppNum, cur
    invoke AppStr, ADDR hTdTd
    invoke AppNum, prev
    mov  eax, cur
    sub  eax, prev
    jz   cr_same
    js   cr_down
    push eax
    invoke AppStr, ADDR hTdUp
    pop  eax
    invoke AppNum, eax
    jmp  cr_end
cr_down:
    neg  eax
    push eax
    invoke AppStr, ADDR hTdDown
    pop  eax
    invoke AppNum, eax
    jmp  cr_end
cr_same:
    invoke AppStr, ADDR hTdSame
cr_end:
    invoke AppStr, ADDR hTdTrEnd
    ret
AppCmpRow ENDP

; ---- assemble KeyReport.html into htmlBuf ----
BuildHtml PROC USES ebx esi edi
    LOCAL mx:DWORD, cnt:DWORD, rowI:DWORD, pVk:DWORD
    mov  appBase, OFFSET htmlBuf
    mov  rptLen, 0
    invoke UpdateStats

    invoke AppStr, ADDR hHead       ; page head, title and date
    invoke GetLocalTime, ADDR sysTime
    movzx eax, sysTime
    invoke AppNum, eax
    invoke AppCh, '-'
    movzx eax, sysTime+2
    invoke AppTwo, eax
    invoke AppCh, '-'
    movzx eax, sysTime+6
    invoke AppTwo, eax
    invoke AppCh, ' '
    movzx eax, sysTime+8
    invoke AppTwo, eax
    invoke AppCh, ':'
    movzx eax, sysTime+10
    invoke AppTwo, eax
    invoke AppStr, ADDR hDot
    invoke AppMMSS, elapsedSec
    invoke AppStr, ADDR hSubEnd

    ; ---- stat cards ----
    mov  ebx, vowels
    add  ebx, consonants
    invoke AppCardOpen, ADDR hlTotal, totalKeys, C_CYAN
    invoke AppStr, ADDR hlKeysSess
    invoke AppStr, ADDR hCardEnd
    invoke AppCardOpen, ADDR hlVowels, vowels, C_GREEN
    invoke Percent, vowels, ebx
    invoke AppNum, eax
    invoke AppStr, ADDR hlPctLetters
    invoke AppStr, ADDR hCardEnd
    invoke AppCardOpen, ADDR hlCons, consonants, C_AMBER
    invoke Percent, consonants, ebx
    invoke AppNum, eax
    invoke AppStr, ADDR hlPctLetters
    invoke AppStr, ADDR hCardEnd
    invoke AppCardOpen, ADDR hlAvg, wpmAvg, C_PURP
    invoke AppStr, ADDR hlPeak
    invoke AppNum, wpmPeak
    invoke AppStr, ADDR hCardEnd
    invoke AppStr, ADDR hGridNext
    invoke AppCardOpen, ADDR hlWords, words, C_GREEN
    invoke AppStr, ADDR hlLongest
    invoke AppNum, longestWord
    invoke AppStr, ADDR hCardEnd
    invoke AppCardOpen, ADDR hlBs, bsCount, C_AMBER
    invoke Percent, bsCount, totalKeys
    invoke AppNum, eax
    invoke AppStr, ADDR hlCorr
    invoke AppStr, ADDR hCardEnd
    invoke AppCardOpen, ADDR hlSpaces, spaces, C_TEXT
    invoke AppStr, ADDR hlDigits
    invoke AppNum, digits
    invoke AppStr, ADDR hlSymbols
    invoke AppNum, symbols
    invoke AppStr, ADDR hCardEnd
    invoke AppCardOpen, ADDR hlTest, testBest, C_PINK
    invoke AppStr, ADDR hlAllTime
    invoke AppNum, bestTestAll
    invoke AppStr, ADDR hCardEnd
    invoke AppStr, ADDR hGridEnd

    ; ---- comparison with the last session ----
    cmp  hasLast, 0
    je   bh_bars
    invoke AppStr, ADDR hCmpHead
    invoke AppCmpRow, ADDR hlAvg, wpmAvg, lastStats[ST_AVG*4]
    invoke AppCmpRow, ADDR hlPeakW, wpmPeak, lastStats[ST_PEAK*4]
    invoke AppCmpRow, ADDR hlTotal, totalKeys, lastStats[ST_TOTAL*4]
    invoke AppCmpRow, ADDR hlWords, words, lastStats[ST_WORDS*4]
    invoke AppCmpRow, ADDR hlBs, bsCount, lastStats[ST_BS*4]
    invoke AppStr, ADDR hCmpEnd

bh_bars:                            ; ---- letter frequency bars ----
    invoke AppStr, ADDR hBarsHead
    mov  mx, 1
    xor  esi, esi
bh_max:
    mov  eax, freq[esi*4 + 'A'*4]
    add  eax, freq[esi*4 + 'a'*4]
    cmp  eax, mx
    jbe  bh_mnext
    mov  mx, eax
bh_mnext:
    inc  esi
    cmp  esi, 26
    jb   bh_max
    xor  esi, esi
bh_bar:
    mov  eax, freq[esi*4 + 'A'*4]
    add  eax, freq[esi*4 + 'a'*4]
    mov  cnt, eax
    invoke AppStr, ADDR hBar1
    cmp  cnt, 0
    je   bh_nonum
    invoke AppNum, cnt
bh_nonum:
    invoke AppStr, ADDR hBar2
    mov  eax, cnt                   ; bar height in pixels (0-130)
    mov  edx, 130
    mul  edx
    div  mx
    invoke AppNum, eax
    invoke AppStr, ADDR hBar3
    lea  eax, [esi+'a']
    invoke Classify, eax
    mov  ecx, C_AMBER2
    cmp  eax, CAT_VOWEL
    jne  bh_col
    mov  ecx, C_GREEN2
bh_col:
    invoke AppHex, ecx
    invoke AppStr, ADDR hBar4
    lea  eax, [esi+'A']
    invoke AppCh, eax
    invoke AppStr, ADDR hBar5
    inc  esi
    cmp  esi, 26
    jb   bh_bar

    ; ---- keyboard heatmap ----
    invoke AppStr, ADDR hKbHead
    mov  heatMax, 1
    xor  ecx, ecx
bh_hmax:
    mov  eax, vkFreq[ecx*4]
    cmp  eax, heatMax
    jbe  bh_hnext
    mov  heatMax, eax
bh_hnext:
    inc  ecx
    cmp  ecx, 256
    jb   bh_hmax
    mov  rowI, 0
bh_row:
    invoke AppStr, ADDR hKbRow
    mov  eax, rowI
    imul eax, eax, 14
    invoke AppNum, eax
    invoke AppStr, ADDR hKbRow2
    mov  eax, rowI
    shl  eax, 4
    mov  esi, kbRows[eax]
    mov  eax, kbRows[eax+4]
    mov  pVk, eax
bh_key:
    movzx edi, BYTE PTR [esi]
    test edi, edi
    jz   bh_rowend
    mov  edx, pVk
    movzx eax, BYTE PTR [edx]
    mov  eax, vkFreq[eax*4]
    mov  cnt, eax
    invoke AppStr, ADDR hKey1
    invoke HeatColor, cnt
    invoke AppHex, eax
    invoke AppStr, ADDR hKey2
    invoke HeatText, cnt
    invoke AppHex, eax
    invoke AppStr, ADDR hKey3
    mov  eax, edi
    mov  keyNameBuf, al
    mov  keyNameBuf+1, 0
    invoke AppEsc, ADDR keyNameBuf
    invoke AppStr, ADDR hKey4
    inc  esi
    inc  pVk
    jmp  bh_key
bh_rowend:
    invoke AppStr, ADDR hDivEnd
    inc  rowI
    cmp  rowI, 4
    jb   bh_row
    invoke AppStr, ADDR hSpace1     ; space bar
    invoke HeatColor, vkFreq[20h*4]
    invoke AppHex, eax
    invoke AppStr, ADDR hKey2
    invoke HeatText, vkFreq[20h*4]
    invoke AppHex, eax
    invoke AppStr, ADDR hSpace2

    ; ---- WPM history as an SVG area chart ----
    invoke AppStr, ADDR hWpmHead
    mov  mx, 20
    xor  esi, esi
bh_wmax:
    cmp  esi, histCount
    jae  bh_area
    mov  eax, histHead
    sub  eax, esi
    dec  eax
    and  eax, HIST_SIZE - 1
    mov  eax, wpmHist[eax*4]
    cmp  eax, mx
    jbe  bh_wnext
    mov  mx, eax
bh_wnext:
    inc  esi
    jmp  bh_wmax
bh_area:
    cmp  histCount, 0
    je   bh_svgend
    invoke AppStr, ADDR hPoly1      ; filled area under the line
    mov  eax, HIST_N
    sub  eax, histCount
    imul eax, eax, 10
    invoke AppNum, eax
    invoke AppStr, ADDR hBase
    mov  edi, 0                     ; pass 0 = area, pass 1 = line
bh_pass:
    mov  esi, HIST_N
    sub  esi, histCount
bh_pt:
    cmp  esi, HIST_N
    jae  bh_passend
    mov  eax, histHead
    add  eax, esi
    sub  eax, HIST_N
    and  eax, HIST_SIZE - 1
    mov  eax, wpmHist[eax*4]
    mov  edx, 110
    mul  edx
    div  mx
    mov  ebx, 120
    sub  ebx, eax                   ; y
    imul eax, esi, 10               ; x
    invoke AppNum, eax
    invoke AppCh, ','
    invoke AppNum, ebx
    invoke AppCh, ' '
    inc  esi
    jmp  bh_pt
bh_passend:
    test edi, edi
    jnz  bh_lineend
    invoke AppNum, (HIST_N - 1) * 10        ; close the area at the base line
    invoke AppStr, ADDR hBaseEnd
    invoke AppStr, ADDR hPoly2              ; then the line on top
    mov  edi, 1
    jmp  bh_pass
bh_lineend:
    invoke AppStr, ADDR hPolyEnd
bh_svgend:
    invoke AppStr, ADDR hWpmEnd

    ; ---- top 5 table ----
    invoke AppStr, ADDR hTopHead
    xor  esi, esi
bh_top:
    cmp  esi, 5
    jae  bh_topend
    invoke AppStr, ADDR hTrTd
    lea  eax, [esi+1]
    invoke AppNum, eax
    invoke AppStr, ADDR hTdTd
    cmp  esi, top5N
    jae  bh_t1
    invoke KeyName, top5Key[esi*4]
    invoke AppEsc, eax
    invoke AppStr, ADDR hTdNum
    invoke AppNum, top5Cnt[esi*4]
    jmp  bh_t2
bh_t1:
    invoke AppStr, ADDR hTdNum
bh_t2:
    invoke AppStr, ADDR hTdTd
    cmp  esi, bi5N
    jae  bh_t3
    invoke NgramName, bi5Idx[esi*4], 2
    invoke AppStr, eax
    invoke AppStr, ADDR hTdNum
    invoke AppNum, bi5Cnt[esi*4]
    jmp  bh_t4
bh_t3:
    invoke AppStr, ADDR hTdNum
bh_t4:
    invoke AppStr, ADDR hTdTd
    cmp  esi, tri5N
    jae  bh_t5
    invoke NgramName, tri5Idx[esi*4], 3
    invoke AppStr, eax
    invoke AppStr, ADDR hTdNum
    invoke AppNum, tri5Cnt[esi*4]
    jmp  bh_t6
bh_t5:
    invoke AppStr, ADDR hTdNum
bh_t6:
    invoke AppStr, ADDR hTdTrEnd
    inc  esi
    jmp  bh_top
bh_topend:
    invoke AppStr, ADDR hTopEnd

    ; ---- every key pressed ----
    invoke AppStr, ADDR hFreqHead
    xor  esi, esi
bh_fl:
    cmp  freq[esi*4], 0
    je   bh_fnext
    invoke AppStr, ADDR hFreq1
    invoke KeyName, esi
    invoke AppEsc, eax
    invoke AppStr, ADDR hFreq2
    invoke AppNum, freq[esi*4]
    invoke AppStr, ADDR hFreq3
bh_fnext:
    inc  esi
    cmp  esi, 256
    jb   bh_fl
    invoke AppStr, ADDR hFoot
    ret
BuildHtml ENDP

; ---- write a buffer to a file; eax = 1 on success ----
SaveFile PROC USES ebx pName:DWORD, pBuf:DWORD, len:DWORD
    invoke CreateFileA, pName, 40000000h, 0, 0, 2, 80h, 0
    cmp  eax, -1
    je   sf_fail
    mov  ebx, eax
    invoke WriteFile, ebx, pBuf, len, ADDR nWritten, 0
    invoke CloseHandle, ebx
    mov  eax, 1
    ret
sf_fail:
    xor  eax, eax
    ret
SaveFile ENDP

; ---- open KeyReport.html in the default browser (cmd /c start) ----
OpenHtml PROC
    invoke GetEnvironmentVariableA, ADDR sNoBrowser, ADDR envBuf, SIZEOF envBuf
    test eax, eax                   ; KPM_NO_BROWSER set -> just save
    jnz  oh_done
    invoke CreateProcessA, 0, ADDR sOpenCmd, 0, 0, 0, 08000000h, 0, 0, ADDR startInfo, ADDR procInfo
    test eax, eax
    jz   oh_done
    invoke CloseHandle, procInfo
    invoke CloseHandle, procInfo+4
oh_done:
    ret
OpenHtml ENDP

; =============================================================
;  Actions
; =============================================================

; ---- show a temporary status message for MSG_TIME ms ----
SetMsg PROC pMsg:DWORD, clr:DWORD
    mov  eax, pMsg
    mov  msgPtr, eax
    mov  eax, clr
    mov  msgColor, eax
    invoke GetTickCount
    mov  msgTick, eax
    ret
SetMsg ENDP

; ---- clear every counter and buffer ----
DoReset PROC USES edi
    cld
    xor  eax, eax
    lea  edi, freq
    mov  ecx, 256
    rep  stosd
    lea  edi, vkFreq
    mov  ecx, 256
    rep  stosd
    lea  edi, tsRing
    mov  ecx, TS_SIZE
    rep  stosd
    lea  edi, wpmHist
    mov  ecx, HIST_SIZE
    rep  stosd
    lea  edi, bigrams
    mov  ecx, NG2
    rep  stosd
    lea  edi, trigrams
    mov  ecx, NG3
    rep  stosd
    mov  prevL1, -1
    mov  prevL2, -1
    mov  vowels, eax
    mov  consonants, eax
    mov  digits, eax
    mov  spaces, eax
    mov  symbols, eax
    mov  others, eax
    mov  totalKeys, eax
    mov  words, eax
    mov  inWord, eax
    mov  curWordLen, eax
    mov  longestWord, eax
    mov  bsCount, eax
    mov  histHead, eax
    mov  histCount, eax
    mov  cardHead, eax
    mov  cardCount, eax
    mov  lastHead, eax
    mov  lastCount, eax
    mov  tsHead, eax
    mov  tsCount, eax
    mov  wpmPeak, eax
    mov  leftHand, eax
    mov  rightHand, eax
    mov  handAlt, eax
    mov  lastHand, -1
    mov  lastKeyTick, eax
    mov  latSum, eax
    mov  latCnt, eax
    mov  avgLatMs, eax
    mov  minLatMs, eax
    mov  activeMs, eax
    mov  curStreak, eax
    mov  bestStreak, eax
    mov  xpScore, eax
    mov  xpLevel, 1
    mov  badgesMask, eax
    mov  badgeCount, eax
    lea  edi, fingerCnt
    mov  ecx, 9
    rep  stosd
    lea  edi, rowCnt
    mov  ecx, 5
    rep  stosd
    mov  lastLetter, -1
    mov  lastKeyCode, -1
    invoke GetTickCount
    mov  startTick, eax
    mov  lastSample, eax
    invoke SetMsg, ADDR sMsgReset, C_CYAN
    ret
DoReset ENDP

; ---- report builder: append "label,value" for CSV ----
AppCsvRow PROC pLabel:DWORD, val:DWORD
    invoke AppStr, pLabel
    invoke AppCh, ','
    invoke AppNum, val
    invoke AppStr, ADDR crlf
    ret
AppCsvRow ENDP

; ---- assemble KeyReport.csv into rptBuf ----
BuildCsv PROC USES esi
    mov  appBase, OFFSET rptBuf
    mov  rptLen, 0
    invoke AppStr, ADDR csvHdr
    invoke AppCsvRow, ADDR hlTotal, totalKeys
    invoke AppCsvRow, ADDR hlVowels, vowels
    invoke AppCsvRow, ADDR hlCons, consonants
    invoke AppCsvRow, ADDR hlWords, words
    invoke AppCsvRow, ADDR hlPeakW, wpmPeak
    invoke AppCsvRow, ADDR hlAvg, wpmAvg
    invoke AppStr, ADDR csvKeyHdr
    xor  esi, esi
bc_loop:
    cmp  freq[esi*4], 0
    je   bc_next
    invoke AppNum, esi
    invoke AppCh, ','
    invoke KeyName, esi
    invoke AppStr, eax
    invoke AppCh, ','
    invoke AppNum, freq[esi*4]
    invoke AppStr, ADDR crlf
bc_next:
    inc  esi
    cmp  esi, 256
    jb   bc_loop
    ret
BuildCsv ENDP

; ---- assemble KeyReport.json into rptBuf ----
BuildJson PROC
    mov  appBase, OFFSET rptBuf
    mov  rptLen, 0
    invoke AppStr, ADDR jsOpen
    invoke AppNum, totalKeys
    invoke AppStr, ADDR jsVow
    invoke AppNum, vowels
    invoke AppStr, ADDR jsCon
    invoke AppNum, consonants
    invoke AppStr, ADDR jsWds
    invoke AppNum, words
    invoke AppStr, ADDR jsPeak
    invoke AppNum, wpmPeak
    invoke AppStr, ADDR jsAvg
    invoke AppNum, wpmAvg
    invoke AppStr, ADDR jsLat
    invoke AppNum, avgLatMs
    invoke AppStr, ADDR jsStrk
    invoke AppNum, bestStreak
    invoke AppStr, ADDR jsLH
    invoke AppNum, leftHand
    invoke AppStr, ADDR jsRH
    invoke AppNum, rightHand
    invoke AppStr, ADDR jsXP
    invoke AppNum, xpScore
    invoke AppStr, ADDR jsBadges
    invoke AppNum, badgeCount
    invoke AppStr, ADDR jsClose
    ret
BuildJson ENDP

; ---- write KeyReport.txt, .html, .csv and .json; openIt = show HTML in browser ----
DoSave PROC openIt:DWORD
    invoke BuildReport
    invoke SaveFile, ADDR sReportFile, ADDR rptBuf, rptLen
    test eax, eax
    jz   ds_fail
    invoke BuildHtml
    invoke SaveFile, ADDR sHtmlFile, ADDR htmlBuf, rptLen
    test eax, eax
    jz   ds_fail
    invoke BuildCsv
    invoke SaveFile, ADDR sCsvFile, ADDR rptBuf, rptLen
    invoke BuildJson
    invoke SaveFile, ADDR sJsonFile, ADDR rptBuf, rptLen
    invoke BuildReport
    invoke SetMsg, ADDR sMsgSaved, C_OK
    cmp  openIt, 0
    je   ds_done
    invoke OpenHtml
ds_done:
    ret
ds_fail:
    invoke SetMsg, ADDR sMsgFail, C_RED
    ret
DoSave ENDP

; ---- change N by delta, clamped to NMIN..NMAX ----
AdjustN PROC delta:DWORD
    mov  eax, nView
    add  eax, delta
    cmp  eax, NMIN
    jge  an_lo
    mov  eax, NMIN
an_lo:
    cmp  eax, NMAX
    jle  an_hi
    mov  eax, NMAX
an_hi:
    mov  nView, eax
    ret
AdjustN ENDP

; ---- 0 reset, 1 save, 2 pause/resume, 3 quit, 4 autosave on/off, 5 typing test ----
DoAction PROC actId:DWORD
    mov  eax, actId
    cmp  eax, 0
    jne  da_save
    invoke DoReset
    ret
da_save:
    cmp  eax, 1
    jne  da_pause
    invoke DoSave, 1
    ret
da_pause:
    cmp  eax, 2
    jne  da_quit
    xor  paused, 1
    cmp  paused, 0
    je   da_resume
    invoke SetMsg, ADDR sMsgPause, C_GOLD
    ret
da_resume:
    invoke SetMsg, ADDR sMsgResume, C_OK
    ret
da_quit:
    cmp  eax, 3
    jne  da_auto
    mov  quitFlag, 1
    ret
da_auto:
    cmp  eax, 4
    jne  da_view
    xor  autoSave, 1
    cmp  autoSave, 0
    je   da_autooff
    invoke SetMsg, ADDR sMsgAutoOn, C_OK
    ret
da_autooff:
    invoke SetMsg, ADDR sMsgAutoOff, C_RED
    ret
da_view:
    cmp  eax, 5
    jne  da_ergo
    cmp  viewMode, 1
    je   da_to_dash
    mov  viewMode, 1
    invoke SetMsg, ADDR sMsgTest, C_CYAN
    ret
da_ergo:
    cmp  eax, 6
    jne  da_theme
    cmp  viewMode, 2
    je   da_to_dash
    mov  viewMode, 2
    invoke SetMsg, ADDR sMsgErgo, C_CYAN
    ret
da_to_dash:
    mov  viewMode, 0
    invoke SetMsg, ADDR sMsgDash, C_CYAN
    ret
da_theme:
    cmp  eax, 7
    jne  da_sound
    mov  eax, themeIdx
    inc  eax
    and  eax, 3
    mov  themeIdx, eax
    invoke ApplyTheme
    mov  eax, themeIdx
    mov  eax, themeMsgs[eax*4]
    invoke SetMsg, eax, C_GREEN
    ret
da_sound:
    xor  soundOn, 1
    cmp  soundOn, 0
    je   da_sndoff
    invoke SetMsg, ADDR sMsgSndOn, C_OK
    ret
da_sndoff:
    invoke SetMsg, ADDR sMsgSndOff, C_MUTED
    ret
DoAction ENDP

; =============================================================
;  Input
; =============================================================

; ---- process a key event: control keys first, then count the character ----
HandleKey PROC USES ebx esi edi
    cmp  DWORD PTR inRec+4, 0       ; key released -> ignore
    je   hk_done
    movzx ebx, WORD PTR inRec+10    ; virtual key code
    movzx esi, BYTE PTR inRec+14    ; ASCII character
    movzx edi, WORD PTR inRec+8     ; repeat count
    test edi, edi
    jnz  hk_keys
    mov  edi, 1
hk_keys:
    cmp  ebx, VK_ESCAPE
    jne  hk_f1
    mov  quitFlag, 1
    ret
hk_f1:
    cmp  ebx, VK_F1
    jne  hk_f2
    invoke DoAction, 0
    ret
hk_f2:
    cmp  ebx, VK_F2
    jne  hk_f3
    invoke DoAction, 1
    ret
hk_f3:
    cmp  ebx, VK_F3
    jne  hk_f4
    invoke DoAction, 2
    ret
hk_f4:
    cmp  ebx, VK_F4
    jne  hk_f5
    invoke DoAction, 4
    ret
hk_f5:
    cmp  ebx, VK_F5
    jne  hk_f6
    invoke DoAction, 5
    ret
hk_f6:
    cmp  ebx, VK_F6
    jne  hk_f7
    invoke DoAction, 6
    ret
hk_f7:
    cmp  ebx, VK_F7
    jne  hk_f8
    invoke DoAction, 7
    ret
hk_f8:
    cmp  ebx, VK_F8
    jne  hk_tab
    invoke DoAction, 8
    ret
hk_tab:
    cmp  ebx, VK_TAB
    jne  hk_left
    cmp  viewMode, 1
    jne  hk_left
    mov  eax, testMode
    inc  eax
    and  eax, 3
    mov  testMode, eax
    invoke NewTest
    ret
hk_left:
    cmp  ebx, VK_LEFT
    jne  hk_right
    invoke AdjustN, -4
    ret
hk_right:
    cmp  ebx, VK_RIGHT
    jne  hk_char
    invoke AdjustN, 4
    ret
hk_char:
    test esi, esi                   ; Shift, Ctrl, arrows... have no character
    jz   hk_done
    cmp  paused, 0
    jne  hk_done
hk_rep:
    invoke CountChar, esi, ebx
    cmp  viewMode, 0                ; the typing test sees the key too
    je   hk_next
    invoke TestKey, esi
hk_next:
    dec  edi
    jnz  hk_rep
hk_done:
    ret
HandleKey ENDP

; ---- process a mouse event: hover, button clicks, wheel ----
HandleMouse PROC USES ebx
    movsx eax, WORD PTR inRec+4
    sub  eax, offX
    mov  mouseX, eax
    movsx eax, WORD PTR inRec+6
    mov  mouseY, eax

    mov  eax, DWORD PTR inRec+16    ; event flags
    cmp  eax, MOUSE_WHEELED
    jne  hm_click
    mov  eax, DWORD PTR inRec+8     ; high word > 0 means wheel up
    test eax, eax
    js   hm_down
    invoke AdjustN, 4
    ret
hm_down:
    invoke AdjustN, -4
    ret
hm_click:
    cmp  eax, 0
    je   hm_btn
    cmp  eax, DOUBLE_CLICK
    jne  hm_done
hm_btn:
    test DWORD PTR inRec+8, 1       ; left button down?
    jz   hm_done
    cmp  mouseY, BTN_Y
    jne  hm_done
    xor  ebx, ebx
hm_find:
    cmp  ebx, NBTN
    jae  hm_done
    mov  eax, mouseX
    cmp  eax, btnX[ebx*4]
    jl   hm_nextb
    mov  edx, btnX[ebx*4]
    add  edx, btnW[ebx*4]
    cmp  eax, edx
    jge  hm_nextb
    movzx eax, btnAction[ebx]
    invoke DoAction, eax
    ret
hm_nextb:
    inc  ebx
    jmp  hm_find
hm_done:
    ret
HandleMouse ENDP

; =============================================================
;  Console setup / restore
; =============================================================

; ---- configure console input/output, palette, cursor and window size ----
SetupScreen PROC USES esi edi
    mov  DWORD PTR csbiOld, 96
    invoke GetConsoleScreenBufferInfoEx, hOut, ADDR csbiOld
    test eax, eax
    jz   ss_clear
    mov  havePalette, 1

    cld
    lea  esi, csbiOld
    lea  edi, csbiNew
    mov  ecx, 96
    rep  movsb

    movsx eax, WORD PTR csbiOld+18  ; window width
    movsx edx, WORD PTR csbiOld+14
    sub  eax, edx
    inc  eax
    cmp  eax, SCR_W
    jge  ss_w
    mov  eax, SCR_W
ss_w:
    mov  bufW, eax
    movsx eax, WORD PTR csbiOld+20  ; window height
    movsx edx, WORD PTR csbiOld+16
    sub  eax, edx
    inc  eax
    cmp  eax, SCR_H
    jge  ss_h
    mov  eax, SCR_H
ss_h:
    mov  bufH, eax

    ; buffer = window size (no scrollbar). Right/Bottom are written
    ; one larger because SetConsoleScreenBufferInfoEx treats them as
    ; exclusive, while GetConsoleScreenBufferInfoEx returns them inclusive.
    mov  eax, bufW
    mov  WORD PTR csbiNew+4, ax
    mov  WORD PTR csbiNew+18, ax
    mov  eax, bufH
    mov  WORD PTR csbiNew+6, ax
    mov  WORD PTR csbiNew+20, ax
    mov  WORD PTR csbiNew+14, 0
    mov  WORD PTR csbiNew+16, 0
    mov  WORD PTR csbiNew+12, A_PAGE
    lea  esi, palette
    lea  edi, csbiNew+32
    mov  ecx, 16
    rep  movsd
    invoke SetConsoleScreenBufferInfoEx, hOut, ADDR csbiNew
    test eax, eax
    jnz  ss_clear
    mov  havePalette, 0
ss_clear:
    mov  eax, bufW
    sub  eax, SCR_W
    sar  eax, 1
    mov  offX, eax
    mov  eax, bufW
    imul eax, bufH
    invoke FillConsoleOutputCharacterA, hOut, ' ', eax, 0, ADDR nWritten
    mov  eax, bufW
    imul eax, bufH
    invoke FillConsoleOutputAttribute, hOut, A_PAGE, eax, 0, ADDR nWritten
    ret
SetupScreen ENDP

; ---- undo SetupScreen: palette, cursor, code page, input mode ----
RestoreScreen PROC USES ebx
    cmp  vtOK, 0
    je   rs_pal
    mov  vtLen, 0                   ; default colours, clear, show cursor
    invoke EmitA, ADDR vtReset
    invoke WriteConsoleW, hOut, ADDR vtBuf, vtLen, ADDR nWritten, 0
    invoke SetConsoleMode, hOut, oldOutMode
rs_pal:
    cmp  havePalette, 0
    je   rs_rest
    inc  WORD PTR csbiOld+18        ; same inclusive/exclusive fix as above
    inc  WORD PTR csbiOld+20
    invoke SetConsoleScreenBufferInfoEx, hOut, ADDR csbiOld
    movzx ebx, WORD PTR csbiOld+4
    movzx eax, WORD PTR csbiOld+6
    imul ebx, eax
    movzx eax, WORD PTR csbiOld+12
    invoke FillConsoleOutputAttribute, hOut, eax, ebx, 0, ADDR nWritten
    jmp  rs_chars
rs_rest:
    mov  ebx, bufW
    imul ebx, bufH
rs_chars:
    invoke FillConsoleOutputCharacterA, hOut, ' ', ebx, 0, ADDR nWritten
    invoke SetConsoleCursorPosition, hOut, 0
    invoke SetConsoleOutputCP, oldCP
    invoke SetConsoleCursorInfo, hOut, ADDR curOld
    invoke SetConsoleMode, hIn, oldInMode
    ret
RestoreScreen ENDP

; ---- print a zero-terminated string with WriteConsoleA ----
ConPrint PROC pStr:DWORD
    invoke StrLen, pStr
    invoke WriteConsoleA, hOut, pStr, eax, ADDR nWritten, 0
    ret
ConPrint ENDP

; =================== MAIN ===================
start:
    invoke GetStdHandle, STD_INPUT_HANDLE
    mov  hIn, eax
    invoke GetStdHandle, STD_OUTPUT_HANDLE
    mov  hOut, eax
    invoke GetConsoleMode, hIn, ADDR oldInMode
    invoke SetConsoleMode, hIn, IN_MODE
    invoke GetConsoleOutputCP
    mov  oldCP, eax
    invoke SetConsoleOutputCP, 437   ; code page with box-drawing characters
    invoke SetConsoleTitleA, ADDR sWinTitle
    invoke GetConsoleCursorInfo, hOut, ADDR curOld
    mov  eax, curOld
    mov  curNew, eax                 ; same size, but hidden
    invoke SetConsoleCursorInfo, hOut, ADDR curNew
    invoke SetupScreen
    invoke GetConsoleMode, hOut, ADDR oldOutMode     ; true colour through VT sequences
    mov  eax, oldOutMode
    or   eax, VT_OUTPUT
    invoke SetConsoleMode, hOut, eax
    test eax, eax
    jz   noVT
    mov  vtOK, 1
    mov  vtLen, 0
    invoke EmitA, ADDR vtClear
    invoke WriteConsoleW, hOut, ADDR vtBuf, vtLen, ADDR nWritten, 0
noVT:
    invoke GetEnvironmentVariableA, ADDR sWtEnv, ADDR envBuf, SIZEOF envBuf
    test eax, eax
    jz   startClock
    mov  fineGlyphs, 1
startClock:
    invoke GetTickCount
    mov  startTick, eax
    mov  lastSample, eax
    invoke NewTest
    invoke LoadStats
    cmp  hasLast, 0
    je   mainLoop
    invoke SetMsg, ADDR sMsgWelcome, C_CYAN

mainLoop:
    invoke RenderAll
    invoke WaitForSingleObject, hIn, frameWait  ; 250 ms, or 30 ms while animating
    test eax, eax
    jnz  mainLoop
readEvents:
    invoke GetNumberOfConsoleInputEvents, hIn, ADDR nEvents
    cmp  nEvents, 0
    je   mainLoop
    invoke ReadConsoleInputA, hIn, ADDR inRec, 1, ADDR nRead
    cmp  nRead, 0
    je   mainLoop
    movzx eax, WORD PTR inRec
    cmp  eax, KEY_EVENT
    jne  notKey
    invoke HandleKey
    jmp  checkQuit
notKey:
    cmp  eax, MOUSE_EVENT
    jne  readEvents
    invoke HandleMouse
checkQuit:
    cmp  quitFlag, 0
    je   readEvents

    ; ---- quit: save stats, optional autosave, restore the console, print the report ----
    invoke SaveStats
    cmp  autoSave, 0
    je   skipSave
    cmp  totalKeys, 0
    je   skipSave
    invoke DoSave, 0
skipSave:
    invoke BuildReport
    invoke RestoreScreen
    invoke WriteConsoleA, hOut, ADDR rptBuf, rptLen, ADDR nWritten, 0
    invoke ConPrint, ADDR sBye
waitKey:
    invoke ReadConsoleInputA, hIn, ADDR inRec, 1, ADDR nRead
    cmp  WORD PTR inRec, KEY_EVENT
    jne  waitKey
    cmp  DWORD PTR inRec+4, 0
    je   waitKey
    invoke ExitProcess, 0
end start
