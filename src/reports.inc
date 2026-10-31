; src/reports.inc - text and HTML reports
; Part of KeyMonitor.asm (included in order; see the INCLUDE list there).

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

; ---- report builder: value x10 with one decimal ----
AppDec1 PROC USES ebx v10:DWORD
    mov  eax, v10
    xor  edx, edx
    mov  ecx, 10
    div  ecx
    mov  ebx, edx
    invoke AppNum, eax
    invoke AppCh, '.'
    add  ebx, '0'
    invoke AppCh, ebx
    ret
AppDec1 ENDP

; ---- report builder: value x100 with two decimals ----
AppDec2 PROC USES ebx v100:DWORD
    mov  eax, v100
    xor  edx, edx
    mov  ecx, 100
    div  ecx
    mov  ebx, edx
    invoke AppNum, eax
    invoke AppCh, '.'
    invoke AppTwo, ebx
    ret
AppDec2 ENDP

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
    invoke AnalyzeText
    invoke AppStr, ADDR rpEnt
    invoke AppDec2, taH100
    invoke AppStr, ADDR rpBits
    invoke AppLine, ADDR rpOvl, taOverlap
    invoke AppStr, ADDR rpChi
    invoke AppDec1, taChi10
    invoke AppStr, ADDR crlf
    invoke AppLine, ADDR rpCae, taShift
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

; ---- HTML stat card with a decimal value (x10 or x100) ----
AppCardDec PROC pLabel:DWORD, val:DWORD, clr:DWORD, decs:DWORD, pSub:DWORD
    invoke AppStr, ADDR hCard1
    invoke AppStr, pLabel
    invoke AppStr, ADDR hCard2
    invoke AppHex, clr
    invoke AppStr, ADDR hCard3
    cmp  decs, 2
    je   acd_two
    invoke AppDec1, val
    jmp  acd_sub
acd_two:
    invoke AppDec2, val
acd_sub:
    invoke AppStr, ADDR hCard4
    invoke AppStr, pSub
    invoke AppStr, ADDR hCardEnd
    ret
AppCardDec ENDP

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

bh_bars:                            ; ---- text analysis cards ----
    invoke AnalyzeText
    invoke AppStr, ADDR hTaHead
    invoke AppCardDec, ADDR hlEnt, taH100, C_CYAN, 2, ADDR hlEntSub
    invoke AppCardOpen, ADDR hlOvl, taOverlap, C_GREEN
    invoke AppStr, ADDR hlOvlSub
    invoke AppStr, ADDR hCardEnd
    invoke AppCardDec, ADDR hlChi, taChi10, C_AMBER, 1, ADDR hlChiSub
    invoke AppCardOpen, ADDR hlCae, taShift, C_PURP
    invoke AppStr, ADDR hlCaeSub
    invoke AppStr, ADDR hCardEnd
    invoke AppStr, ADDR hGridEnd
                                    ; ---- letter frequency bars ----
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
