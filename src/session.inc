; src/session.inc - typing test and last-session statistics (KeyStats.dat)
; Part of KeyMonitor.asm (included in order; see the INCLUDE list there).

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
    mov  ghostState, eax
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
    movzx eax, BYTE PTR [edx+ebx]   ; remember which key was missed
    invoke MissKey, eax
tk_ok:
    invoke GhostMark                ; time at this position, for the ghost race
    inc  ebx
    mov  testPos, ebx
    cmp  ebx, testLen
    jb   tk_done
    invoke GetTickCount             ; sentence finished
    mov  testEnd, eax
    mov  testDone, 1
    invoke TestLive
    invoke GhostFinish
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
    cmp  recCount, 0                ; nothing typed live (e.g. only a replay)
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
;  Ghost race (KeyGhost.dat) and session replay (KeySession.kpm)
; =============================================================

; ---- time (ms from the start) at the current test position ----
GhostMark PROC
    invoke GetTickCount
    sub  eax, testStart
    mov  ecx, testPos
    cmp  ecx, GHOST_LEN
    jae  gm_done
    mov  testTimes[ecx*4], eax
gm_done:
    ret
GhostMark ENDP

; ---- after a finished sentence: compare with the ghost, keep the faster run ----
GhostFinish PROC USES esi edi
    mov  ecx, testIdx
    mov  eax, ghostWpm[ecx*4]
    mov  edx, tWpm
    test eax, eax
    jnz  gf_have
    mov  ghostState, 1              ; first finished run on this sentence
    jmp  gf_save
gf_have:
    cmp  edx, eax
    jbe  gf_lost
    sub  edx, eax
    mov  ghostDiff, edx
    mov  ghostState, 2              ; ghost beaten
    jmp  gf_save
gf_lost:
    sub  eax, edx
    mov  ghostDiff, eax
    mov  ghostState, 3              ; ghost was faster
    ret
gf_save:
    mov  ecx, testIdx
    mov  eax, tWpm
    mov  ghostWpm[ecx*4], eax
    imul edi, ecx, GHOST_LEN * 4
    add  edi, OFFSET ghostTimes
    lea  esi, testTimes
    mov  ecx, GHOST_LEN
    cld
    rep  movsd
    mov  ghostDirty, 1
    ret
GhostFinish ENDP

; ---- characters the ghost has typed by now; -1 = no ghost for this sentence ----
GhostPos PROC USES esi
    mov  ecx, testIdx
    cmp  ghostWpm[ecx*4], 0
    je   gp_none
    xor  eax, eax
    cmp  testStart, 0
    je   gp_done
    mov  edx, nowTick
    cmp  testDone, 0
    je   gp_t
    mov  edx, testEnd
gp_t:
    sub  edx, testStart             ; edx = ms since the start
    imul esi, ecx, GHOST_LEN * 4
    add  esi, OFFSET ghostTimes
gp_loop:
    cmp  eax, testLen
    jae  gp_done
    cmp  [esi+eax*4], edx
    ja   gp_done
    inc  eax
    jmp  gp_loop
gp_none:
    mov  eax, -1
gp_done:
    ret
GhostPos ENDP

LoadGhosts PROC USES ebx
    invoke CreateFileA, ADDR sGhostFile, 80000000h, 1, 0, 3, 80h, 0
    cmp  eax, -1
    je   lg_done
    mov  ebx, eax
    invoke ReadFile, ebx, ADDR ghostHdr, 4, ADDR nRead, 0
    cmp  ghostHdr, GHOST_MAGIC
    jne  lg_close
    invoke ReadFile, ebx, ADDR ghostWpm, NSENT * 4, ADDR nRead, 0
    invoke ReadFile, ebx, ADDR ghostTimes, NSENT * GHOST_LEN * 4, ADDR nRead, 0
lg_close:
    invoke CloseHandle, ebx
lg_done:
    ret
LoadGhosts ENDP

