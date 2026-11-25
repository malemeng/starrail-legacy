@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Watch-Freight.ps1" %*
if errorlevel 1 pause
