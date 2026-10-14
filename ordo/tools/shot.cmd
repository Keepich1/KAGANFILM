@echo off
rem Windows: scene frame to PNG on the PC video card, same as tools/shot.sh (details in shot.ps1).
rem   tools\shot.cmd res://scenes/slice.tscn out.png --at=6 --cam=CamCamp --size=1920x1080
rem ASCII only: cmd reads this file in the OEM code page.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0shot.ps1" %*
exit /b %ERRORLEVEL%
