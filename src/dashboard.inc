; src/dashboard.inc - dashboard, typing test, biomechanics and help screens
; Part of KeyMonitor.asm (included in order; see the INCLUDE list there).

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
    invoke Text, 55, 0, ADDR sHdrLvl, C_GOLD, C_KEEP
    invoke Num, eax, 0, xpLevel, C_WHITE
    lea  ebx, [eax+1]               ; rank name right after the level
    mov  eax, xpLevel
    dec  eax
    cmp  eax, 4
    jbe  dh_rnk
    mov  eax, 4
dh_rnk:
    mov  eax, rankNames[eax*4]
    invoke Text, ebx, 0, eax, C_CYAN, C_KEEP
    cmp  replayOn, 0
    je   dh_pause
    invoke Cell, 74, 0, 25B8h, C_PINK, C_KEEP
    invoke Text, 76, 0, ADDR sReplayBadge, C_PINK, C_KEEP
    jmp  dh_time
dh_pause:
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
    mov  eax, heatMode
    invoke RBox, 59, 12, 39, 7, heatTitles[eax*4], C_BORDER, C_TEXT
    invoke RippleSetup

    mov  heatMax, 1
    xor  ecx, ecx
hm_max:
    push ecx
    invoke HeatValue, ecx
    pop  ecx
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
    invoke HeatValue, eax
    invoke Keycap, kx, ky, edi, eax
    add  kx, 3
    inc  esi
    inc  pVk
    jmp  hm_key
hm_nextrow:
    inc  rowI
    cmp  rowI, 4
    jb   hm_row

    invoke HeatValue, 20h           ; space bar
    mov  edi, eax
    invoke HeatColor, edi
    invoke RippleMix, 74, 17, eax
    mov  ebx, eax
    invoke HeatText, edi
    mov  esi, eax
    invoke Cell, 65, 17, 2590h, ebx, C_PANEL
    invoke Fill, 66, 17, 18, 1, ' ', esi, ebx
    invoke Text, 72, 17, ADDR sSpace, esi, C_KEEP
    invoke Cell, 84, 17, 258Ch, ebx, C_PANEL

    mov  eax, heatMode              ; legend in the bottom edge
    invoke Text, 69, 18, heatLo[eax*4], C_MUTED, C_KEEP
    xor  esi, esi
hm_leg:
    invoke Ramp, ADDR heatStops, 6, esi, 11
    lea  ecx, [esi+75]
    invoke Cell, ecx, 18, 2588h, eax, C_KEEP
    inc  esi
    cmp  esi, 12
    jb   hm_leg
    mov  eax, heatMode
    invoke Text, 87, 18, heatHi[eax*4], C_MUTED, C_KEEP
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
    invoke Text, eax, 27, ADDR sPctClose, C_MUTED, C_KEEP
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
    jne  bt_test
    cmp  paused, 0
    je   bt_size
    mov  pName, OFFSET sBN2R
    mov  col, C_PAUSEBTN
    jmp  bt_size
bt_test:
    cmp  esi, 3                     ; F5 / F6 read "Dash" while their screen is shown
    jne  bt_bio
    cmp  viewMode, 1
    jne  bt_size
    mov  pName, OFFSET sBN5B
    jmp  bt_size
bt_bio:
    cmp  esi, 4                     ; F6 names the screen it leads to
    jne  bt_help
    cmp  viewMode, 2
    jne  bt_bio3
    mov  pName, OFFSET sBN6T
    jmp  bt_size
bt_bio3:
    cmp  viewMode, 3
    jne  bt_size
    mov  pName, OFFSET sBN5B
    jmp  bt_size
bt_help:
    cmp  esi, 5                     ; help button lit while the help is open
    jne  bt_size
    cmp  helpOn, 0
    je   bt_size
    mov  col, C_PAUSEBTN
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
    inc  ebx                        ; one cell between buttons
    inc  esi
    jmp  bt_loop

