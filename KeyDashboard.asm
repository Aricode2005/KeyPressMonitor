; =============================================================
;  KeyDashboard.asm  -  Real-time Key Press Monitor with a live
;                       full-screen dashboard (MASM, 32-bit)
;
;  Required features:
;   1. Counts vowels and consonants typed
;   2. Keeps frequency of every key pressed (ASCII 0-255)
;   3. Shows the last N characters typed (buffered view)
;
;  Extra features:
;   4. Full-screen colour dashboard, drawn off-screen and copied
;      in one WriteConsoleOutputA call (no flicker), custom palette
;   5. Live A-Z letter histogram (vowels green, consonants amber)
;   6. Keyboard heatmap - QWERTY keys coloured by how often used
;   7. Typing speed: live WPM, peak WPM, average WPM, session timer
;   8. Top-5 most used keys + digit / space / symbol counters
;   9. Mouse-clickable buttons, adjustable N, pause, save report
;
;  Keys:  F1 reset   F2 save report   F3 pause   ESC quit
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
WriteConsoleOutputA           PROTO :DWORD, :DWORD, :DWORD, :DWORD, :DWORD
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

SCR_W             EQU 100         ; dashboard size in character cells
SCR_H             EQU 30
NMAX              EQU 64          ; largest N (power of two -> wrap with AND)
NMIN              EQU 8
TS_SIZE           EQU 128         ; key timestamps kept for WPM
WPM_WINDOW        EQU 5000        ; WPM measured over the last 5 seconds
MSG_TIME          EQU 3000        ; status message shown for 3 seconds
BTN_Y             EQU 27          ; row of the button bar

CAT_VOWEL         EQU 1
CAT_CONS          EQU 2
CAT_DIGIT         EQU 3
CAT_SPACE         EQU 4
CAT_SYM           EQU 5
CAT_OTHER         EQU 6

; ---------- colour attributes (foreground + background*16) ----------
; palette index: 0 page  1 panel  2 green  3 cyan  4 red  5 purple
;                6 amber 7 text   8 muted  9 blue  11 header  12 orange
;                14 yellow 15 white
A_PAGE            EQU 07h
A_MUTED_PG        EQU 08h
A_PANEL           EQU 17h
A_PANEL_HI        EQU 1Fh
A_BORDER          EQU 18h
A_VOWEL           EQU 12h
A_CONS            EQU 16h
A_CYAN            EQU 13h
A_PURPLE          EQU 15h
A_NEWEST          EQU 30h
A_HDR             EQU 0B7h
A_HDR_HI          EQU 0BFh
A_HDR_ACC         EQU 0B3h
A_HDR_OK          EQU 0B2h
A_HDR_WARN        EQU 0BEh
A_BTN             EQU 9Fh
A_BTN_HOT         EQU 30h
A_BTN_QUIT        EQU 4Fh
A_BTN_QHOT        EQU 0C0h
A_BTN_PAUSED      EQU 0E0h

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

; ---- statistics ----
vowels       DD 0
consonants   DD 0
digits       DD 0
spaces       DD 0
symbols      DD 0
others       DD 0
totalKeys    DD 0
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

paused       DD 0
quitFlag     DD 0
mouseX       DD -1
mouseY       DD -1
btnX         DD 4 DUP(0)
btnW         DD 4 DUP(0)
msgPtr       DD 0
msgTick      DD 0
msgAttr      DD 0

nEvents      DD 0
nRead        DD 0
nWritten     DD 0
inRec        DB 20 DUP(0)         ; INPUT_RECORD
numBuf       DB 16 DUP(0)
keyNameBuf   DB 4 DUP(0)
rptLen       DD 0

; ---- custom colour theme (COLORREF = 00BBGGRRh) ----
palette      DD 0020100Dh, 002E1B16h, 0099D334h, 00EED322h
             DD 005E3FF4h, 00FA8BA7h, 000B9EF5h, 00E1D5CBh
             DD 0088675Bh, 00F6823Bh, 0081B910h, 00552A1Eh
             DD 003C92FBh, 009948ECh, 0015CCFAh, 00FCFAF8h

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

