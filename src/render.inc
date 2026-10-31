; src/render.inc - canvas primitives and console output (VT / 16-colour)
; Part of KeyMonitor.asm (included in order; see the INCLUDE list there).

; =============================================================
;  Canvas primitives - everything is drawn into 'canvas' first.
;  A cell is 3 DWORDs: Unicode character, foreground colour and
;  background colour (COLORREF 00BBGGRRh). C_KEEP leaves a colour
;  unchanged, so text can be drawn over a panel or gradient.
; =============================================================

; ---- put one character with colours (clipped to the canvas) ----
Cell PROC px:DWORD, py:DWORD, chv:DWORD, fg:DWORD, bg:DWORD
    mov  eax, px
    cmp  eax, SCR_W
    jae  ce_done
    mov  edx, py
    cmp  edx, SCR_H
    jae  ce_done
    imul edx, edx, SCR_W
    add  edx, eax
    lea  edx, [edx+edx*2]           ; 3 DWORDs per cell
    mov  eax, chv
    mov  canvas[edx*4], eax
    mov  eax, fg
    cmp  eax, C_KEEP
    je   ce_bg
    mov  canvas[edx*4+4], eax
ce_bg:
    mov  eax, bg
    cmp  eax, C_KEEP
    je   ce_done
    mov  canvas[edx*4+8], eax
ce_done:
    ret
Cell ENDP

; ---- CP437 byte (as used in our strings) -> Unicode character ----
GlyphW PROC b:DWORD
    mov  eax, b
    and  eax, 0FFh
    cmp  eax, 80h
    jb   gw_done
    movzx eax, cp437W[eax*2 - 100h]
gw_done:
    ret
GlyphW ENDP

; ---- fill a rectangle with one character / colours ----
Fill PROC USES ebx esi px:DWORD, py:DWORD, wd:DWORD, ht:DWORD, chv:DWORD, fg:DWORD, bg:DWORD
    xor  esi, esi
fi_row:
    cmp  esi, ht
    jae  fi_done
    xor  ebx, ebx
fi_col:
    cmp  ebx, wd
    jae  fi_next
    mov  eax, px
    add  eax, ebx
    mov  edx, py
    add  edx, esi
    invoke Cell, eax, edx, chv, fg, bg
    inc  ebx
    jmp  fi_col
fi_next:
    inc  esi
    jmp  fi_row
fi_done:
    ret
Fill ENDP

; ---- zero-terminated byte string; returns eax = x after the text ----
Text PROC USES ebx esi px:DWORD, py:DWORD, pStr:DWORD, fg:DWORD, bg:DWORD
    mov  esi, pStr
    mov  ebx, px
tx_loop:
    movzx eax, BYTE PTR [esi]
    test eax, eax
    jz   tx_done
    invoke GlyphW, eax
    invoke Cell, ebx, py, eax, fg, bg
    inc  esi
    inc  ebx
    jmp  tx_loop
tx_done:
    mov  eax, ebx
    ret
Text ENDP

; ---- length of zero-terminated string ----
StrLen PROC pStr:DWORD
    mov  edx, pStr
    xor  eax, eax
sl_loop:
    cmp  BYTE PTR [edx+eax], 0
    je   sl_done
    inc  eax
    jmp  sl_loop
sl_done:
    ret
StrLen ENDP

; ---- unsigned number -> decimal text; eax = pointer, ecx = length ----
NumToStr PROC USES ebx edi val:DWORD
    lea  edi, numBuf + 15
    mov  BYTE PTR [edi], 0
    mov  eax, val
    mov  ebx, 10
nts_loop:
    dec  edi
    xor  edx, edx
    div  ebx
    add  dl, '0'
    mov  [edi], dl
    test eax, eax
    jnz  nts_loop
    lea  ecx, numBuf + 15
    sub  ecx, edi
    mov  eax, edi
    ret
NumToStr ENDP

; ---- number, left aligned; returns eax = x after the text ----
Num PROC px:DWORD, py:DWORD, val:DWORD, fg:DWORD
    invoke NumToStr, val
    invoke Text, px, py, eax, fg, C_KEEP
    ret
Num ENDP

