; src/data.inc - variables, tables and text (.data / .data?)
; Part of KeyMonitor.asm (included in order; see the INCLUDE list there).

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
helpOn       DD 0                 ; F9: help overlay shown
; ---- recording and replay (KeySession.kpm) ----
recCount     DD 0                 ; live keys recorded this session
recLastTick  DD 0
replayOn     DD 0                 ; F10: replay running
replayPos    DD 0
replayCount  DD 0
replayNext   DD 0                 ; tick when the next replayed key is due
replayHdr    DD 0, 0              ; magic, key count
; ---- ghost race (KeyGhost.dat) ----
testTimes    DD GHOST_LEN DUP(0)  ; ms from the start at each position of this run
ghostWpm     DD NSENT DUP(0)      ; best WPM per sentence (0 = no ghost)
ghostHdr     DD 0
ghostDirty   DD 0
ghostState   DD 0                 ; after a run: 1 first ghost, 2 beaten, 3 lost
ghostDiff    DD 0
; ---- heatmap modes (frequency / speed / errors) ----
heatMode     DD 0
keyLatSum    DD 256 DUP(0)        ; per key: sum of ms from the previous key
keyLatCnt    DD 256 DUP(0)        ;   (these three tables must stay together: DoReset)
errKey       DD 256 DUP(0)        ; per key: missed in the typing test
keyLatPrev   DD 0
; ---- text analysis ----
taN          DD 0                 ; letters analysed
taH100       DD 0                 ; entropy x100 (bits per letter)
taOverlap    DD 0                 ; % overlap with English letter shares
taChi10      DD 0                 ; chi-squared x10
taShift      DD 0                 ; most likely Caesar shift
taUnique     DD 0
taRedund     DD 0
taValid      DD 0
taCnt        DD 26 DUP(0)
taPm         DD 26 DUP(0)         ; your share of each letter, 0.1 % units
taOver       DD 3 DUP(0)
taOverD      DD 3 DUP(0)
taUnder      DD 3 DUP(0)
taUnderD     DD 3 DUP(0)
chiTmp       DD 0
fHundred     REAL4 100.0
fTen         REAL4 10.0
fThousand    REAL4 1000.0
; English letter shares a-z in 0.1 % units
eng1000      DD 82, 15, 28, 43, 127, 22, 20, 61, 70, 2, 8, 40, 24
             DD 67, 75, 19, 1, 60, 63, 91, 28, 10, 24, 2, 20, 1
stdOut       DD 0                 ; self-test output handle
stLastOk     DD 0                 ; self-test: last-N view correct

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
prevValid    DD 0                 ; prevCanvas holds what the terminal shows
lastFullTick DD 0

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
sSubtitle    DB "MASM x86 ", 0FAh, " keystroke analytics", 0
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
sLongest     DB "LONGEST ", 0
sBackspaces  DB "  BACKSPACE ", 0
sErrRate     DB " (", 0
sPctClose    DB "%)", 0
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
sBK4         DB " ESC ", 0
sBK5         DB " F5 ", 0
sBK6         DB " F6 ", 0
sBK9         DB " F9 ", 0
sBN0         DB " Reset ", 0
sBN1         DB " Export ", 0
sBN2         DB " Pause ", 0
sBN2R        DB " Resume ", 0
sBN4         DB " Quit ", 0
sBN5         DB " Test ", 0
sBN5B        DB " Dash ", 0
sBN6         DB " Bio/XP ", 0
sBN9         DB " Help ", 0
sBN6T        DB " Text ", 0
btnKeys      DD OFFSET sBK0, OFFSET sBK1, OFFSET sBK2, OFFSET sBK5, OFFSET sBK6, OFFSET sBK9, OFFSET sBK4
btnNames     DD OFFSET sBN0, OFFSET sBN1, OFFSET sBN2, OFFSET sBN5, OFFSET sBN6, OFFSET sBN9, OFFSET sBN4
btnColors    DD C_BLUE, C_BLUE, C_BLUE, C_PURP2, C_CYAN2, C_SLATE, C_RED
btnAction    DB 0, 1, 2, 5, 6, 9, 3
sHint        DB "Mouse: click buttons ", 0FAh, " <- ->: N ", 0FAh, " Up/Dn: heatmap ", 0FAh, " F4 F7 F8 ", 0FAh
             DB " F10 replay ", 0FAh, " F9: help", 0