bt_msg:
    cmp  replayOn, 0                ; replay progress replaces the message line
    je   bt_msg2
    invoke Text, 2, 29, ADDR sReplayLine, C_PINK, C_KEEP
    mov  ebx, eax
    mov  eax, replayPos
    mov  edx, 100
    mul  edx
    div  replayCount
    invoke Num, ebx, 29, eax, C_WHITE
    invoke Text, eax, 29, ADDR sReplayRest, C_PINK, C_KEEP
    ret
bt_msg2:
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
    invoke Text, 59, 27, ADDR sVsLast, C_MUTED, C_KEEP
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
    invoke DrawGhost, x0
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
; ---- thin horizontal bar (lower half blocks), scaled to maxv, fading into clr ----
HBarL PROC USES ebx esi px:DWORD, py:DWORD, wd:DWORD, val:DWORD, maxv:DWORD, clr:DWORD
    LOCAL fillN:DWORD, dim:DWORD
    mov  eax, val                   ; filled cells, at least 1 when val > 0
    mul  wd
    add  eax, maxv
    dec  eax
    div  maxv
    cmp  eax, wd
    jbe  hb_n
    mov  eax, wd
hb_n:
    mov  fillN, eax
    invoke Lerp, clr, C_PANEL, 55, 100
    mov  dim, eax
    xor  esi, esi
hb_loop:
    cmp  esi, wd
    jae  hb_done
    mov  ebx, px
    add  ebx, esi
    cmp  esi, fillN
    jae  hb_track
    mov  eax, wd
    dec  eax
    invoke Lerp, dim, clr, esi, eax
    invoke Cell, ebx, py, 2584h, eax, C_KEEP
    jmp  hb_next
hb_track:
    invoke Cell, ebx, py, 2584h, C_TRACK, C_KEEP
hb_next:
    inc  esi
    jmp  hb_loop
hb_done:
    ret
HBarL ENDP

DrawErgoView PROC USES ebx esi edi
    LOCAL totH:DWORD, yRow:DWORD, maxF:DWORD, maxR:DWORD
    mov  ebx, leftHand
    add  ebx, rightHand
    mov  totH, ebx
    mov  maxF, 1                    ; bars are scaled to the busiest finger / row
    xor  ecx, ecx
de_mf:
    mov  eax, fingerCnt[ecx*4]
    cmp  eax, maxF
    jbe  de_mf2
    mov  maxF, eax
de_mf2:
    inc  ecx
    cmp  ecx, 9
    jb   de_mf
    mov  maxR, 1
    xor  ecx, ecx
de_mr:
    mov  eax, rowCnt[ecx*4]
    cmp  eax, maxR
    jbe  de_mr2
    mov  maxR, eax
de_mr2:
    inc  ecx
    cmp  ecx, 5
    jb   de_mr

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
    invoke Percent, fingerCnt[esi*4], totalKeys
    mov  edi, eax                   ; edi = percent
    mov  ebx, C_CYAN                ; left hand cyan, right hand purple, thumbs green
    cmp  esi, 4
    jb   de_fcol
    mov  ebx, C_PURP
    cmp  esi, 8
    jb   de_fcol
    mov  ebx, C_GREEN
de_fcol:
    invoke HBarL, 14, yRow, 22, fingerCnt[esi*4], maxF, ebx
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
    invoke HBarL, 72, yRow, 14, rowCnt[esi*4], maxR, C_AMBER
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

; ---- one help row: key in gold, description, optional ON/OFF ----
HelpRow PROC px:DWORD, py:DWORD, pKey:DWORD, pText:DWORD
    invoke Text, px, py, pKey, C_GOLD, C_KEEP
    mov  eax, px
    add  eax, 7
    invoke Text, eax, py, pText, C_TEXT, C_KEEP
    ret
HelpRow ENDP