; ---- number, right aligned so its last digit is at column pxr ----
NumR PROC pxr:DWORD, py:DWORD, val:DWORD, fg:DWORD
    invoke NumToStr, val
    mov  edx, pxr
    sub  edx, ecx
    inc  edx
    invoke Text, edx, py, eax, fg, C_KEEP
    ret
NumR ENDP

; ---- two digits with leading zero (0-99) ----
Two PROC px:DWORD, py:DWORD, val:DWORD, fg:DWORD
    mov  eax, val
    xor  edx, edx
    mov  ecx, 10
    div  ecx
    push edx
    add  eax, '0'
    invoke Cell, px, py, eax, fg, C_KEEP
    pop  edx
    add  edx, '0'
    mov  eax, px
    inc  eax
    invoke Cell, eax, py, edx, fg, C_KEEP
    ret
Two ENDP

; ---- seconds as mm:ss ----
TimeMS PROC px:DWORD, py:DWORD, secs:DWORD, fg:DWORD
    mov  eax, secs
    xor  edx, edx
    mov  ecx, 60
    div  ecx
    cmp  eax, 99
    jbe  tm_ok
    mov  eax, 99
tm_ok:
    push edx
    invoke Two, px, py, eax, fg
    mov  eax, px
    add  eax, 2
    invoke Cell, eax, py, ':', fg, C_KEEP
    pop  edx
    mov  eax, px
    add  eax, 3
    invoke Two, eax, py, edx, fg
    ret
TimeMS ENDP

; ---- blend two colours: c1 + (c2 - c1) * t / tmax, per channel ----
Lerp PROC USES ebx esi edi c1:DWORD, c2:DWORD, t:DWORD, tmax:DWORD
    mov  eax, c1                    ; empty range -> first colour
    cmp  tmax, 0
    jle  lp_ret
    mov  eax, t                     ; clamp t to 0..tmax
    cmp  eax, tmax
    jle  lp_lo
    mov  eax, tmax
lp_lo:
    test eax, eax
    jns  lp_t
    xor  eax, eax
lp_t:
    mov  t, eax
    xor  edi, edi                   ; result
    xor  esi, esi                   ; channel shift: 0, 8, 16
lp_ch:
    mov  ecx, esi
    mov  eax, c1
    shr  eax, cl
    and  eax, 0FFh
    mov  ebx, c2
    shr  ebx, cl
    and  ebx, 0FFh
    sub  ebx, eax                   ; signed difference
    push eax
    mov  eax, ebx
    imul t
    idiv tmax
    pop  ebx
    add  eax, ebx
    and  eax, 0FFh
    mov  ecx, esi
    shl  eax, cl
    or   edi, eax
    add  esi, 8
    cmp  esi, 24
    jb   lp_ch
    mov  eax, edi
lp_ret:
    ret
Lerp ENDP

; ---- colour at position t/tmax along a list of colour stops ----
Ramp PROC USES ebx pStops:DWORD, nStops:DWORD, t:DWORD, tmax:DWORD
    mov  eax, nStops
    dec  eax
    mul  t                          ; segment position = t * (n-1)
    div  tmax                       ; eax = stop index, edx = remainder
    mov  ecx, nStops
    sub  ecx, 2
    cmp  eax, ecx
    jbe  rp_ok
    mov  eax, ecx                   ; t = tmax -> end of the last segment
    mov  edx, tmax
rp_ok:
    mov  ebx, pStops
    invoke Lerp, DWORD PTR [ebx+eax*4], DWORD PTR [ebx+eax*4+4], edx, tmax
    ret
Ramp ENDP

; ---- panel with a rounded border and a title in the top edge ----
RBox PROC USES ebx esi edi px:DWORD, py:DWORD, wd:DWORD, ht:DWORD, pTitle:DWORD, bc:DWORD, tc:DWORD
    invoke Fill, px, py, wd, ht, ' ', C_TEXT, C_PANEL
    mov  esi, px
    add  esi, wd
    dec  esi                        ; esi = right column
    mov  edi, py
    add  edi, ht
    dec  edi                        ; edi = bottom row
    mov  ebx, px
rb_h:
    cmp  ebx, esi
    ja   rb_v0
    invoke Cell, ebx, py, 2500h, bc, C_KEEP
    invoke Cell, ebx, edi, 2500h, bc, C_KEEP
    inc  ebx
    jmp  rb_h