heatAttrs    DB 08h, 9Fh, 30h, 20h, 0E0h, 4Fh   ; cold -> hot
rankAttrs    DB 1Eh, 1Fh, 1Ch, 18h, 18h         ; gold, silver, bronze

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
sCardW       DB " SPEED  WPM ", 0
sPctLetters  DB "% of letters", 0
sKeysSession DB "keys this session", 0
sPeak        DB "peak ", 0
sAvg         DB "   avg ", 0
sDigits      DB "DIGITS ", 0
sSpaces      DB "SPACES ", 0
sSymbols     DB "SYMBOLS ", 0
sOther       DB "OTHER ", 0
sBoxLast     DB " LAST N CHARACTERS ", 0
sNEq         DB " N = ", 0
sNHint       DB "  (<- ->  or mouse wheel) ", 0
sLastKey     DB "LAST KEY ", 0
sAscii       DB "  ASCII ", 0
sBoxHist     DB " LETTER FREQUENCY  A-Z ", 0
sVowel       DB "vowel", 0
sConsonant   DB "consonant", 0
sMax         DB "max ", 0
sBoxHeat     DB " KEYBOARD HEATMAP ", 0
sSpace       DB "SPACE", 0
sCold        DB " cold ", 0
sHot         DB " hot ", 0
sBoxTop      DB " TOP 5 KEYS ", 0
sDash        DB "-", 0
sBtn0        DB " F1  RESET ", 0
sBtn1        DB " F2  SAVE REPORT ", 0
sBtn2        DB " F3  PAUSE ", 0
sBtnResume   DB " F3  RESUME ", 0
sBtn3        DB " ESC  QUIT ", 0
btnLabels    DD OFFSET sBtn0, OFFSET sBtn1, OFFSET sBtn2, OFFSET sBtn3
btnAttrs     DB A_BTN, A_BTN, A_BTN, A_BTN_QUIT
btnHot       DB A_BTN_HOT, A_BTN_HOT, A_BTN_HOT, A_BTN_QHOT
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

; ---- report text (saved with F2 and printed on exit) ----
rpTitle      DB 13, 10, "========== KEY PRESS MONITOR - REPORT ==========", 13, 10, 0
rpTotal      DB "Total keys       : ", 0
rpVow        DB "Total Vowels     : ", 0
rpCon        DB "Total Consonants : ", 0
rpDig        DB "Digits           : ", 0
rpSpc        DB "Spaces           : ", 0
rpSym        DB "Symbols          : ", 0
rpOth        DB "Other keys       : ", 0
rpPeak       DB "Peak WPM         : ", 0
rpAvg        DB "Average WPM      : ", 0
rpTime       DB "Session time     : ", 0
rpLast       DB "Last N chars     : [", 0
rpLastEnd    DB "]", 13, 10, 0
rpTop        DB 13, 10, "Top 5 keys:", 13, 10, 0
rpFreq       DB 13, 10, "Key Frequency:", 13, 10, 0
rpIndent     DB "  ", 0
rpDot        DB ".  ", 0
rpAsciiTxt   DB "(ASCII ", 0
rpArrow      DB ")  ->  ", 0
rpTimes      DB " x ", 0
crlf         DB 13, 10, 0
sBye         DB 13, 10, "Press any key to exit...", 0

.data?
canvas       DD SCR_W * SCR_H DUP(?)   ; CHAR_INFO cells: char (low word), attr (high word)
csbiOld      DB 96 DUP(?)              ; CONSOLE_SCREEN_BUFFER_INFOEX
csbiNew      DB 96 DUP(?)
rptBuf       DB 16384 DUP(?)

.code

; =============================================================
;  Canvas primitives - everything is drawn into 'canvas' first
; =============================================================

; ---- put one character with colour (clipped to the canvas) ----
PutCh PROC px:DWORD, py:DWORD, chv:DWORD, attr:DWORD
    mov  eax, px
    cmp  eax, SCR_W
    jae  pc_done
    mov  edx, py
    cmp  edx, SCR_H
    jae  pc_done
    imul edx, edx, SCR_W
    add  edx, eax
    mov  eax, attr
    shl  eax, 16
    mov  ecx, chv
    and  ecx, 0FFh
    or   eax, ecx
    mov  canvas[edx*4], eax