; ---- ON / OFF badge after a help row; returns nothing ----
OnOff PROC px:DWORD, py:DWORD, flag:DWORD
    cmp  flag, 0
    je   oo_off
    invoke Text, px, py, ADDR sHelpOn, C_OK, C_KEEP
    ret
oo_off:
    invoke Text, px, py, ADDR sHelpOff, C_DIM, C_KEEP
    ret
OnOff ENDP

; ---- help overlay (F9): every key and what each screen shows ----
DrawHelp PROC
    invoke RBox, 12, 3, 76, 23, ADDR sHelpTitle, C_GOLD, C_GOLD
    invoke Text, 15, 5, ADDR sHelpKeys, C_CYAN, C_KEEP
    invoke HelpRow, 15, 6, ADDR sKF1, ADDR sHF1
    invoke HelpRow, 15, 7, ADDR sKF2, ADDR sHF2
    invoke HelpRow, 15, 8, ADDR sKF3, ADDR sHF3
    invoke HelpRow, 15, 9, ADDR sKF4, ADDR sHF4
    invoke OnOff, 44, 9, autoSave
    invoke HelpRow, 15, 10, ADDR sKF5, ADDR sHF5
    invoke HelpRow, 15, 11, ADDR sKF6, ADDR sHF6
    invoke HelpRow, 15, 12, ADDR sKF7, ADDR sHF7
    mov  eax, themeIdx              ; theme name = the theme message after "v Theme: "
    mov  eax, themeMsgs[eax*4]
    add  eax, 9
    invoke Text, 29, 12, eax, C_OK, C_KEEP
    invoke HelpRow, 15, 13, ADDR sKF8, ADDR sHF8
    invoke OnOff, 44, 13, soundOn
    invoke HelpRow, 15, 14, ADDR sKF9, ADDR sHF9
    invoke HelpRow, 15, 15, ADDR sKTab, ADDR sHTab
    invoke HelpRow, 15, 16, ADDR sKArr, ADDR sHArr
    invoke HelpRow, 15, 17, ADDR sKEsc, ADDR sHEsc
    invoke HelpRow, 15, 18, ADDR sKF10, ADDR sHF10
    invoke HelpRow, 15, 19, ADDR sKUpDn, ADDR sHUpDn

    invoke Text, 52, 5, ADDR sHelpScr, C_CYAN, C_KEEP
    invoke Text, 52, 6, ADDR sHS1, C_WHITE, C_KEEP
    invoke Text, 52, 7, ADDR sHS2, C_MUTED, C_KEEP
    invoke Text, 52, 8, ADDR sHS3, C_MUTED, C_KEEP
    invoke Text, 52, 9, ADDR sHS4, C_MUTED, C_KEEP
    invoke Text, 52, 10, ADDR sHS5, C_MUTED, C_KEEP
    invoke Text, 52, 11, ADDR sHS6, C_MUTED, C_KEEP
    invoke Text, 52, 12, ADDR sHS7, C_WHITE, C_KEEP
    invoke Text, 52, 13, ADDR sHS8, C_MUTED, C_KEEP
    invoke Text, 52, 14, ADDR sHS9, C_WHITE, C_KEEP
    invoke Text, 52, 15, ADDR sHS10, C_MUTED, C_KEEP
    invoke Text, 52, 17, ADDR sHS11, C_WHITE, C_KEEP
    invoke Text, 52, 18, ADDR sHS12, C_MUTED, C_KEEP

    invoke Text, 15, 21, ADDR sHelpMouse, C_MUTED, C_KEEP
    invoke Text, 15, 22, ADDR sHelpSelf, C_MUTED, C_KEEP
    invoke Text, 35, 24, ADDR sHelpClose, C_GOLD, C_KEEP
    ret
DrawHelp ENDP

