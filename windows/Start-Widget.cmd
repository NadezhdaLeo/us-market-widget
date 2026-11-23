@echo off
rem Launches the US Market widget without a visible console window.
start "" /min powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0us-market-widget.ps1"
