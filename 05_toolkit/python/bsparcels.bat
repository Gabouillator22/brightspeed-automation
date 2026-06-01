@echo off
setlocal
set SCRIPT=%~dp0bsparcels.py

set PY=
set PYARGS=
where py >nul 2>nul && set PY=py&& set PYARGS=-3
if "%PY%"=="" where python >nul 2>nul && set PY=python
if "%PY%"=="" if exist "%LOCALAPPDATA%\Programs\Python\Python312\python.exe" set "PY=%LOCALAPPDATA%\Programs\Python\Python312\python.exe"
if "%PY%"=="" if exist "%LOCALAPPDATA%\Programs\Python\Python311\python.exe" set "PY=%LOCALAPPDATA%\Programs\Python\Python311\python.exe"
if "%PY%"=="" for /d %%D in ("%LOCALAPPDATA%\Programs\Python\Python*") do if exist "%%~fD\python.exe" set "PY=%%~fD\python.exe"
if "%PY%"=="" (
  echo Python was not found. Install Python 3, then run this again.
  pause
  exit /b 1
)

"%PY%" %PYARGS% "%SCRIPT%" %*
endlocal
