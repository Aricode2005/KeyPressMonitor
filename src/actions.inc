; src/actions.inc - actions (reset, save, CSV/JSON, views) and keyboard / mouse input
; Part of KeyMonitor.asm (included in order; see the INCLUDE list there).

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
    lea  edi, keyLatSum             ; keyLatSum, keyLatCnt, errKey
    mov  ecx, 256 * 3
    rep  stosd
    mov  keyLatPrev, eax
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

; ---- 0 reset, 1 save, 2 pause, 3 quit, 4 autosave, 5 typing test, 6 bio/XP, 7 theme, 8 sound, 9 help ----
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
    cmp  viewMode, 2                ; F6 cycles: biomechanics -> text analysis -> dashboard
    je   da_to_text
    cmp  viewMode, 3
    je   da_to_dash
    mov  viewMode, 2
    invoke SetMsg, ADDR sMsgErgo, C_CYAN
    ret
da_to_text:
    mov  viewMode, 3
    invoke SetMsg, ADDR sMsgText, C_CYAN
    ret
da_to_dash:
    mov  viewMode, 0
    invoke SetMsg, ADDR sMsgDash, C_CYAN
    ret
da_theme:
    cmp  eax, 7
    jne  da_help
    mov  eax, themeIdx
    inc  eax
    and  eax, 3
    mov  themeIdx, eax
    invoke ApplyTheme
    mov  eax, themeIdx
    mov  eax, themeMsgs[eax*4]
    invoke SetMsg, eax, C_GREEN
    ret
da_help:
    cmp  eax, 9
    jne  da_sound
    xor  helpOn, 1
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
    jne  hk_f9
    invoke DoAction, 8
    ret
hk_f9:
    cmp  ebx, VK_F9
    jne  hk_f10
    invoke DoAction, 9
    ret
hk_f10:
    cmp  ebx, VK_F10
    jne  hk_up
    invoke StartReplay
    ret
hk_up:
    cmp  ebx, VK_UP
    jne  hk_down
    invoke HeatStep, 1
    ret
hk_down:
    cmp  ebx, VK_DOWN
    jne  hk_tab
    invoke HeatStep, -1
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
    cmp  replayOn, 0                ; live keys are ignored during a replay
    jne  hk_done
hk_rep:
    invoke RecKey, esi, ebx
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
    jne  hm_heat
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
hm_heat:                            ; click on the heatmap: next mode
    cmp  viewMode, 0
    jne  hm_done
    cmp  mouseY, 12
    jl   hm_done
    cmp  mouseY, 18
    jg   hm_done
    cmp  mouseX, 59
    jl   hm_done
    cmp  mouseX, 97
    jg   hm_done
    invoke HeatStep, 1
    ret
hm_done:
    ret
HandleMouse ENDP