sMsgReset    DB 0FBh, " Counters reset", 0
sMsgSaved    DB 0FBh, " Exported TXT, HTML, CSV and JSON reports", 0
sMsgErgo     DB 0FBh, " Biomechanics, Rhythm & Achievements (F6 = text analysis)", 0
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
sVsLast      DB "VS LAST ", 0
sFirstRun    DB "first run - saved on exit", 0
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

; ---- help overlay (F9) ----
sHelpTitle   DB " HELP ", 0FAh, " KEYS AND SCREENS ", 0
sHelpKeys    DB "KEYS", 0
sHelpScr     DB "SCREENS AND PANELS", 0
sHelpOn      DB "ON", 0
sHelpOff     DB "OFF", 0
sKF1         DB "F1", 0
sKF2         DB "F2", 0
sKF3         DB "F3", 0
sKF4         DB "F4", 0
sKF5         DB "F5", 0
sKF6         DB "F6", 0
sKF7         DB "F7", 0
sKF8         DB "F8", 0
sKF9         DB "F9", 0
sKTab        DB "Tab", 0
sKArr        DB "<- ->", 0
sKEsc        DB "ESC", 0
sHF1         DB "Reset all counters", 0
sHF2         DB "Export TXT, HTML, CSV, JSON", 0
sHF3         DB "Pause / resume counting", 0
sHF4         DB "Autosave on exit", 0
sHF5         DB "Typing test", 0
sHF6         DB "Biomechanics, then text", 0
sHF7         DB "Theme", 0
sHF8         DB "Key click sound", 0
sHF9         DB "Open / close this help", 0
sHTab        DB "Typing test category", 0
sHArr        DB "Resize last N (or wheel)", 0
sHEsc        DB "Quit and print the report", 0
sHS1         DB "Dashboard (start screen)", 0
sHS2         DB "  cards: vowels, consonants, WPM", 0
sHS3         DB "  last N: newest key highlighted", 0
sHS4         DB "  heatmap: pressed key ripples", 0
sHS5         DB "  top 5 keys, bigrams, trigrams", 0
sHS6         DB "  VS LAST: change since last run", 0
sHS7         DB "Typing test (F5)", 0
sHS8         DB "  green ok, red wrong, Enter = next", 0
sHS9         DB "F6: biomechanics, then text", 0
sHS10        DB "  entropy, chi-squared, Caesar", 0
sHS11        DB "Files (next to KeyMonitor.exe)", 0
sHS12        DB "  KeyReport.*, KeyStats.dat", 0
sHelpMouse   DB "Mouse: click any button at the bottom; the wheel changes N.", 0
sHelpSelf    DB "Self-test: run  KeyMonitor.exe /selftest  to check the counters.", 0
sHelpClose   DB "Press F9 or click Help to close", 0
sKF10        DB "F10", 0
sHF10        DB "Replay the last session", 0
sKUpDn       DB "Up/Dn", 0
sHUpDn       DB "Heatmap: often/speed/miss", 0

