; src/selftest.inc - self-test mode (KeyMonitor.exe /selftest)
; Part of KeyMonitor.asm (included in order; see the INCLUDE list there).

; =============================================================
;  Self-test (KeyMonitor.exe /selftest): feeds a known sentence
;  through the counting code and checks every result. Prints to
;  stdout (works when redirected, e.g. in CI); exit code = failures.
; =============================================================

; ---- write a string to stdout ----
StOut PROC pStr:DWORD
    invoke StrLen, pStr
    invoke WriteFile, stdOut, pStr, eax, ADDR nWritten, 0
    ret
StOut ENDP

; ---- write a number to stdout ----
StNum PROC val:DWORD
    invoke NumToStr, val
    invoke StOut, eax
    ret
StNum ENDP

; ---- does the command line contain pNeedle? eax = 1 / 0 ----
CmdHas PROC USES esi edi pNeedle:DWORD
    invoke GetCommandLineA
    mov  esi, eax
ch_start:
    cmp  BYTE PTR [esi], 0
    je   ch_no
    mov  edi, pNeedle
    xor  ecx, ecx
ch_cmp:
    mov  al, [edi+ecx]
    test al, al
    jz   ch_yes
    cmp  al, [esi+ecx]
    jne  ch_next
    inc  ecx
    jmp  ch_cmp
ch_next:
    inc  esi
    jmp  ch_start
ch_yes:
    mov  eax, 1
    ret
ch_no:
    xor  eax, eax
    ret
CmdHas ENDP

; ---- run the self-test; eax = number of failed checks ----
RunSelfTest PROC USES ebx esi edi
    LOCAL fails:DWORD, passes:DWORD
    invoke GetStdHandle, STD_OUTPUT_HANDLE
    mov  stdOut, eax
    invoke StOut, ADDR stTitle

    mov  esi, OFFSET stInput        ; type the test sentence
st_feed:
    movzx ebx, BYTE PTR [esi]
    test ebx, ebx
    jz   st_fed
    mov  eax, ebx                   ; virtual key: letters are upper case
    cmp  eax, 'a'
    jb   st_vk
    cmp  eax, 'z'
    ja   st_vk
    sub  eax, 20h
st_vk:
    invoke CountChar, ebx, eax
    inc  esi
    jmp  st_feed
st_fed:
    invoke ComputeTop5
    invoke AnalyzeText

    mov  stLastOk, 1                ; last N view must end with the expected glyphs
    xor  ecx, ecx
st_last:
    cmp  ecx, ST_LASTN
    jae  st_checks
    mov  eax, lastHead
    sub  eax, ST_LASTN
    add  eax, ecx
    and  eax, NMAX - 1
    mov  dl, lastRing[eax]
    cmp  dl, stLastExp[ecx]
    je   st_lnext
    mov  stLastOk, 0
st_lnext:
    inc  ecx
    jmp  st_last

st_checks:                          ; each check: name, address of a DWORD, expected value
    mov  fails, 0
    mov  passes, 0
    mov  esi, OFFSET stChecks
st_loop:
    mov  eax, [esi]
    test eax, eax
    jz   st_sum
    mov  edi, [esi+4]
    mov  edi, [edi]                 ; actual value
    cmp  edi, [esi+8]
    jne  st_fail
    inc  passes
    invoke StOut, ADDR stPass
    invoke StOut, DWORD PTR [esi]
    invoke StNum, edi
    jmp  st_eol
st_fail:
    inc  fails
    invoke StOut, ADDR stFail
    invoke StOut, DWORD PTR [esi]
    invoke StOut, ADDR stGot
    invoke StNum, edi
    invoke StOut, ADDR stExpected
    invoke StNum, DWORD PTR [esi+8]
st_eol:
    invoke StOut, ADDR crlf
    add  esi, 12
    jmp  st_loop

st_sum:
    invoke StOut, ADDR stResult
    invoke StNum, passes
    invoke StOut, ADDR stOf
    mov  eax, passes
    add  eax, fails
    invoke StNum, eax
    mov  eax, OFFSET stAllOk
    cmp  fails, 0
    je   st_end
    mov  eax, OFFSET stSomeBad
st_end:
    invoke StOut, eax
    mov  eax, fails
    ret
RunSelfTest ENDP