; ---- value of a key for the current heatmap mode ----
HeatValue PROC vk:DWORD
    mov  ecx, vk
    and  ecx, 0FFh
    mov  eax, heatMode
    cmp  eax, 1
    je   hv_speed
    cmp  eax, 2
    je   hv_err
    mov  eax, vkFreq[ecx*4]         ; 0: how often
    ret
hv_speed:                           ; 1: average ms to reach the key
    mov  eax, keyLatCnt[ecx*4]
    test eax, eax
    jz   hv_ret
    mov  eax, keyLatSum[ecx*4]
    xor  edx, edx
    div  keyLatCnt[ecx*4]
hv_ret:
    ret
hv_err:                             ; 2: missed in the typing test
    mov  eax, errKey[ecx*4]
    ret
HeatValue ENDP

; ---- next / previous heatmap mode (Up / Down, or a click on the heatmap) ----
HeatStep PROC delta:DWORD
    mov  eax, heatMode
    add  eax, delta
    add  eax, NHEAT
    xor  edx, edx
    mov  ecx, NHEAT
    div  ecx
    mov  heatMode, edx
    invoke SetMsg, heatMsgs[edx*4], C_CYAN
    ret
HeatStep ENDP

; ---- typing test: ghost marker under the sentence and the race status ----
DrawGhost PROC USES ebx esi x0:DWORD
    invoke GhostPos
    mov  esi, eax
    cmp  testDone, 0
    jne  dg_result
    cmp  esi, -1
    jne  dg_have
    invoke Text, 6, 14, ADDR sGhostNone, C_DIM, C_KEEP
    ret
dg_have:
    mov  ecx, testIdx
    mov  ebx, ghostWpm[ecx*4]
    cmp  testStart, 0
    jne  dg_race
    invoke Text, 6, 14, ADDR sGhostReady, C_MUTED, C_KEEP
    invoke Num, eax, 14, ebx, C_PINK
    invoke Text, eax, 14, ADDR sGhostRace, C_MUTED, C_KEEP
    ret
dg_race:
    cmp  esi, testLen               ; marker under the ghost's next character
    jae  dg_text
    mov  eax, x0
    add  eax, esi
    invoke Cell, eax, 12, 25B2h, C_PINK, C_KEEP
dg_text:
    invoke Text, 6, 14, ADDR sGhostLive, C_PINK, C_KEEP
    invoke Num, eax, 14, ebx, C_PINK
    invoke Text, eax, 14, ADDR sGhostYou, C_MUTED, C_KEEP
    mov  ebx, eax
    mov  eax, testPos
    sub  eax, esi
    jz   dg_level
    js   dg_behind
    invoke Num, ebx, 14, eax, C_OK
    invoke Text, eax, 14, ADDR sGhostAhead, C_OK, C_KEEP
    ret
dg_behind:
    neg  eax
    invoke Num, ebx, 14, eax, C_RED
    invoke Text, eax, 14, ADDR sGhostBehind, C_RED, C_KEEP
    ret
dg_level:
    invoke Text, ebx, 14, ADDR sGhostLevel, C_GOLD, C_KEEP
    ret
dg_result:
    mov  eax, ghostState
    cmp  eax, 1
    jne  dg_win
    invoke Text, 6, 14, ADDR sGhostFirst, C_OK, C_KEEP
    ret
dg_win:
    cmp  eax, 2
    jne  dg_lose
    invoke Text, 6, 14, ADDR sGhostWin, C_OK, C_KEEP
    invoke Num, eax, 14, ghostDiff, C_WHITE
    invoke Text, eax, 14, ADDR sGhostWin2, C_OK, C_KEEP
    ret
dg_lose:
    cmp  eax, 3
    jne  dg_done
    invoke Text, 6, 14, ADDR sGhostLose, C_PINK, C_KEEP
    invoke Num, eax, 14, ghostDiff, C_WHITE
    invoke Text, eax, 14, ADDR sGhostLose2, C_PINK, C_KEEP
dg_done:
    ret