pc_done:
    ret
PutCh ENDP

; ---- fill a rectangle with one character / colour ----
FillRect PROC USES ebx esi px:DWORD, py:DWORD, wd:DWORD, ht:DWORD, chv:DWORD, attr:DWORD
    xor  esi, esi
fr_row:
    cmp  esi, ht
    jae  fr_done
    xor  ebx, ebx
fr_col:
    cmp  ebx, wd
    jae  fr_next
    mov  eax, px
    add  eax, ebx
    mov  edx, py
    add  edx, esi
    invoke PutCh, eax, edx, chv, attr
    inc  ebx
    jmp  fr_col
fr_next:
    inc  esi
    jmp  fr_row
fr_done:
    ret
FillRect ENDP

; ---- put zero-terminated string; returns eax = x after the text ----
PutStr PROC USES ebx esi px:DWORD, py:DWORD, pStr:DWORD, attr:DWORD
    mov  esi, pStr
    mov  ebx, px
ps_loop:
    movzx eax, BYTE PTR [esi]
    test eax, eax
    jz   ps_done
    invoke PutCh, ebx, py, eax, attr
    inc  esi
    inc  ebx
    jmp  ps_loop
ps_done:
    mov  eax, ebx
    ret
PutStr ENDP

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
PutNum PROC px:DWORD, py:DWORD, val:DWORD, attr:DWORD
    invoke NumToStr, val
    invoke PutStr, px, py, eax, attr
    ret
PutNum ENDP

; ---- number, right aligned so its last digit is at column pxr ----
PutNumR PROC pxr:DWORD, py:DWORD, val:DWORD, attr:DWORD
    invoke NumToStr, val
    mov  edx, pxr
    sub  edx, ecx
    inc  edx
    invoke PutStr, edx, py, eax, attr
    ret
PutNumR ENDP

; ---- two digits with leading zero (0-99) ----
Put2 PROC px:DWORD, py:DWORD, val:DWORD, attr:DWORD
    mov  eax, val
    xor  edx, edx
    mov  ecx, 10
    div  ecx
    push edx
    add  eax, '0'
    invoke PutCh, px, py, eax, attr
    pop  edx
    add  edx, '0'
    mov  eax, px
    inc  eax
    invoke PutCh, eax, py, edx, attr
    ret
Put2 ENDP

; ---- seconds as mm:ss ----
PutTime PROC px:DWORD, py:DWORD, secs:DWORD, attr:DWORD
    mov  eax, secs
    xor  edx, edx
    mov  ecx, 60
    div  ecx
    cmp  eax, 99
    jbe  pt_ok
    mov  eax, 99
pt_ok:
    push edx
    invoke Put2, px, py, eax, attr
    mov  eax, px
    add  eax, 2
    invoke PutCh, eax, py, ':', attr
    pop  edx
    mov  eax, px
    add  eax, 3
    invoke Put2, eax, py, edx, attr
    ret
PutTime ENDP

; ---- panel with a single-line border and a title in the top edge ----
DrawBox PROC USES ebx esi edi px:DWORD, py:DWORD, wd:DWORD, ht:DWORD, pTitle:DWORD, battr:DWORD, tattr:DWORD
    invoke FillRect, px, py, wd, ht, ' ', A_PANEL
    mov  esi, px
    add  esi, wd
    dec  esi                      ; esi = right column
    mov  edi, py
    add  edi, ht
    dec  edi                      ; edi = bottom row
    mov  ebx, px
box_h:
    cmp  ebx, esi
    ja   box_v0
    invoke PutCh, ebx, py, 0C4h, battr
    invoke PutCh, ebx, edi, 0C4h, battr
    inc  ebx
    jmp  box_h
box_v0:
    mov  ebx, py
box_v:
    cmp  ebx, edi
    ja   box_c
    invoke PutCh, px, ebx, 0B3h, battr
    invoke PutCh, esi, ebx, 0B3h, battr
    inc  ebx
    jmp  box_v
