; src/stats.inc - counting logic: classify, n-grams, biomechanics, WPM, top 5
; Part of KeyMonitor.asm (included in order; see the INCLUDE list there).

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
    push eax
    invoke KeyLat, vk, eax
    pop  eax
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

; ---- time from the previous key to this one, per key (speed heatmap) ----
KeyLat PROC vk:DWORD, now:DWORD
    mov  eax, now
    mov  ecx, keyLatPrev
    mov  keyLatPrev, eax
    test ecx, ecx
    jz   kl_done
    sub  eax, ecx
    cmp  eax, 2000                  ; pauses do not count
    jae  kl_done
    mov  ecx, vk
    and  ecx, 0FFh
    add  keyLatSum[ecx*4], eax
    inc  keyLatCnt[ecx*4]
kl_done:
    ret
KeyLat ENDP

; ---- character -> virtual key on the heatmap keyboard, or -1 ----
CharToVk PROC USES ebx esi edi chv:DWORD
    mov  eax, chv
    cmp  eax, ' '
    jne  cv_case
    mov  eax, 20h
    ret
cv_case:
    cmp  eax, 'a'
    jb   cv_scan
    cmp  eax, 'z'
    ja   cv_scan
    sub  eax, 20h                   ; labels are upper case
cv_scan:
    xor  ecx, ecx
cv_row:
    cmp  ecx, 4
    jae  cv_none
    mov  ebx, ecx
    shl  ebx, 4
    mov  esi, kbRows[ebx]           ; labels
    mov  edi, kbRows[ebx+4]         ; virtual keys
    xor  edx, edx
cv_key:
    cmp  BYTE PTR [esi+edx], 0
    je   cv_next
    cmp  [esi+edx], al
    je   cv_hit
    inc  edx
    jmp  cv_key
cv_next:
    inc  ecx
    jmp  cv_row
cv_hit:
    movzx eax, BYTE PTR [edi+edx]
    ret
cv_none:
    mov  eax, -1
    ret
CharToVk ENDP

; ---- a key the typing test expected but got wrong (error heatmap) ----
MissKey PROC chv:DWORD
    invoke CharToVk, chv
    cmp  eax, -1
    je   mk_done
    inc  errKey[eax*4]
mk_done:
    ret
MissKey ENDP

; ---- record a live key for replay: char, virtual key, ms since the last one ----
RecKey PROC chv:DWORD, vk:DWORD
    cmp  recCount, REC_MAX
    jae  rk_done
    invoke GetTickCount
    mov  edx, eax
    sub  eax, recLastTick
    cmp  recCount, 0
    jne  rk_gap
    xor  eax, eax                   ; first key: no wait
rk_gap:
    mov  recLastTick, edx
    cmp  eax, REPLAY_GAP            ; long pauses are shortened in the replay
    jbe  rk_pack
    mov  eax, REPLAY_GAP
rk_pack:
    shl  eax, 16
    mov  edx, vk
    and  edx, 0FFh
    shl  edx, 8
    or   eax, edx
    mov  edx, chv
    and  edx, 0FFh
    or   eax, edx
    mov  ecx, recCount
    mov  recBuf[ecx*4], eax
    inc  recCount
rk_done:
    ret
RecKey ENDP

; ---- chi-squared x10 of the letters against English, alphabet rotated by sh ----
ChiShift PROC USES esi sh:DWORD
    fldz                            ; running sum
    xor  esi, esi
cs_loop:
    mov  eax, esi                   ; observed letter = (i + sh) mod 26
    add  eax, sh
    cmp  eax, 26
    jb   cs_obs
    sub  eax, 26
cs_obs:
    fild taCnt[eax*4]               ; observed count
    fild taN
    fimul eng1000[esi*4]
    fdiv fThousand                  ; expected = n * English share
    fsub st(1), st                  ; st1 = observed - expected
    fxch st(1)
    fmul st, st                     ; (o - e)^2
    fdivrp st(1), st                ; / expected
    faddp st(1), st
    inc  esi
    cmp  esi, 26
    jb   cs_loop
    fmul fTen
    fistp chiTmp
    mov  eax, chiTmp
    ret
ChiShift ENDP

; ---- the three most over- and under-used letters compared with English ----
PickDiffs PROC USES ebx esi edi
    LOCAL k:DWORD, picked:DWORD, best:DWORD, bestI:DWORD
    mov  picked, 0
    mov  k, 0
pd_over:
    cmp  k, 3
    jae  pd_under0
    mov  best, 80000000h
    mov  bestI, 0
    xor  esi, esi
