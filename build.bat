@echo off
REM Run this from "x86 Native Tools Command Prompt for VS"
ml /c /coff KeyMonitor.asm
if errorlevel 1 goto fail
link /subsystem:console KeyMonitor.obj kernel32.lib
if errorlevel 1 goto fail
echo.
echo Build OK. Run: KeyMonitor.exe
goto end
:fail
echo Build FAILED.
:end
