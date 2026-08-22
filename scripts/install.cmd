@echo off
rem Altair installer wrapper for Windows cmd.
rem
rem Runs the PowerShell installer, which downloads the binary, verifies
rem its SHA-256 digest and installs it onto PATH. Use:
rem
rem   curl -fsSL https://github.com/Arab-Open-Source/Altair/releases/latest/download/install.cmd | cmd
rem
rem Or download it and run:
rem
rem   install.cmd [--dir DIR] [--force] [--version VER]
setlocal

set "PS1_URL=https://github.com/Arab-Open-Source/Altair/releases/latest/download/install.ps1"
set "TMP_PS1=%TEMP%\altair-install-%RANDOM%-%RANDOM%.ps1"

rem Map the sh-style options to PowerShell parameters.
set "ARGS="
:parse
if "%~1"=="" goto done
if /i "%~1"=="--dir" ( set "ARGS=%ARGS% -Dir \"%~2\"" & shift & shift & goto parse )
if /i "%~1"=="--force" ( set "ARGS=%ARGS% -Force" & shift & goto parse )
if /i "%~1"=="--version" ( set "ARGS=%ARGS% -Version \"%~2\"" & shift & shift & goto parse )
echo error: unknown option: %~1
exit /b 1
:done

echo Downloading the Altair installer ...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri '%PS1_URL%' -OutFile '%TMP_PS1%' -UseBasicParsing -MaximumRedirection 5 -TimeoutSec 30"
if errorlevel 1 (
  echo error: failed to download the installer
  del /q "%TMP_PS1%" 2>nul
  exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%TMP_PS1%" %ARGS%
set "RESULT=%ERRORLEVEL%"
del /q "%TMP_PS1%" 2>nul
exit /b %RESULT%