; ---- self-test (KeyMonitor.exe /selftest) ----
sSelfArg1    DB "/selftest", 0
sSelfArg2    DB "-selftest", 0
stInput      DB "The quick brown fox jumps over the lazy dog. Pack 5 boxes, then the end!", 8, 13, 0
stLastExp    DB "end!", 0AEh, 0D9h          ; last N glyphs: Backspace, Enter
stTitle      DB "KeyMonitor self-test", 13, 10, "--------------------", 13, 10, 0
stPass       DB "  PASS  ", 0
stFail       DB "  FAIL  ", 0
stGot        DB "got ", 0
stExpected   DB ", expected ", 0
stResult     DB 13, 10, "RESULT: ", 0
stOf         DB " / ", 0
stAllOk      DB " checks passed", 13, 10, 0
stSomeBad    DB " checks passed - SELF-TEST FAILED", 13, 10, 0
stN1         DB "total keys          ", 0
stN2         DB "vowels              ", 0
stN3         DB "consonants          ", 0
stN4         DB "digits              ", 0
stN5         DB "spaces              ", 0
stN6         DB "symbols             ", 0
stN7         DB "other keys          ", 0
stN8         DB "frequency of 'e'    ", 0
stN9         DB "words               ", 0
stN10        DB "longest word        ", 0
stN11        DB "backspaces          ", 0
stN12        DB "bigram 'th'         ", 0
stN13        DB "trigram 'the'       ", 0
stN14        DB "top key (ASCII)     ", 0
stN15        DB "last N view correct ", 0
stN16        DB "entropy x100        ", 0
stN17        DB "English overlap %   ", 0
stN18        DB "chi-squared x10     ", 0
stN19        DB "Caesar shift        ", 0
; name, address of the value, expected (worked out separately from the sentence)
stChecks     DD OFFSET stN1, OFFSET totalKeys, 74
             DD OFFSET stN2, OFFSET vowels, 17
             DD OFFSET stN3, OFFSET consonants, 37
             DD OFFSET stN4, OFFSET digits, 1
             DD OFFSET stN5, OFFSET spaces, 14
             DD OFFSET stN6, OFFSET symbols, 3
             DD OFFSET stN7, OFFSET others, 2
             DD OFFSET stN8, OFFSET freq + 'e' * 4, 7
             DD OFFSET stN9, OFFSET words, 15
             DD OFFSET stN10, OFFSET longestWord, 5
             DD OFFSET stN11, OFFSET bsCount, 1
             DD OFFSET stN12, OFFSET bigrams + (19 * 26 + 7) * 4, 4
             DD OFFSET stN13, OFFSET trigrams + ((19 * 26 + 7) * 26 + 4) * 4, 4
             DD OFFSET stN14, OFFSET top5Key, 32
             DD OFFSET stN15, OFFSET stLastOk, 1
             DD OFFSET stN16, OFFSET taH100, 442
             DD OFFSET stN17, OFFSET taOverlap, 78
             DD OFFSET stN18, OFFSET taChi10, 887
             DD OFFSET stN19, OFFSET taShift, 0
             DD 0

; ---- replay and ghost race ----
sSessFile    DB "KeySession.kpm", 0
sGhostFile   DB "KeyGhost.dat", 0
sMsgReplay   DB 0FBh, " Replaying your last session (F10 = stop)", 0
sMsgReplayStop DB "|| Replay stopped", 0
sMsgReplayEnd DB 0FBh, " Replay finished", 0
sMsgNoReplay DB "x No recorded session yet - type something, then quit with ESC", 0
sReplayBadge DB "REPLAY", 0
sReplayLine  DB ">> REPLAY  ", 0
sReplayRest  DB "% of the last session  ", 0FAh, "  pauses over 3 s are shortened  ", 0FAh, "  F10 = stop", 0
sGhostNone   DB "No ghost yet: finish this sentence to race yourself next time", 0
sGhostReady  DB "GHOST: your best on this sentence is ", 0
sGhostRace   DB " WPM - start typing to race it", 0
sGhostLive   DB "GHOST ", 0
sGhostYou    DB " WPM  ", 0FAh, "  you are ", 0
sGhostAhead  DB " chars ahead", 0
sGhostBehind DB " chars behind", 0
sGhostLevel  DB "level with it", 0
sGhostFirst  DB 0FBh, " First run - saved as your ghost for next time", 0
sGhostWin    DB 0FBh, " Ghost beaten by ", 0
sGhostWin2   DB " WPM - new ghost saved!", 0
sGhostLose   DB "Your ghost was faster by ", 0
sGhostLose2  DB " WPM - try again (Enter)", 0