box_c:
    invoke PutCh, px, py, 0DAh, battr
    invoke PutCh, esi, py, 0BFh, battr
    invoke PutCh, px, edi, 0C0h, battr
    invoke PutCh, esi, edi, 0D9h, battr
    cmp  pTitle, 0
    je   box_done
    mov  eax, px
    add  eax, 2
    invoke PutStr, eax, py, pTitle, tattr
box_done:
    ret
DrawBox ENDP

; ---- big 3-row number using the block font ----
BigNum PROC USES ebx esi edi px:DWORD, py:DWORD, val:DWORD, attr:DWORD
    LOCAL row:DWORD, col:DWORD
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
    mov  col, 0
bn_col:
    movzx eax, BYTE PTR [edi]
    mov  ecx, ebx
    add  ecx, col
    mov  edx, py
    add  edx, row
    invoke PutCh, ecx, edx, eax, attr
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

; ---- copy the finished canvas to the console in one call ----
Flush PROC
    mov  eax, offX
    mov  writeRegion, ax
    mov  writeRegion+2, 0
    add  eax, SCR_W - 1
    mov  writeRegion+4, ax
    mov  writeRegion+6, SCR_H - 1
    invoke WriteConsoleOutputA, hOut, ADDR canvas, (SCR_H SHL 16) OR SCR_W, 0, ADDR writeRegion
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

    invoke Classify, ebx            ; requirement (a)
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

cc_glyph:                           ; character shown in the last-N view
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
ComputeTop5 PROC USES ebx esi edi
    xor  ebx, ebx                   ; ebx = rank being filled
t5_rank:
    cmp  ebx, 5
    jae  t5_done
    mov  edi, -1                    ; best key so far
    xor  edx, edx                   ; best count so far
    xor  esi, esi
t5_scan:
    mov  eax, freq[esi*4]
    cmp  eax, edx
    jbe  t5_next
    xor  ecx, ecx                   ; already picked?
t5_check:
    cmp  ecx, ebx
    jae  t5_take
    cmp  top5Key[ecx*4], esi
    je   t5_next
    inc  ecx
    jmp  t5_check
t5_take:
    mov  edi, esi
    mov  edx, eax
t5_next:
    inc  esi
    cmp  esi, 256
    jb   t5_scan
    cmp  edi, -1
    je   t5_done
    mov  top5Key[ebx*4], edi
    mov  top5Cnt[ebx*4], edx
    inc  ebx
    jmp  t5_rank
t5_done:
    mov  top5N, ebx
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
us_top:
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

; =============================================================
;  Dashboard sections
; =============================================================

DrawHeader PROC
    invoke FillRect, 0, 0, SCR_W, 1, ' ', A_HDR
    invoke PutCh, 2, 0, 0FEh, A_HDR_ACC
    invoke PutStr, 4, 0, ADDR sTitle, A_HDR_HI
    invoke PutStr, 23, 0, ADDR sSubtitle, A_HDR
    cmp  paused, 0
    je   dh_live
    invoke PutCh, 74, 0, 0FEh, A_HDR_WARN
    invoke PutStr, 76, 0, ADDR sPaused, A_HDR_WARN
    jmp  dh_time
dh_live:
    mov  eax, A_HDR_OK              ; blinking dot
    test nowTick, 512
    jz   dh_dot
    mov  eax, A_HDR
dh_dot:
    invoke PutCh, 74, 0, 0FEh, eax
    invoke PutStr, 76, 0, ADDR sLive, A_HDR_OK
dh_time:
    invoke PutStr, 86, 0, ADDR sTime, A_HDR
    invoke PutTime, 91, 0, elapsedSec, A_HDR_HI
    ret
DrawHeader ENDP

