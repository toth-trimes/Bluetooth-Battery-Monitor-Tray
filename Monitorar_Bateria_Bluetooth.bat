@echo off
title Monitor de Bateria Bluetooth
chcp 65001 >nul
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0monitor_bateria_bluetooth.ps1" %*
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo O programa foi encerrado com codigo de erro: %ERRORLEVEL%
    pause
)
