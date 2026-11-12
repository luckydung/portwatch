@echo off
rem Double-click de mo Port Dashboard. De file nay cung thu muc voi PortDashboard.ps1
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0PortDashboard.ps1"