DrawGhost ENDP

; ---- card frame without a number (the caller draws the value) ----
CardFrame PROC px:DWORD, pTitle:DWORD, c1:DWORD, c2:DWORD
    invoke Lerp, c2, C_BORDER, 35, 100
    invoke RBox, px, 2, 23, 6, pTitle, eax, c1
    ret
CardFrame ENDP

; ---- big number with two decimals (value x100), e.g. 4.42 ----
BigFix PROC USES ebx esi px:DWORD, py:DWORD, v100:DWORD, c1:DWORD, c2:DWORD
    mov  eax, v100
    xor  edx, edx
    mov  ecx, 100
    div  ecx
    push edx                        ; hundredths
    mov  esi, eax
    invoke BigNum, px, py, esi, c1, c2
    invoke NumToStr, esi
    lea  ebx, [ecx*4]               ; x after the whole part
    add  ebx, px
    mov  eax, py
    add  eax, 2
    invoke Cell, ebx, eax, 2580h, c2, C_KEEP     ; decimal point
    pop  eax
    xor  edx, edx
    mov  ecx, 10
    div  ecx
    push edx
    lea  ecx, [ebx+2]
    invoke BigNum, ecx, py, eax, c1, c2
    pop  edx
    lea  ecx, [ebx+6]
    invoke BigNum, ecx, py, edx, c1, c2
    ret
BigFix ENDP

; ---- number with one decimal (value x10); returns eax = next x ----
NumDec1 PROC USES ebx px:DWORD, py:DWORD, v10:DWORD, fg:DWORD
    mov  eax, v10
    xor  edx, edx
    mov  ecx, 10
    div  ecx
    mov  ebx, edx
    invoke Num, px, py, eax, fg
    push eax
    invoke Cell, eax, py, '.', fg, C_KEEP
    pop  eax
    inc  eax
    add  ebx, '0'
    push eax
    invoke Cell, eax, py, ebx, fg, C_KEEP
    pop  eax
    inc  eax
    ret
NumDec1 ENDP

; ---- one over/under-used letter: E+3.1 ; returns eax = next x ----
DiffItem PROC USES ebx px:DWORD, py:DWORD, letter:DWORD, diff:DWORD, fg:DWORD
    mov  eax, letter
    add  eax, 'A'
    invoke Cell, px, py, eax, C_WHITE, C_KEEP
    mov  ebx, px
    inc  ebx
    mov  eax, diff
    mov  ecx, '+'
    test eax, eax
    jns  di_sign
    neg  eax
    mov  diff, eax
    mov  ecx, '-'
di_sign:
    invoke Cell, ebx, py, ecx, fg, C_KEEP
    inc  ebx
    invoke NumDec1, ebx, py, diff, fg
    inc  eax
    ret
DiffItem ENDP

; ---- text analysis screen (F6 twice): entropy, English overlap, chi-squared, Caesar ----
DrawTextView PROC USES ebx esi edi
    LOCAL scale:DWORD, h8:DWORD, col:DWORD, lo:DWORD, hi:DWORD, ey:DWORD
    invoke AnalyzeText

    invoke CardFrame, 2, ADDR sCardEnt, C_CYAN, C_CYAN2
    invoke BigFix, 4, 3, taH100, C_CYAN, C_CYAN2
    invoke Text, 4, 6, ADDR sEntSub, C_MUTED, C_KEEP
    invoke Card, 26, ADDR sCardOvl, taOverlap, C_GREEN, C_GREEN2, 0, 0, 0, 0
    invoke Text, 28, 6, ADDR sOvlSub, C_MUTED, C_KEEP
    invoke CardFrame, 50, ADDR sCardChi, C_AMBER, C_AMBER2
    mov  eax, taChi10
    xor  edx, edx
    mov  ecx, 10
    div  ecx
    invoke BigNum, 52, 3, eax, C_AMBER, C_AMBER2
    cmp  taValid, 0
    jne  tx_verdict
    invoke Text, 52, 6, ADDR sChiFew, C_MUTED, C_KEEP
    jmp  tx_cae