rb_v0:
    mov  ebx, py
rb_v:
    cmp  ebx, edi
    ja   rb_c
    invoke Cell, px, ebx, 2502h, bc, C_KEEP
    invoke Cell, esi, ebx, 2502h, bc, C_KEEP
    inc  ebx
    jmp  rb_v
rb_c:
    invoke Cell, px, py, 256Dh, bc, C_KEEP      ; rounded corners
    invoke Cell, esi, py, 256Eh, bc, C_KEEP
    invoke Cell, px, edi, 2570h, bc, C_KEEP
    invoke Cell, esi, edi, 256Fh, bc, C_KEEP
    cmp  pTitle, 0
    je   rb_done
    mov  eax, px
    add  eax, 2
    invoke Text, eax, py, pTitle, tc, C_KEEP
rb_done:
    ret
RBox ENDP

; ---- big 3-row number; colour fades from c1 (top) to c2 (bottom) ----
BigNum PROC USES ebx esi edi px:DWORD, py:DWORD, val:DWORD, c1:DWORD, c2:DWORD
    LOCAL row:DWORD, col:DWORD, rc:DWORD
    invoke NumToStr, val
    mov  esi, eax
    mov  ebx, px
bn_digit:
    movzx eax, BYTE PTR [esi]
    test eax, eax
    jz   bn_done
    sub  eax, '0'
    imul edi, eax, 9
    add  edi, OFFSET bigFont
    mov  row, 0
bn_row:
    invoke Lerp, c1, c2, row, 2
    mov  rc, eax
    mov  col, 0
bn_col:
    movzx eax, BYTE PTR [edi]
    cmp  eax, ' '
    je   bn_skip
    invoke GlyphW, eax
    mov  ecx, ebx
    add  ecx, col
    mov  edx, py
    add  edx, row
    invoke Cell, ecx, edx, eax, rc, C_KEEP
bn_skip:
    inc  edi
    inc  col
    cmp  col, 3
    jb   bn_col
    inc  row
    cmp  row, 3
    jb   bn_row
    add  ebx, 4
    inc  esi
    jmp  bn_digit
bn_done:
    ret
BigNum ENDP

; ---- vertical bar cell: e = filled eighths (1-8) -> block character ----
Eighth PROC e:DWORD
    mov  eax, e
    cmp  eax, 8
    jb   eg_part
    mov  eax, 2588h                 ; full block
    ret
eg_part:
    add  eax, 2580h                 ; U+2581..U+2587 lower blocks
    ret
Eighth ENDP

; ---- sparkline of the newest wd samples of a ring buffer ----
Spark PROC USES ebx esi edi px:DWORD, py:DWORD, wd:DWORD, pRing:DWORD, rmask:DWORD, head:DWORD, cnt:DWORD, c1:DWORD, c2:DWORD
    LOCAL n:DWORD, mx:DWORD, last:DWORD
    mov  eax, cnt
    cmp  eax, wd
    jbe  sk_n
    mov  eax, wd
sk_n:
    mov  n, eax
    test eax, eax
    jz   sk_done
    dec  eax
    jnz  sk_last
    inc  eax
sk_last:
    mov  last, eax                  ; max(n-1, 1) for the colour fade
    mov  mx, 1
    mov  ebx, pRing
    xor  esi, esi
sk_max:
    cmp  esi, n
    jae  sk_draw
    mov  eax, head
    sub  eax, n
    add  eax, esi
    and  eax, rmask
    mov  eax, [ebx+eax*4]
    cmp  eax, mx
    jbe  sk_mnext
    mov  mx, eax
sk_mnext:
    inc  esi
    jmp  sk_max
sk_draw:
    xor  esi, esi
sk_loop:
    cmp  esi, n
    jae  sk_done
    mov  eax, head
    sub  eax, n
    add  eax, esi
    and  eax, rmask
    mov  eax, [ebx+eax*4]
    mov  edx, 7                     ; level 0-7
    mul  edx
    div  mx
    lea  edi, [eax+2581h]
    invoke Lerp, c2, c1, esi, last
    mov  ecx, px
    add  ecx, wd
    sub  ecx, n
    add  ecx, esi
    invoke Cell, ecx, py, edi, eax, C_KEEP
    inc  esi
    jmp  sk_loop