; ---- heatmap modes ----
sHeatT0      DB " HEATMAP ", 0FAh, " FREQUENCY ", 0
sHeatT1      DB " HEATMAP ", 0FAh, " SPEED (slow = hot) ", 0
sHeatT2      DB " HEATMAP ", 0FAh, " TEST MISSES ", 0
heatTitles   DD OFFSET sHeatT0, OFFSET sHeatT1, OFFSET sHeatT2
sFast        DB " fast ", 0
sSlow        DB " slow ", 0
sFew         DB " few  ", 0
sMany        DB " many ", 0
heatLo       DD OFFSET sCold, OFFSET sFast, OFFSET sFew
heatHi       DD OFFSET sHot, OFFSET sSlow, OFFSET sMany
sMsgHeat0    DB 0FBh, " Heatmap: how often each key is pressed (Up/Down to change)", 0
sMsgHeat1    DB 0FBh, " Heatmap: time to reach each key - slow keys are hot", 0
sMsgHeat2    DB 0FBh, " Heatmap: keys you miss in the typing test", 0
heatMsgs     DD OFFSET sMsgHeat0, OFFSET sMsgHeat1, OFFSET sMsgHeat2

; ---- text analysis screen ----
sMsgText     DB 0FBh, " Text analysis: entropy, chi-squared, Caesar shift (F6 = dashboard)", 0
sCardEnt     DB " ENTROPY ", 0
sEntSub      DB "bits/letter, Eng 4.1", 0
sCardOvl     DB " ENGLISH OVERLAP % ", 0
sOvlSub      DB "similar to English", 0
sCardChi     DB " CHI-SQUARED ", 0
sChiOk       DB "looks like English", 0
sChiBad      DB "not English-like", 0
sChiFew      DB "type 20+ letters", 0
sCardCae     DB " CAESAR SHIFT ", 0
sCaePlain    DB "0 = plain text", 0
sCaeShift    DB "decode: shift back ", 0
sBoxTaBars   DB " YOUR LETTERS vs ENGLISH ", 0
sTaYou       DB "you", 0
sTaEng       DB "English share", 0
sBoxTaNum    DB " WHAT THE NUMBERS SAY ", 0
sTaN         DB "Letters analysed  ", 0
sTaU         DB "Unique letters    ", 0
sTaOf        DB "/26", 0
sTaR         DB "Redundancy        ", 0
sTaChi       DB "Chi-squared       ", 0
sTaDf        DB "  (df 25)", 0
sTaOver      DB "More than English ", 0
sTaUnder     DB "Less than English ", 0
sBoxTaHow    DB " HOW IT WORKS ", 0
sTa1         DB "Entropy H = -sum(p * log2 p): how unpredictable your letters are (max 4.70 if all equal).", 0
sTa2         DB "Chi-squared compares your counts with English; under 37.7 (df 25, 5% level) = English-like.", 0
sTa3         DB "Caesar shift: the alphabet rotation that makes the text most English-like (cracks ROT-n).", 0
sTa4         DB "Computed live on the x87 FPU (FYL2X gives log2) from the dashboard's frequency table.", 0

; ---- reports: text analysis ----
rpEnt        DB "Letter entropy   : ", 0
rpBits       DB " bits/letter", 13, 10, 0
rpOvl        DB "English overlap %: ", 0
rpChi        DB "Chi-squared      : ", 0
rpCae        DB "Caesar shift     : ", 0
hTaHead      DB '<div class="grid">', 13, 10, 0
hlEnt        DB "Letter entropy", 0
hlEntSub     DB "bits per letter (English ~4.1)", 0
hlOvl        DB "English overlap %", 0
hlOvlSub     DB "letter mix like English", 0
hlChi        DB "Chi-squared", 0
hlChiSub     DB "under 37.7 = English-like", 0
hlCae        DB "Caesar shift", 0
hlCaeSub     DB "0 = plain text", 0

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
prevCanvas   DD SCR_W * SCR_H * 3 DUP(?) ; last frame sent, for sending only changes
csbiOld      DB 96 DUP(?)              ; CONSOLE_SCREEN_BUFFER_INFOEX
csbiNew      DB 96 DUP(?)
rptBuf       DB 16384 DUP(?)
recBuf       DD REC_MAX DUP(?)        ; this session: char | vk << 8 | gap ms << 16
replayBuf    DD REC_MAX DUP(?)        ; the session being replayed
ghostTimes   DD NSENT * GHOST_LEN DUP(?)
htmlBuf      DB 65536 DUP(?)          ; KeyReport.html
bigrams      DD NG2 DUP(?)            ; count of every letter pair
trigrams     DD NG3 DUP(?)            ; count of every letter triple
