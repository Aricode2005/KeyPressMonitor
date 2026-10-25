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
;
;  Keys:  F1 reset   F2 save report   F3 pause   F4 autosave   ESC quit
;         Left / Right arrow (or mouse wheel) change N
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
includelib kernel32.lib

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
NBTN              EQU 5           ; number of buttons
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
C_PAGE      EQU 01A0E0Bh  ; #0B0E1A
C_PANEL     EQU 0291712h  ; #121729
C_BORDER    EQU 052332Ah  ; #2A3352
C_TRACK     EQU 038221Ch  ; #1C2238
C_AXIS      EQU 0452A23h  ; #232A45
C_OFFKEY    EQU 040261Fh  ; #1F2640
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
C_HDR1      EQU 04B1B1Eh  ; #1E1B4B
C_HDR2      EQU 0B6215Bh  ; #5B21B6
C_HDRTXT    EQU 0FED2C7h  ; #C7D2FE

.data
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
sBN0         DB " Reset ", 0
sBN1         DB " Save report ", 0
sBN2         DB " Pause ", 0
sBN2R        DB " Resume ", 0
sBN3         DB " Autosave off ", 0
sBN3On       DB " Autosave on ", 0
sBN4         DB " Quit ", 0
btnKeys      DD OFFSET sBK0, OFFSET sBK1, OFFSET sBK2, OFFSET sBK3, OFFSET sBK4
btnNames     DD OFFSET sBN0, OFFSET sBN1, OFFSET sBN2, OFFSET sBN3, OFFSET sBN4
btnColors    DD C_BLUE, C_BLUE, C_BLUE, C_BLUE, C_RED
btnAction    DB 0, 1, 2, 4, 3
sHint        DB "Mouse: click the buttons  ", 0FAh, "  <- -> or wheel: resize N  ", 0FAh
             DB "  keys are counted only while LIVE", 0
sMsgReset    DB 0FBh, " Counters reset", 0
sMsgSaved    DB 0FBh, " Report saved to KeyReport.txt", 0
sMsgFail     DB "x Could not write KeyReport.txt", 0
sMsgPause    DB "|| Paused - typing is not counted", 0
sMsgResume   DB 0FBh, " Live again", 0
sReportFile  DB "KeyReport.txt", 0
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

; ---- count one typed character (kc = ASCII, vk = virtual key) ----
CountChar PROC USES ebx kc:DWORD, vk:DWORD
    mov  ebx, kc
    and  ebx, 0FFh
    inc  totalKeys
    inc  freq[ebx*4]                ; requirement (b)
    mov  eax, vk
    and  eax, 0FFh
    inc  vkFreq[eax*4]
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

    invoke Card, 2, ADDR sCardV, vowels, C_GREEN, C_GREEN2, ADDR cardV, CARD_MASK, cardHead, cardCount
    invoke Percent, vowels, ebx
    invoke Num, 4, 6, eax, C_GREEN
    invoke Text, eax, 6, ADDR sPctLetters, C_MUTED, C_KEEP

    invoke Card, 26, ADDR sCardC, consonants, C_AMBER, C_AMBER2, ADDR cardC, CARD_MASK, cardHead, cardCount
    invoke Percent, consonants, ebx
    invoke Num, 28, 6, eax, C_AMBER
    invoke Text, eax, 6, ADDR sPctLetters, C_MUTED, C_KEEP

    invoke Card, 50, ADDR sCardT, totalKeys, C_CYAN, C_CYAN2, ADDR cardT, CARD_MASK, cardHead, cardCount
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
    jne  bt_size
    cmp  autoSave, 0
    je   bt_size
    mov  pName, OFFSET sBN3On
    mov  col, C_GREEN2
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

; ---- redraw every panel into the canvas, then flush once ----
RenderAll PROC
    invoke UpdateStats
    invoke Fill, 0, 0, SCR_W, SCR_H, ' ', C_TEXT, C_PAGE
    invoke DrawHeader
    invoke DrawCards
    invoke DrawChips
    invoke DrawLastN
    invoke DrawHistogram
    invoke DrawHeatmap
    invoke DrawRanks
    invoke DrawWpmHistory
    invoke DrawStatsLine
    invoke DrawButtons
    invoke Flush
    ret
RenderAll ENDP

; =============================================================
;  Report (F2 saves it, ESC prints it)
; =============================================================

; ---- report builder: append a zero-terminated string ----
AppStr PROC USES esi edi pStr:DWORD
    mov  esi, pStr
    mov  edi, OFFSET rptBuf
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
    sub  edi, OFFSET rptBuf
    mov  rptLen, edi
    ret
AppStr ENDP

; ---- report builder: append one character ----
AppCh PROC chv:DWORD
    mov  edx, rptLen
    mov  eax, chv
    mov  rptBuf[edx], al
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
    mov  lastLetter, -1
    mov  lastKeyCode, -1
    invoke GetTickCount
    mov  startTick, eax
    mov  lastSample, eax
    invoke SetMsg, ADDR sMsgReset, C_CYAN
    ret
DoReset ENDP

; ---- write the report to KeyReport.txt ----
DoSave PROC USES ebx
    invoke BuildReport
    invoke CreateFileA, ADDR sReportFile, 40000000h, 0, 0, 2, 80h, 0
    cmp  eax, -1
    je   ds_fail
    mov  ebx, eax
    invoke WriteFile, ebx, ADDR rptBuf, rptLen, ADDR nWritten, 0
    invoke CloseHandle, ebx
    invoke SetMsg, ADDR sMsgSaved, C_OK
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

; ---- 0 reset, 1 save, 2 pause/resume, 3 quit, 4 autosave on/off ----
DoAction PROC actId:DWORD
    mov  eax, actId
    cmp  eax, 0
    jne  da_save
    invoke DoReset
    ret
da_save:
    cmp  eax, 1
    jne  da_pause
    invoke DoSave
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
    xor  autoSave, 1
    cmp  autoSave, 0
    je   da_autooff
    invoke SetMsg, ADDR sMsgAutoOn, C_OK
    ret
da_autooff:
    invoke SetMsg, ADDR sMsgAutoOff, C_RED
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
    jne  hk_left
    invoke DoAction, 4
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

mainLoop:
    invoke RenderAll
    invoke WaitForSingleObject, hIn, 250    ; redraw at least 4x a second
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

    ; ---- quit: optional autosave, restore the console, print the report ----
    cmp  autoSave, 0
    je   skipSave
    cmp  totalKeys, 0
    je   skipSave
    invoke DoSave
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
