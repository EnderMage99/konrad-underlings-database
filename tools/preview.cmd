@echo off
rem Double-click to preview the site locally. See preview.ps1.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0preview.ps1" %*
