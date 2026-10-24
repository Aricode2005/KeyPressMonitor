; =============================================================
;  KeyMonitor.asm  -  Real-time Key Press Monitor (MASM, 32-bit)
;
;  Features:
;   1. Counts vowels and consonants typed
;   2. Keeps frequency of every key pressed (ASCII 0-255)
;   3. Shows the last N characters typed
;
;  Press ESC to stop and see the frequency report.
;  Uses only kernel32.lib (comes with Visual Studio / Windows SDK).
; =============================================================

.386
.model flat, stdcall
option casemap:none

; ---------- Windows API prototypes ----------
GetStdHandle    PROTO :DWORD
SetConsoleMode  PROTO :DWORD, :DWORD
ReadConsoleA    PROTO :DWORD, :DWORD, :DWORD, :DWORD, :DWORD
WriteConsoleA   PROTO :DWORD, :DWORD, :DWORD, :DWORD, :DWORD
ExitProcess     PROTO :DWORD
includelib kernel32.lib

STD_INPUT_HANDLE  EQU -10
STD_OUTPUT_HANDLE EQU -11
N                 EQU 10          ; how many last characters to show
KEY_ESC           EQU 27

.data
hIn         DD ?
hOut        DD ?
inChar      DB ?, ?
nRead       DD ?
nWritten    DD ?

vowels      DD 0
consonants  DD 0
freq        DD 256 DUP(0)         ; frequency table
lastBuf     DB N DUP(' '), 0      ; last N chars (zero terminated)
numBuf      DB 12 DUP(0)

msgTitle    DB "===== Real-Time Key Press Monitor (MASM) =====", 13, 10
            DB "Start typing... Press ESC to stop.", 13, 10, 13, 10, 0
msgKey      DB 13, 10, "Key: ", 0
msgVow      DB "  | Vowels: ", 0
msgCon      DB "  | Consonants: ", 0
msgLast     DB "  | Last 10: [", 0
msgClose    DB "]", 0
msgReport   DB 13, 10, 13, 10, "========== FINAL REPORT ==========", 13, 10, 0
msgTotV     DB "Total Vowels     : ", 0
msgTotC     DB "Total Consonants : ", 0
msgFreq     DB 13, 10, "Key Frequency:", 13, 10, 0
msgCode     DB "  code ", 0
msgAscii    DB "   (ASCII ", 0
msgSep      DB ")  ->  ", 0
msgBye      DB 13, 10, "Press any key to exit...", 0
newline     DB 13, 10, 0
vowelList   DB "aeiou", 0

.code

; ---- print zero-terminated string ----
PrintStr PROC USES edi pStr:DWORD
    mov  edi, pStr
    xor  ecx, ecx
@@: cmp  BYTE PTR [edi+ecx], 0
    je   @F
    inc  ecx
    jmp  @B
@@: invoke WriteConsoleA, hOut, pStr, ecx, ADDR nWritten, 0
    ret
PrintStr ENDP

; ---- print one character ----
PrintChar PROC chv:DWORD
    invoke WriteConsoleA, hOut, ADDR chv, 1, ADDR nWritten, 0
    ret
PrintChar ENDP

; ---- print unsigned number in decimal ----
PrintNum PROC USES ebx edi val:DWORD
    mov  eax, val
    lea  edi, numBuf + 11
    mov  BYTE PTR [edi], 0
    mov  ebx, 10
@@: dec  edi
    xor  edx, edx
    div  ebx
    add  dl, '0'
    mov  [edi], dl
    test eax, eax
    jnz  @B
    invoke PrintStr, edi
    ret
PrintNum ENDP

; ---- read ONE key (no Enter needed, no echo) ----
ReadKey PROC
@@: invoke ReadConsoleA, hIn, ADDR inChar, 1, ADDR nRead, 0
    cmp  nRead, 0
    je   @B
    movzx eax, inChar
    ret
ReadKey ENDP

; =================== MAIN ===================
start:
    invoke GetStdHandle, STD_INPUT_HANDLE
    mov  hIn, eax
    invoke GetStdHandle, STD_OUTPUT_HANDLE
    mov  hOut, eax
    invoke SetConsoleMode, hIn, 0      ; raw mode: no line buffer, no echo

    invoke PrintStr, ADDR msgTitle

mainLoop:
    call ReadKey                       ; eax = key code
    cmp  eax, KEY_ESC
    je   showReport
    mov  ebx, eax                      ; keep key in ebx

    ; ---- 1) frequency ----
    inc  freq[ebx*4]

    ; ---- 2) shift last-N buffer left, add new char ----
    cld
    lea  esi, lastBuf + 1
    lea  edi, lastBuf
    mov  ecx, N - 1
    rep  movsb
    mov  al, bl
    cmp  al, 32                        ; non-printable -> '.'
    jb   notPrint
    cmp  al, 126
    jbe  storeIt
notPrint:
    mov  al, '.'
storeIt:
    mov  lastBuf[N-1], al

    ; ---- 3) vowel / consonant check ----
    mov  al, bl
    cmp  al, 'A'
    jb   showStatus
    cmp  al, 'Z'
    jbe  makeLower
    cmp  al, 'a'
    jb   showStatus
    cmp  al, 'z'
    ja   showStatus
    jmp  isLetter
makeLower:
    or   al, 20h                       ; to lowercase
isLetter:
    lea  esi, vowelList
checkV:
    mov  dl, [esi]
    test dl, dl
    jz   gotConsonant
    cmp  al, dl
    je   gotVowel
    inc  esi
    jmp  checkV
gotVowel:
    inc  vowels
    jmp  showStatus
gotConsonant:
    inc  consonants

    ; ---- display live status ----
showStatus:
    invoke PrintStr, ADDR msgKey
    movzx eax, lastBuf[N-1]
    invoke PrintChar, eax
    invoke PrintStr, ADDR msgVow
    invoke PrintNum, vowels
    invoke PrintStr, ADDR msgCon
    invoke PrintNum, consonants
    invoke PrintStr, ADDR msgLast
    invoke PrintStr, ADDR lastBuf
    invoke PrintStr, ADDR msgClose
    jmp  mainLoop

; =================== REPORT ===================
showReport:
    invoke PrintStr, ADDR msgReport
    invoke PrintStr, ADDR msgTotV
    invoke PrintNum, vowels
    invoke PrintStr, ADDR newline
    invoke PrintStr, ADDR msgTotC
    invoke PrintNum, consonants
    invoke PrintStr, ADDR newline
    invoke PrintStr, ADDR msgFreq

    xor  esi, esi                      ; esi = ASCII code 0..255
freqLoop:
    cmp  freq[esi*4], 0
    je   nextKey
    cmp  esi, 33                       ; printable (not space)?
    jb   printCode
    cmp  esi, 126
    ja   printCode
    invoke PrintChar, ' '
    invoke PrintChar, ' '
    invoke PrintChar, esi
    invoke PrintChar, ' '
    invoke PrintChar, ' '
    invoke PrintChar, ' '
    jmp  printCount
printCode:
    invoke PrintStr, ADDR msgCode
printCount:
    invoke PrintStr, ADDR msgAscii
    invoke PrintNum, esi
    invoke PrintStr, ADDR msgSep
    invoke PrintNum, freq[esi*4]
    invoke PrintStr, ADDR newline
nextKey:
    inc  esi
    cmp  esi, 256
    jb   freqLoop

    invoke PrintStr, ADDR msgBye
    call ReadKey
    invoke ExitProcess, 0
end start
