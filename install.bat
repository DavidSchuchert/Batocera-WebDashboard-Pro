@echo off
echo ================================================
echo Batocera WebDashboard PRO -- Installer (Windows)
echo ================================================
echo.

:: Check for WSL
where wsl.exe >nul 2>&1
if %errorlevel% equ 0 (
    echo [OK] WSL found. Running Linux installer...
    wsl bash ./install.sh %*
    goto :eof
)

:: Check for Git Bash
where bash.exe >nul 2>&1
if %errorlevel% equ 0 (
    echo [OK] Git Bash found. Running...
    bash ./install.sh %*
    goto :eof
)

:: Neither found
echo [ERROR] This installer requires WSL or Git Bash.
echo.
echo To install WSL (Windows Subsystem for Linux):
echo   1. Open PowerShell as Administrator
echo   2. Run: wsl --install
echo   3. Restart your PC
echo   4. Run this installer again
echo.
echo To install Git Bash:
echo   https://git-scm.com/download/win
echo.
pause
