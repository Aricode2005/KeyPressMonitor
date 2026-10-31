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
;  21. Help overlay (F9) with every key and screen
;  22. Self-test: KeyMonitor.exe /selftest checks the counters
;  23. Session replay (F10) and a ghost race in the typing test
;  24. Heatmap modes (Up / Down): frequency, speed, typing-test errors
;  25. Text analysis (F6 twice): entropy, English overlap, chi-squared,
;      Caesar-shift detection (x87 FPU)
;
;  Keys:  F1 reset   F2 save reports   F3 pause   F4 autosave
;         F5 typing test   F6 biomechanics   F7 theme   F8 sound
;         F9 help   F10 replay   Up/Down heatmap mode   Tab test mode
;         Left/Right (or wheel) change N   ESC quit
;
;  Source layout (this file includes the modules in src\):
;    defs.inc       API prototypes and constants
;    data.inc       variables, tables and text
;    render.inc     canvas primitives, VT / 16-colour output
;    stats.inc      counting: classify, n-grams, biomechanics, WPM
;    session.inc    typing test, last-session stats (KeyStats.dat)
;    selftest.inc   KeyMonitor.exe /selftest
;    dashboard.inc  dashboard, typing test, biomechanics, help screens
;    reports.inc    text and HTML reports
;    actions.inc    actions and keyboard / mouse input
;    console.inc    console setup and restore
;
;  Uses only kernel32.lib (comes with Visual Studio / Windows SDK).
; =============================================================

.386
.387                                ; x87 FPU for the text analysis (log2)
.model flat, stdcall
option casemap:none

; ---------- source modules (order matters: MASM needs a procedure
;            defined above the first INVOKE that uses it) ----------
INCLUDE src\defs.inc
INCLUDE src\data.inc

.code
INCLUDE src\render.inc
INCLUDE src\stats.inc
INCLUDE src\session.inc
INCLUDE src\selftest.inc
INCLUDE src\dashboard.inc
INCLUDE src\reports.inc
INCLUDE src\actions.inc
INCLUDE src\console.inc

; =================== MAIN ===================
start:
    invoke CmdHas, ADDR sSelfArg1   ; KeyMonitor.exe /selftest (or -selftest)
    test eax, eax
    jnz  selfTest
    invoke CmdHas, ADDR sSelfArg2
    test eax, eax
    jz   normalStart
selfTest:
    invoke RunSelfTest
    invoke ExitProcess, eax         ; exit code = number of failed checks
normalStart:
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
    invoke LoadGhosts
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
    invoke SaveSession
    invoke SaveGhosts
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