tx_verdict:
    cmp  taChi10, CHI_CRIT
    jae  tx_bad
    invoke Text, 52, 6, ADDR sChiOk, C_OK, C_KEEP
    jmp  tx_cae
tx_bad:
    invoke Text, 52, 6, ADDR sChiBad, C_RED, C_KEEP
tx_cae:
    invoke Card, 74, ADDR sCardCae, taShift, C_PURP, C_PURP2, 0, 0, 0, 0
    cmp  taShift, 0
    jne  tx_shifted
    invoke Text, 76, 6, ADDR sCaePlain, C_MUTED, C_KEEP
    jmp  tx_bars
tx_shifted:
    invoke Text, 76, 6, ADDR sCaeShift, C_MUTED, C_KEEP
    invoke Num, eax, 6, taShift, C_WHITE

tx_bars:                            ; ---- your share of each letter vs English ----
    invoke RBox, 2, 9, 56, 12, ADDR sBoxTaBars, C_BORDER, C_TEXT
    invoke Cell, 4, 10, 2588h, C_GREEN, C_KEEP
    invoke Text, 6, 10, ADDR sTaYou, C_MUTED, C_KEEP
    invoke Cell, 14, 10, 2500h, C_WHITE, C_KEEP
    invoke Text, 16, 10, ADDR sTaEng, C_MUTED, C_KEEP
    mov  scale, 130                 ; at least English 'e' (12.7 %)
    xor  esi, esi
tx_max:
    mov  eax, taPm[esi*4]
    cmp  eax, scale
    jbe  tx_mnext
    mov  scale, eax
tx_mnext:
    inc  esi
    cmp  esi, 26
    jb   tx_max
    invoke Fill, 4, 17, 52, 1, 2500h, C_AXIS, C_KEEP
    xor  esi, esi
tx_col:
    mov  eax, esi
    shl  eax, 1
    add  eax, 4
    mov  col, eax
    lea  eax, [esi+'a']
    invoke Classify, eax
    mov  lo, C_AMBER2
    mov  hi, C_AMBER
    cmp  eax, CAT_VOWEL
    jne  tx_lbl
    mov  lo, C_GREEN2
    mov  hi, C_GREEN
tx_lbl:
    lea  eax, [esi+'A']
    mov  edx, C_TEXT
    cmp  taCnt[esi*4], 0
    jne  tx_l2
    mov  edx, C_DIM
tx_l2:
    invoke Cell, col, 18, eax, edx, C_KEEP
    mov  eax, taPm[esi*4]           ; bar height in eighths (6 rows = 48)
    mov  edx, 48
    mul  edx
    add  eax, scale
    dec  eax
    div  scale
    mov  h8, eax
    xor  edi, edi
tx_bar:
    cmp  edi, 6
    jae  tx_eng
    mov  eax, edi
    shl  eax, 3
    mov  ebx, h8
    sub  ebx, eax
    jle  tx_eng
    cmp  ebx, 8
    jbe  tx_e
    mov  ebx, 8
tx_e:
    invoke Lerp, lo, hi, edi, 5
    push eax
    invoke Eighth, ebx
    pop  edx
    mov  ecx, 16
    sub  ecx, edi
    invoke Cell, col, ecx, eax, edx, C_KEEP
    inc  edi
    jmp  tx_bar
tx_eng:                             ; white line at the English share
    mov  eax, eng1000[esi*4]
    mov  edx, 48
    mul  edx
    div  scale
    shr  eax, 3                     ; row from the bottom
    cmp  eax, 5
    jbe  tx_ey
    mov  eax, 5