pd_oi:
    bt   picked, esi
    jc   pd_on
    mov  eax, taPm[esi*4]
    sub  eax, eng1000[esi*4]
    cmp  eax, best
    jle  pd_on
    mov  best, eax
    mov  bestI, esi
pd_on:
    inc  esi
    cmp  esi, 26
    jb   pd_oi
    mov  eax, bestI
    bts  picked, eax
    mov  ecx, k
    mov  taOver[ecx*4], eax
    mov  edx, best
    mov  taOverD[ecx*4], edx
    inc  k
    jmp  pd_over
pd_under0:
    mov  picked, 0
    mov  k, 0
pd_under:
    cmp  k, 3
    jae  pd_done
    mov  best, 7FFFFFFFh
    mov  bestI, 0
    xor  esi, esi
pd_ui:
    bt   picked, esi
    jc   pd_un
    mov  eax, taPm[esi*4]
    sub  eax, eng1000[esi*4]
    cmp  eax, best
    jge  pd_un
    mov  best, eax
    mov  bestI, esi
pd_un:
    inc  esi
    cmp  esi, 26
    jb   pd_ui
    mov  eax, bestI
    bts  picked, eax
    mov  ecx, k
    mov  taUnder[ecx*4], eax
    mov  edx, best
    mov  taUnderD[ecx*4], edx
    inc  k
    jmp  pd_under
pd_done:
    ret
PickDiffs ENDP

; ---- text analysis of the letters typed: entropy, English overlap,
;      chi-squared and the Caesar shift (x87 FPU for log2) ----
AnalyzeText PROC USES ebx esi edi
    xor  eax, eax
    mov  taN, eax
    mov  taH100, eax
    mov  taOverlap, eax
    mov  taChi10, eax
    mov  taShift, eax
    mov  taUnique, eax
    mov  taRedund, eax
    mov  taValid, eax
    xor  esi, esi                   ; letter counts, upper + lower case
    xor  ebx, ebx
at_cnt:
    mov  eax, freq[esi*4 + 'A'*4]
    add  eax, freq[esi*4 + 'a'*4]
    mov  taCnt[esi*4], eax
    add  ebx, eax
    test eax, eax
    jz   at_cnext
    inc  taUnique
at_cnext:
    inc  esi
    cmp  esi, 26
    jb   at_cnt
    mov  taN, ebx
    test ebx, ebx
    jz   at_done

    xor  esi, esi                   ; shares in 0.1 % and overlap with English
    xor  edi, edi
at_pm:
    mov  eax, taCnt[esi*4]
    mov  edx, 1000
    mul  edx
    div  ebx
    mov  taPm[esi*4], eax
    mov  ecx, eng1000[esi*4]
    cmp  eax, ecx
    jbe  at_min
    mov  eax, ecx
at_min:
    add  edi, eax
    inc  esi
    cmp  esi, 26
    jb   at_pm
    mov  eax, edi
    xor  edx, edx
    mov  ecx, 10
    div  ecx
    mov  taOverlap, eax

    fldz                            ; H = log2(n) - sum(c * log2 c) / n
    xor  esi, esi
at_h:
    cmp  taCnt[esi*4], 0
    je   at_hnext
    fild taCnt[esi*4]
    fild taCnt[esi*4]
    fyl2x                           ; c * log2(c)
    faddp st(1), st
at_hnext:
    inc  esi
    cmp  esi, 26
    jb   at_h
    fild taN
    fdivp st(1), st                 ; sum / n
    fld1
    fild taN
    fyl2x                           ; log2(n)
    fsubrp st(1), st                ; log2(n) - sum / n
    fmul fHundred
    fistp taH100

    mov  eax, 470                   ; redundancy = 1 - H / log2(26)
    sub  eax, taH100
    jle  at_chi
    imul eax, eax, 100
    xor  edx, edx
    mov  ecx, 470
    div  ecx
    mov  taRedund, eax
at_chi:
    invoke ChiShift, 0
    mov  taChi10, eax
    mov  edi, eax                   ; Caesar: rotation with the smallest chi-squared
    mov  esi, 1
at_shift:
    invoke ChiShift, esi
    cmp  eax, edi
    jae  at_snext
    mov  edi, eax
    mov  taShift, esi
at_snext:
    inc  esi
    cmp  esi, 26
    jb   at_shift
    cmp  taN, MIN_LETTERS
    jb   at_diffs
    mov  taValid, 1
at_diffs:
    invoke PickDiffs
at_done:
    ret
AnalyzeText ENDP

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