SaveGhosts PROC USES ebx
    cmp  ghostDirty, 0
    je   sg_done
    invoke CreateFileA, ADDR sGhostFile, 40000000h, 0, 0, 2, 80h, 0
    cmp  eax, -1
    je   sg_done
    mov  ebx, eax
    mov  ghostHdr, GHOST_MAGIC
    invoke WriteFile, ebx, ADDR ghostHdr, 4, ADDR nWritten, 0
    invoke WriteFile, ebx, ADDR ghostWpm, NSENT * 4, ADDR nWritten, 0
    invoke WriteFile, ebx, ADDR ghostTimes, NSENT * GHOST_LEN * 4, ADDR nWritten, 0
    invoke CloseHandle, ebx
sg_done:
    ret
SaveGhosts ENDP

; ---- write this session's keys to KeySession.kpm (for F10 next time) ----
SaveSession PROC USES ebx
    cmp  recCount, 0
    je   ss_done
    invoke CreateFileA, ADDR sSessFile, 40000000h, 0, 0, 2, 80h, 0
    cmp  eax, -1
    je   ss_done
    mov  ebx, eax
    mov  replayHdr, REC_MAGIC
    mov  eax, recCount
    mov  replayHdr+4, eax
    invoke WriteFile, ebx, ADDR replayHdr, 8, ADDR nWritten, 0
    mov  eax, recCount
    shl  eax, 2
    invoke WriteFile, ebx, ADDR recBuf, eax, ADDR nWritten, 0
    invoke CloseHandle, ebx
ss_done:
    ret
SaveSession ENDP

; ---- F10: replay the last recorded session on the dashboard (again = stop) ----
StartReplay PROC USES ebx
    cmp  replayOn, 0
    je   sr_load
    mov  replayOn, 0
    invoke SetMsg, ADDR sMsgReplayStop, C_GOLD
    ret
sr_load:
    invoke CreateFileA, ADDR sSessFile, 80000000h, 1, 0, 3, 80h, 0
    cmp  eax, -1
    je   sr_none
    mov  ebx, eax
    invoke ReadFile, ebx, ADDR replayHdr, 8, ADDR nRead, 0
    cmp  replayHdr, REC_MAGIC
    jne  sr_bad
    mov  eax, replayHdr+4
    test eax, eax
    jz   sr_bad
    cmp  eax, REC_MAX
    ja   sr_bad
    mov  replayCount, eax
    shl  eax, 2
    invoke ReadFile, ebx, ADDR replayBuf, eax, ADDR nRead, 0
    invoke CloseHandle, ebx
    invoke DoReset                  ; start from zero, like the original session
    mov  viewMode, 0
    mov  replayPos, 0
    invoke GetTickCount
    mov  ecx, replayBuf             ; wait of the first key (high word)
    shr  ecx, 16
    add  eax, ecx
    mov  replayNext, eax
    mov  replayOn, 1
    invoke SetMsg, ADDR sMsgReplay, C_PINK
    ret
sr_bad:
    invoke CloseHandle, ebx
sr_none:
    invoke SetMsg, ADDR sMsgNoReplay, C_RED
    ret
StartReplay ENDP

; ---- feed every replayed key whose time has come (called each frame) ----
ReplayTick PROC USES ebx esi
    cmp  replayOn, 0
    je   rt_done
    invoke GetTickCount
    mov  ebx, eax
rt_loop:
    mov  esi, replayPos
    cmp  esi, replayCount
    jae  rt_end
    mov  eax, ebx
    sub  eax, replayNext            ; due yet?
    js   rt_done
    mov  eax, replayBuf[esi*4]
    movzx ecx, al                   ; character
    movzx edx, ah                   ; virtual key
    invoke CountChar, ecx, edx
    inc  replayPos
    mov  esi, replayPos
    cmp  esi, replayCount
    jae  rt_end
    mov  eax, replayBuf[esi*4]
    shr  eax, 16
    add  replayNext, eax
    jmp  rt_loop
rt_end:
    mov  replayOn, 0
    invoke SetMsg, ADDR sMsgReplayEnd, C_OK
rt_done:
    ret
ReplayTick ENDP