DrawCards PROC USES ebx
    mov  ebx, vowels
    add  ebx, consonants            ; ebx = letters typed

    invoke DrawBox, 2, 2, 23, 6, ADDR sCardV, A_VOWEL, A_PANEL_HI
    invoke BigNum, 4, 3, vowels, A_VOWEL
    invoke Percent, vowels, ebx
    invoke PutNum, 4, 6, eax, A_VOWEL
    invoke PutStr, eax, 6, ADDR sPctLetters, A_BORDER

    invoke DrawBox, 26, 2, 23, 6, ADDR sCardC, A_CONS, A_PANEL_HI
    invoke BigNum, 28, 3, consonants, A_CONS
    invoke Percent, consonants, ebx
    invoke PutNum, 28, 6, eax, A_CONS
    invoke PutStr, eax, 6, ADDR sPctLetters, A_BORDER

    invoke DrawBox, 50, 2, 23, 6, ADDR sCardT, A_CYAN, A_PANEL_HI
    invoke BigNum, 52, 3, totalKeys, A_CYAN
    invoke PutStr, 52, 6, ADDR sKeysSession, A_BORDER

    invoke DrawBox, 74, 2, 23, 6, ADDR sCardW, A_PURPLE, A_PANEL_HI
    invoke BigNum, 76, 3, wpmNow, A_PURPLE
    invoke PutStr, 76, 6, ADDR sPeak, A_BORDER
    invoke PutNum, eax, 6, wpmPeak, A_PANEL_HI
    invoke PutStr, eax, 6, ADDR sAvg, A_BORDER
    invoke PutNum, eax, 6, wpmAvg, A_PANEL_HI
    ret
DrawCards ENDP

; ---- small "pill" counter on row 8; returns eax = next x ----
Chip PROC USES ebx px:DWORD, pLabel:DWORD, val:DWORD, attr:DWORD
    invoke PutCh, px, 8, ' ', A_PANEL
    mov  eax, px
    inc  eax
    invoke PutStr, eax, 8, pLabel, A_BORDER
    invoke PutNum, eax, 8, val, attr
    mov  ebx, eax
    invoke PutCh, ebx, 8, ' ', A_PANEL
    lea  eax, [ebx+2]
    ret
Chip ENDP

DrawChips PROC USES ebx esi
    invoke Chip, 2, ADDR sDigits, digits, A_CYAN
    invoke Chip, eax, ADDR sSpaces, spaces, A_PANEL_HI
    invoke Chip, eax, ADDR sSymbols, symbols, A_PURPLE
    invoke Chip, eax, ADDR sOther, others, A_PANEL_HI

    ; vowel / consonant mix bar (columns 62-94)
    invoke PutCh, 60, 8, 'V', 02h
    invoke PutCh, 96, 8, 'C', 06h
    mov  ecx, vowels
    add  ecx, consonants
    test ecx, ecx
    jnz  dc_bar
    invoke FillRect, 62, 8, 33, 1, 0B0h, A_MUTED_PG
    ret
dc_bar:
    mov  eax, vowels
    mov  edx, 33
    mul  edx
    div  ecx
    mov  ebx, eax                   ; vowel part length
    invoke FillRect, 62, 8, ebx, 1, 0DBh, 02h
    mov  esi, 33
    sub  esi, ebx
    lea  eax, [ebx+62]
    invoke FillRect, eax, 8, esi, 1, 0DBh, 06h
    ret
DrawChips ENDP

DrawLastN PROC USES ebx esi edi
    LOCAL show:DWORD, firstIdx:DWORD
    invoke DrawBox, 2, 9, 96, 3, ADDR sBoxLast, A_BORDER, A_PANEL_HI
    invoke PutStr, 24, 9, ADDR sNEq, A_PANEL_HI
    invoke PutNum, eax, 9, nView, A_CYAN
    invoke PutStr, eax, 9, ADDR sNHint, A_BORDER

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
    movzx edi, lastRing[eax]
    mov  eax, show                  ; age 0 = newest
    dec  eax
    sub  eax, esi
    mov  ecx, A_NEWEST
    test eax, eax
    jz   ln_put
    mov  ecx, A_PANEL_HI
    cmp  eax, 8
    jb   ln_put
    mov  ecx, A_PANEL
    mov  edx, nView
    shr  edx, 1
    cmp  eax, edx
    jb   ln_put
    mov  ecx, A_BORDER
ln_put:
    lea  eax, [esi+4]
    invoke PutCh, eax, 10, edi, ecx
    inc  esi
    jmp  ln_loop
