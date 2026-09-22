@echo off
setlocal
cd /d "%~dp0"

if exist "%~dp0GitLocal.exe" (
  start "" "%~dp0GitLocal.exe"
  exit /b 0
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0src\GitLocal.App.ps1"
if errorlevel 1 (
  echo.
  echo Git Local 실행에 실패했습니다.
  pause
)
