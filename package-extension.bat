@echo off
REM Package the Chrome Extension into KeyPressMonitor-Chrome-Extension.zip for Chrome Web Store upload
powershell -NoProfile -Command "$ProgressPreference='SilentlyContinue'; Add-Type -AssemblyName System.IO.Compression.FileSystem; Remove-Item 'KeyPressMonitor-Chrome-Extension.zip' -ErrorAction SilentlyContinue; [System.IO.Compression.ZipFile]::CreateFromDirectory('chrome-extension', 'KeyPressMonitor-Chrome-Extension.zip')"
if errorlevel 1 goto fail
echo Packaged Chrome Extension: KeyPressMonitor-Chrome-Extension.zip
goto end
:fail
echo Packaging FAILED.
:end