sk_done:
    ret
Spark ENDP

; =============================================================
;  Output: true colour through VT sequences, or the 16-colour
;  console as a fallback
; =============================================================

; ---- characters the classic console font does not have ----
FineGlyph PROC chv:DWORD
    mov  eax, chv
    cmp  fineGlyphs, 0
    jne  fg_done
    cmp  eax, 25C6h                 ; diamond -> square
    jne  fg_low
    mov  eax, 25A0h
    ret
fg_low:
    cmp  eax, 2581h                 ; lower 1/8 .. 7/8 blocks
    jb   fg_done
    cmp  eax, 2587h
    ja   fg_left
    cmp  eax, 2582h
    ja   fg_half
    mov  eax, '_'
    ret
fg_half:
    cmp  eax, 2585h
    ja   fg_full
    mov  eax, 2584h
    ret
fg_left:
    cmp  eax, 2589h                 ; left 7/8 .. 1/8 blocks
    jb   fg_done
    cmp  eax, 258Fh
    ja   fg_done
    cmp  eax, 258Ch
    je   fg_done
    jb   fg_full
    mov  eax, 258Ch
    ret
fg_full:
    mov  eax, 2588h
fg_done:
    ret
FineGlyph ENDP

; ---- append to the VT output buffer ----
EmitW PROC chv:DWORD
    mov  edx, vtLen
    mov  eax, chv
    mov  vtBuf[edx*2], ax
    inc  vtLen
    ret
EmitW ENDP

EmitA PROC USES esi pStr:DWORD
    mov  esi, pStr
ea_loop:
    movzx eax, BYTE PTR [esi]
    test eax, eax
    jz   ea_done
    invoke EmitW, eax
    inc  esi
    jmp  ea_loop
ea_done:
    ret
EmitA ENDP

EmitNum PROC val:DWORD
    invoke NumToStr, val
    invoke EmitA, eax
    ret
EmitNum ENDP

; ---- "r;g;b" of a colour ----
EmitRGB PROC USES ebx clr:DWORD
    mov  ebx, clr
    movzx eax, bl
    invoke EmitNum, eax
    invoke EmitW, ';'
    movzx eax, bh
    invoke EmitNum, eax
    invoke EmitW, ';'
    shr  ebx, 16
    movzx eax, bl
    invoke EmitNum, eax
    ret
EmitRGB ENDP