ln_empty:                           ; free slots shown as dots
    cmp  esi, nView
    jae  ln_cursor
    lea  eax, [esi+4]
    invoke PutCh, eax, 10, 0FAh, A_BORDER
    inc  esi
    jmp  ln_empty
ln_cursor:
    mov  eax, show
    cmp  eax, nView
    jae  ln_key
    test nowTick, 512
    jnz  ln_key
    add  eax, 4
    invoke PutCh, eax, 10, 0DDh, A_CYAN

ln_key:
    invoke PutStr, 70, 10, ADDR sLastKey, A_BORDER
    cmp  lastKeyCode, -1
    jne  ln_has
    invoke PutStr, eax, 10, ADDR sDash, A_BORDER
    ret
ln_has:
    mov  ebx, eax
    invoke KeyName, lastKeyCode
    invoke PutStr, ebx, 10, eax, A_PANEL_HI
    invoke PutStr, eax, 10, ADDR sAscii, A_BORDER
    invoke PutNum, eax, 10, lastKeyCode, A_CYAN
    ret
DrawLastN ENDP

DrawHistogram PROC USES ebx esi edi
    LOCAL maxL:DWORD, realMax:DWORD, cnt:DWORD, hh:DWORD, col:DWORD, attr:DWORD, lattr:DWORD
    invoke DrawBox, 2, 12, 56, 14, ADDR sBoxHist, A_BORDER, A_PANEL_HI
    invoke PutCh, 4, 13, 0FEh, A_VOWEL
    invoke PutStr, 6, 13, ADDR sVowel, A_PANEL
    invoke PutCh, 13, 13, 0FEh, A_CONS
    invoke PutStr, 15, 13, ADDR sConsonant, A_PANEL

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
    invoke PutStr, 47, 13, ADDR sMax, A_BORDER
    invoke PutNum, eax, 13, realMax, A_PANEL_HI

    invoke FillRect, 4, 23, 52, 1, 0C4h, A_BORDER

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
    mov  attr, A_CONS
    cmp  eax, CAT_VOWEL
    jne  hg_lbl
    mov  attr, A_VOWEL
hg_lbl:
    mov  lattr, A_PANEL_HI
    cmp  cnt, 0
    jne  hg_l1
    mov  lattr, A_BORDER
hg_l1:
    cmp  esi, lastLetter
    jne  hg_l2
    mov  lattr, A_NEWEST
hg_l2:
    mov  eax, esi
    add  eax, 'A'
    invoke PutCh, col, 24, eax, lattr

    cmp  cnt, 0
    je   hg_next
    mov  eax, cnt                   ; bar height in half rows (1-18)
    mov  edx, 18
    mul  edx
    add  eax, maxL
    dec  eax
    div  maxL
    mov  hh, eax

    xor  edi, edi                   ; edi = row from the bottom
hg_bar:
    cmp  edi, 9
    jae  hg_next
    mov  eax, edi
    shl  eax, 1
    mov  edx, hh
    sub  edx, eax
    jle  hg_next
    mov  ecx, 0DBh                  ; full block
    cmp  edx, 1
    jne  hg_draw
    mov  ecx, 0DCh                  ; half block on top
hg_draw:
    mov  eax, 22
    sub  eax, edi
    invoke PutCh, col, eax, ecx, attr
    inc  edi
    jmp  hg_bar
hg_next:
    inc  esi
    cmp  esi, 26
    jb   hg_col
    ret
DrawHistogram ENDP

; ---- colour for a key in the heatmap, from cold to hot ----
HeatAttr PROC cnt:DWORD
    mov  eax, cnt
    test eax, eax
    jz   ha_pick
    mov  edx, 5                     ; level = ceil(cnt * 5 / max)
    mul  edx
    add  eax, heatMax
    adc  edx, 0
    sub  eax, 1
    sbb  edx, 0
    div  heatMax
    cmp  eax, 5
    jbe  ha_pick
    mov  eax, 5
ha_pick:
    movzx eax, heatAttrs[eax]
    ret
HeatAttr ENDP

