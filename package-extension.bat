@echo off
REM Package the Chrome Extension into KeyPressMonitor-Chrome-Extension.zip and copy to chrome-extension/ for Render static hosting
powershell -NoProfile -Command "$ProgressPreference='SilentlyContinue'; Add-Type -AssemblyName System.IO.Compression.FileSystem; Remove-Item 'KeyPressMonitor-Chrome-Extension.zip','chrome-extension\KeyPressMonitor-Chrome-Extension.zip','chrome-extension\index.html' -ErrorAction SilentlyContinue; Copy-Item 'chrome-extension\popup.html' 'chrome-extension\index.html' -Force; [System.IO.Compression.ZipFile]::CreateFromDirectory('chrome-extension', 'KeyPressMonitor-Chrome-Extension.zip'); Copy-Item 'KeyPressMonitor-Chrome-Extension.zip' 'chrome-extension\KeyPressMonitor-Chrome-Extension.zip' -Force"
if errorlevel 1 goto fail
echo Packaged Chrome Extension: KeyPressMonitor-Chrome-Extension.zip
goto end
:fail
echo Packaging FAILED.
:end
