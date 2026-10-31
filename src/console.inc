; src/console.inc - console setup and restore
; Part of KeyMonitor.asm (included in order; see the INCLUDE list there).

; =============================================================
;  Console setup / restore
; =============================================================

; ---- configure console input/output, palette, cursor and window size ----
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

; ---- undo SetupScreen: palette, cursor, code page, input mode ----
RestoreScreen PROC USES ebx
    cmp  vtOK, 0
    je   rs_pal
    mov  vtLen, 0                   ; default colours, clear, show cursor
    invoke EmitA, ADDR vtReset
    invoke WriteConsoleW, hOut, ADDR vtBuf, vtLen, ADDR nWritten, 0
    invoke SetConsoleMode, hOut, oldOutMode
rs_pal:
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

; ---- print a zero-terminated string with WriteConsoleA ----
ConPrint PROC pStr:DWORD
    invoke StrLen, pStr
    invoke WriteConsoleA, hOut, pStr, eax, ADDR nWritten, 0
    ret
ConPrint ENDP