DrawHeatmap PROC USES ebx esi edi
    LOCAL rowI:DWORD, kx:DWORD, ky:DWORD, pVk:DWORD
    invoke DrawBox, 59, 12, 39, 7, ADDR sBoxHeat, A_BORDER, A_PANEL_HI

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
    invoke HeatAttr, vkFreq[eax*4]
    mov  ebx, eax
    invoke PutCh, kx, ky, edi, ebx
    mov  eax, kx
    inc  eax
    invoke PutCh, eax, ky, ' ', ebx
    add  kx, 3
    inc  esi
    inc  pVk
    jmp  hm_key
hm_nextrow:
    inc  rowI
    cmp  rowI, 4
    jb   hm_row

    invoke HeatAttr, vkFreq[20h*4]  ; space bar
    mov  ebx, eax
    invoke FillRect, 66, 17, 20, 1, ' ', ebx
    invoke PutStr, 73, 17, ADDR sSpace, ebx

    invoke PutStr, 68, 18, ADDR sCold, A_BORDER   ; legend in the bottom edge
    mov  esi, 1
    mov  edi, 74
hm_leg:
    movzx ebx, heatAttrs[esi]
    invoke PutCh, edi, 18, ' ', ebx
    inc  edi
    invoke PutCh, edi, 18, ' ', ebx
    inc  edi
    inc  esi
    cmp  esi, 6
    jb   hm_leg
    invoke PutStr, edi, 18, ADDR sHot, A_BORDER
    ret
DrawHeatmap ENDP

DrawTop5 PROC USES ebx esi edi
    LOCAL ky:DWORD, barLen:DWORD, attr:DWORD
    invoke DrawBox, 59, 19, 39, 7, ADDR sBoxTop, A_BORDER, A_PANEL_HI
    xor  esi, esi
tp_loop:
    cmp  esi, 5
    jae  tp_done
    lea  eax, [esi+20]
    mov  ky, eax
    movzx ecx, rankAttrs[esi]
    lea  eax, [esi+'1']
    invoke PutCh, 61, ky, eax, ecx
    cmp  esi, top5N
    jae  tp_empty

    mov  ebx, top5Key[esi*4]
    invoke KeyName, ebx
    invoke PutStr, 64, ky, eax, A_PANEL_HI
    invoke Classify, ebx
    mov  attr, A_CYAN
    cmp  eax, CAT_VOWEL
    jne  tp_c1
    mov  attr, A_VOWEL
tp_c1:
    cmp  eax, CAT_CONS
    jne  tp_c2
    mov  attr, A_CONS
tp_c2:
    mov  eax, top5Cnt[esi*4]        ; bar length scaled to the #1 key
    mov  edx, 18
    mul  edx
    div  top5Cnt
    cmp  eax, 1
    jae  tp_len
    mov  eax, 1
tp_len:
    mov  barLen, eax
    invoke FillRect, 69, ky, 18, 1, 0B0h, A_BORDER
    invoke FillRect, 69, ky, barLen, 1, 0DBh, attr
    invoke PutNumR, 91, ky, top5Cnt[esi*4], A_PANEL_HI
    invoke Percent, top5Cnt[esi*4], totalKeys
    invoke PutNumR, 95, ky, eax, A_BORDER
    invoke PutCh, 96, ky, '%', A_BORDER
    jmp  tp_next
tp_empty:
    invoke PutStr, 64, ky, ADDR sDash, A_BORDER
tp_next:
    inc  esi
    jmp  tp_loop
tp_done:
    ret
DrawTop5 ENDP

DrawButtons PROC USES ebx esi edi
    LOCAL blen:DWORD, battr:DWORD
    mov  ebx, 2                     ; x of the next button
    xor  esi, esi
bt_loop:
    cmp  esi, 4
    jae  bt_msg
    mov  edi, btnLabels[esi*4]
    movzx eax, btnAttrs[esi]
    mov  battr, eax
    cmp  esi, 2
    jne  bt_len
    cmp  paused, 0
    je   bt_len
    mov  edi, OFFSET sBtnResume
    mov  battr, A_BTN_PAUSED
