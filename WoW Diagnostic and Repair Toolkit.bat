@echo off
setlocal
if not exist "%~dp0Launch-Toolkit.vbs" (
 echo Launch-Toolkit.vbs is missing. Extract all files into the same folder.
 pause
 exit /b 1
)
start "" "%SystemRoot%\System32\wscript.exe" "%~dp0Launch-Toolkit.vbs"
exit /b
