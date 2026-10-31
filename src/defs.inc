; src/defs.inc - API prototypes and constants
; Part of KeyMonitor.asm (included in order; see the INCLUDE list there).

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
GetCommandLineA               PROTO
Beep                          PROTO :DWORD, :DWORD
includelib kernel32.lib

; ---------- procedures used before their definition ----------
Tween                         PROTO :DWORD, :DWORD
RippleSetup                   PROTO
RippleMix                     PROTO :DWORD, :DWORD, :DWORD
DrawCompare                   PROTO
KeyLat                        PROTO :DWORD, :DWORD
MissKey                       PROTO :DWORD
GhostMark                     PROTO
GhostFinish                   PROTO
ReplayTick                    PROTO
HeatValue                     PROTO :DWORD
DrawGhost                     PROTO :DWORD
DrawTextView                  PROTO
AnalyzeText                   PROTO
DoReset                       PROTO
SetMsg                        PROTO :DWORD, :DWORD

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
VK_F9             EQU 78h
VK_F10            EQU 79h
VK_UP             EQU 26h
VK_DOWN           EQU 28h
REC_MAX           EQU 32768       ; keys kept for the replay
REC_MAGIC         EQU 524D504Bh   ; "KPMR" (KeySession.kpm)
REPLAY_GAP        EQU 3000        ; longer pauses are shortened in the replay
GHOST_LEN         EQU 128         ; ghost times per sentence
GHOST_MAGIC       EQU 474D504Bh   ; "KPMG" (KeyGhost.dat)
NHEAT             EQU 3           ; heatmap modes
FULL_FRAME_MS     EQU 2000        ; send the whole screen at least this often
MIN_LETTERS       EQU 20          ; letters needed for the chi-squared verdict
CHI_CRIT          EQU 377         ; chi-squared x10, df 25, 5 % level (37.65)
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
NBTN              EQU 7           ; number of buttons (F4, F7, F8 are in the F9 help)
ST_LASTN          EQU 6           ; self-test: last-N characters checked
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
C_SLATE     EQU 0695547h  ; #475569 (help button)
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