tx_ey:
    mov  ecx, 16
    sub  ecx, eax
    mov  ey, ecx
    shl  eax, 3                     ; covered by the bar? then draw it on the bar colour
    add  eax, 8
    mov  edx, C_KEEP
    cmp  h8, eax
    jb   tx_mark
    mov  edx, hi
tx_mark:
    invoke Cell, col, ey, 2500h, C_WHITE, edx
    inc  esi
    cmp  esi, 26
    jb   tx_col

    ; ---- the numbers in words ----
    invoke RBox, 59, 9, 39, 12, ADDR sBoxTaNum, C_BORDER, C_TEXT
    invoke Text, 61, 11, ADDR sTaN, C_MUTED, C_KEEP
    invoke Num, eax, 11, taN, C_WHITE
    invoke Text, 61, 12, ADDR sTaU, C_MUTED, C_KEEP
    invoke Num, eax, 12, taUnique, C_WHITE
    invoke Text, eax, 12, ADDR sTaOf, C_MUTED, C_KEEP
    invoke Text, 61, 13, ADDR sTaR, C_MUTED, C_KEEP
    invoke Num, eax, 13, taRedund, C_WHITE
    invoke Cell, eax, 13, '%', C_MUTED, C_KEEP
    invoke Text, 61, 14, ADDR sTaChi, C_MUTED, C_KEEP
    invoke NumDec1, eax, 14, taChi10, C_AMBER
    invoke Text, eax, 14, ADDR sTaDf, C_MUTED, C_KEEP
    cmp  taN, 0
    je   tx_how
    invoke Text, 61, 16, ADDR sTaOver, C_MUTED, C_KEEP
    mov  ebx, eax
    xor  esi, esi
tx_over:
    invoke DiffItem, ebx, 16, taOver[esi*4], taOverD[esi*4], C_OK
    mov  ebx, eax
    inc  esi
    cmp  esi, 3
    jb   tx_over
    invoke Text, 61, 17, ADDR sTaUnder, C_MUTED, C_KEEP
    mov  ebx, eax
    xor  esi, esi
tx_under:
    invoke DiffItem, ebx, 17, taUnder[esi*4], taUnderD[esi*4], C_RED
    mov  ebx, eax
    inc  esi
    cmp  esi, 3
    jb   tx_under

tx_how:                             ; ---- what the numbers mean ----
    invoke RBox, 2, 21, 96, 6, ADDR sBoxTaHow, C_BORDER, C_TEXT
    invoke Text, 4, 22, ADDR sTa1, C_MUTED, C_KEEP
    invoke Text, 4, 23, ADDR sTa2, C_MUTED, C_KEEP
    invoke Text, 4, 24, ADDR sTa3, C_MUTED, C_KEEP
    invoke Text, 4, 25, ADDR sTa4, C_MUTED, C_KEEP
    ret
DrawTextView ENDP

; ---- redraw every panel into the canvas, then flush once ----
RenderAll PROC
    mov  animating, 0
    invoke ReplayTick
    invoke UpdateStats
    invoke Fill, 0, 0, SCR_W, SCR_H, ' ', C_TEXT, C_PAGE
    invoke DrawHeader
    cmp  viewMode, 1
    je   ra_test
    cmp  viewMode, 2
    je   ra_ergo
    cmp  viewMode, 3
    je   ra_text
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
ra_text:
    invoke DrawTextView
    jmp  ra_bottom
ra_ergo:
    invoke DrawErgoView
ra_bottom:
    cmp  helpOn, 0
    je   ra_nohelp
    invoke DrawHelp
ra_nohelp:
    invoke DrawStatsLine
    invoke DrawButtons
    invoke Flush
    mov  frameWait, 250             ; about 30 fps only while something moves
    cmp  animating, 0
    je   ra_replay
    mov  frameWait, 30
ra_replay:
    cmp  replayOn, 0
    je   ra_done
    mov  frameWait, 15              ; replayed keys arrive at their recorded times
ra_done:
    ret
RenderAll ENDP