bt_len:
    invoke StrLen, edi
    mov  blen, eax
    mov  btnX[esi*4], ebx
    mov  btnW[esi*4], eax

    cmp  mouseY, BTN_Y              ; mouse hovering this button?
    jne  bt_draw
    mov  eax, mouseX
    cmp  eax, ebx
    jl   bt_draw
    mov  edx, ebx
    add  edx, blen
    cmp  eax, edx
    jge  bt_draw
    movzx eax, btnHot[esi]
    mov  battr, eax
bt_draw:
    invoke FillRect, ebx, BTN_Y, blen, 1, ' ', battr
    invoke PutStr, ebx, BTN_Y, edi, battr
    add  ebx, blen
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
    invoke PutStr, 64, BTN_Y, msgPtr, msgAttr
bt_hint:
    invoke PutStr, 2, 28, ADDR sHint, A_MUTED_PG
    ret
DrawButtons ENDP

RenderAll PROC
    invoke UpdateStats
    invoke FillRect, 0, 0, SCR_W, SCR_H, ' ', A_PAGE
    invoke DrawHeader
    invoke DrawCards
    invoke DrawChips
    invoke DrawLastN
    invoke DrawHistogram
    invoke DrawHeatmap
    invoke DrawTop5
    invoke DrawButtons
    invoke Flush
    ret
RenderAll ENDP

; =============================================================
;  Report (F2 saves it, ESC prints it)
; =============================================================

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

AppCh PROC chv:DWORD
    mov  edx, rptLen
    mov  eax, chv
    mov  rptBuf[edx], al
    inc  rptLen
    ret
AppCh ENDP

AppNum PROC val:DWORD
    invoke NumToStr, val
    invoke AppStr, eax
    ret
AppNum ENDP

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

br_freq:                            ; full frequency table
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

SetMsg PROC pMsg:DWORD, attr:DWORD
    mov  eax, pMsg
    mov  msgPtr, eax
    mov  eax, attr
    mov  msgAttr, eax
    invoke GetTickCount
    mov  msgTick, eax
    ret
SetMsg ENDP

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
    mov  vowels, eax
    mov  consonants, eax
    mov  digits, eax
    mov  spaces, eax
    mov  symbols, eax
    mov  others, eax
    mov  totalKeys, eax
    mov  lastHead, eax
    mov  lastCount, eax
    mov  tsHead, eax
    mov  tsCount, eax
    mov  wpmPeak, eax
    mov  lastLetter, -1
    mov  lastKeyCode, -1
    invoke GetTickCount
    mov  startTick, eax
    invoke SetMsg, ADDR sMsgReset, A_CYAN AND 0Fh
    ret
DoReset ENDP

DoSave PROC USES ebx
    invoke BuildReport
    invoke CreateFileA, ADDR sReportFile, 40000000h, 0, 0, 2, 80h, 0
    cmp  eax, -1
    je   ds_fail
    mov  ebx, eax
    invoke WriteFile, ebx, ADDR rptBuf, rptLen, ADDR nWritten, 0
    invoke CloseHandle, ebx
    invoke SetMsg, ADDR sMsgSaved, 02h
    ret
ds_fail:
    invoke SetMsg, ADDR sMsgFail, 04h
    ret
DoSave ENDP

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

; ---- 0 reset, 1 save, 2 pause/resume, 3 quit ----
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
    invoke SetMsg, ADDR sMsgPause, 0Eh
    ret
da_resume:
    invoke SetMsg, ADDR sMsgResume, 02h
    ret
da_quit:
    mov  quitFlag, 1
    ret
DoAction ENDP

; =============================================================
;  Input
; =============================================================

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
    jne  hk_left
    invoke DoAction, 2
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
    cmp  ebx, 4
    jae  hm_done
    mov  eax, mouseX
    cmp  eax, btnX[ebx*4]
    jl   hm_nextb
    mov  edx, btnX[ebx*4]
    add  edx, btnW[ebx*4]
    cmp  eax, edx
    jge  hm_nextb
    invoke DoAction, ebx
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

RestoreScreen PROC USES ebx
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
    invoke GetTickCount
    mov  startTick, eax

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

    ; ---- quit: restore the console and print the final report ----
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