; ---- ESC[38;2;r;g;b;48;2;r;g;bm : set foreground and background ----
EmitSgr PROC fg:DWORD, bg:DWORD
    invoke EmitA, ADDR vtCsi
    invoke EmitA, ADDR vtFg
    invoke EmitRGB, fg
    invoke EmitA, ADDR vtBg
    invoke EmitRGB, bg
    invoke EmitW, 'm'
    ret
EmitSgr ENDP

; ---- one WriteConsoleW call per frame, sending only the cells that changed
;      since the last frame (a full frame every 2 s repairs anything the
;      terminal changed by itself) ----
FlushVT PROC USES ebx esi edi
    LOCAL row:DWORD, lastFg:DWORD, lastBg:DWORD, curRow:DWORD, curCol:DWORD, full:DWORD
    mov  vtLen, 0
    invoke EmitA, ADDR vtFrame
    mov  full, 0
    cmp  prevValid, 0
    je   fv_full
    invoke GetTickCount
    sub  eax, lastFullTick
    cmp  eax, FULL_FRAME_MS
    jb   fv_go
fv_full:
    mov  full, 1
    invoke GetTickCount
    mov  lastFullTick, eax
    mov  prevValid, 1
fv_go:
    mov  lastFg, -2
    mov  lastBg, -2
    mov  curRow, -1
    mov  curCol, -1
    mov  row, 0
    lea  esi, canvas
    lea  edi, prevCanvas
fv_row:
    cmp  row, SCR_H
    jae  fv_end
    xor  ebx, ebx
fv_col:
    cmp  ebx, SCR_W
    jae  fv_next
    cmp  full, 0
    jne  fv_draw
    mov  eax, [esi]                 ; unchanged cell -> nothing to send
    cmp  eax, [edi]
    jne  fv_draw
    mov  eax, [esi+4]
    cmp  eax, [edi+4]
    jne  fv_draw
    mov  eax, [esi+8]
    cmp  eax, [edi+8]
    je   fv_skip
fv_draw:
    mov  eax, row                   ; move the cursor unless it is already here
    cmp  eax, curRow
    jne  fv_move
    cmp  ebx, curCol
    je   fv_colour
fv_move:
    invoke EmitA, ADDR vtCsi
    mov  eax, row
    inc  eax
    invoke EmitNum, eax
    invoke EmitW, ';'
    mov  eax, offX
    add  eax, ebx
    inc  eax
    invoke EmitNum, eax
    invoke EmitW, 'H'
    mov  eax, row
    mov  curRow, eax
fv_colour:
    mov  eax, [esi+4]
    mov  edx, [esi+8]
    cmp  eax, lastFg                ; colours only when they change
    jne  fv_sgr
    cmp  edx, lastBg
    je   fv_ch
fv_sgr:
    mov  lastFg, eax
    mov  lastBg, edx
    invoke EmitSgr, eax, edx
fv_ch:
    invoke FineGlyph, DWORD PTR [esi]
    invoke EmitW, eax
    lea  eax, [ebx+1]
    mov  curCol, eax
    mov  eax, [esi]                 ; remember what the terminal now shows
    mov  [edi], eax
    mov  eax, [esi+4]
    mov  [edi+4], eax
    mov  eax, [esi+8]
    mov  [edi+8], eax
fv_skip:
    add  esi, 12
    add  edi, 12
    inc  ebx
    jmp  fv_col
fv_next:
    inc  row
    jmp  fv_row
fv_end:
    invoke EmitA, ADDR vtFrameEnd
    invoke WriteConsoleW, hOut, ADDR vtBuf, vtLen, ADDR nWritten, 0
    ret
FlushVT ENDP

; ---- nearest of the 16 console colours (fallback output) ----
Nearest PROC USES ebx esi edi clr:DWORD
    LOCAL best:DWORD, bestD:DWORD
    mov  bestD, 7FFFFFFFh
    mov  best, 0
    xor  esi, esi
nr_loop:
    cmp  esi, 16
    jae  nr_done
    xor  edi, edi                   ; squared distance
    xor  ecx, ecx
nr_ch:
    mov  eax, clr
    shr  eax, cl
    and  eax, 0FFh
    mov  ebx, palette[esi*4]
    shr  ebx, cl
    and  ebx, 0FFh
    sub  eax, ebx
    imul eax, eax
    add  edi, eax
    add  ecx, 8
    cmp  ecx, 24
    jb   nr_ch
    cmp  edi, bestD
    jae  nr_next
    mov  bestD, edi
    mov  best, esi
nr_next:
    inc  esi
    jmp  nr_loop
nr_done:
    mov  eax, best
    ret
Nearest ENDP

FlushLegacy PROC USES ebx esi edi
    lea  esi, canvas
    lea  edi, legacyBuf
    xor  ebx, ebx
fl_loop:
    cmp  ebx, SCR_W * SCR_H
    jae  fl_write
    invoke Nearest, DWORD PTR [esi+8]
    shl  eax, 4
    push eax
    invoke Nearest, DWORD PTR [esi+4]
    pop  edx
    or   eax, edx
    shl  eax, 16                    ; attribute in the high word
    push eax
    invoke FineGlyph, DWORD PTR [esi]
    pop  edx
    and  eax, 0FFFFh
    or   eax, edx
    mov  [edi], eax
    add  esi, 12
    add  edi, 4
    inc  ebx
    jmp  fl_loop
fl_write:
    mov  eax, offX
    mov  writeRegion, ax
    mov  writeRegion+2, 0
    add  eax, SCR_W - 1
    mov  writeRegion+4, ax
    mov  writeRegion+6, SCR_H - 1
    invoke WriteConsoleOutputW, hOut, ADDR legacyBuf, (SCR_H SHL 16) OR SCR_W, 0, ADDR writeRegion
    ret
FlushLegacy ENDP

Flush PROC
    cmp  vtOK, 0
    je   fl_legacy
    invoke FlushVT
    ret
fl_legacy:
    invoke FlushLegacy
    ret
Flush ENDP
