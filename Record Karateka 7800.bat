@echo off
rem ---------------------------------------------------------------------------
rem  Record a session of the 7800 PORT of Karateka in MAME, for debugging.
rem
rem  Drag the cartridge you want to play (an .a78 file, for example
rem  work\karateka7800-invincible-easy.a78) onto this file. Nothing is
rem  built: that cartridge is copied next to the recording as inp\NAME.a78,
rem  because a recording only replays on the cartridge it was made with
rem  ("Play Karateka 7800 Recording.bat" loads that copy).
rem
rem  NAME is the cartridge's name and the next free number, for example
rem  inp\karateka7800-invincible-easy-01.inp. From a command prompt a name
rem  can be given after the cartridge:
rem     "Record Karateka 7800.bat" work\karateka7800.a78 finale
rem
rem  Controls: arrow keys = joystick, Left Ctrl = button 1 (punch), Space or
rem  Left Shift = button 2 (kick; not MAME's Left Alt, which Windows takes for
rem  the window's menu: mame-ctrlr\karateka7800.cfg), 1 = the console's Reset,
rem  2 = Select, Pause key... see MAME's Tab menu.
rem  Esc stops and saves (Scroll Lock first if Esc does nothing).
rem ---------------------------------------------------------------------------

setlocal
rem the cartridges are BankSet now (FINDINGS "MAME with BankSet"): the MAME
rem 0.287 build with BankSet (stock MAME refuses them), unless MAME is set
if not defined MAME set "MAME=%USERPROFILE%\Documents\mame-src\a78.exe"
for %%M in ("%MAME%") do set "MAMEDIR=%%~dpM"
set "MAMEDIR=%MAMEDIR:~0,-1%"

rem %~dp0 ends with a backslash; a trailing backslash before a closing quote
rem escapes that quote on Windows and mangles the argument list.
set "HERE=%~dp0"
set "DIR=%HERE:~0,-1%"
set "INP=%DIR%\inp"

if "%~1"=="" (
    echo Drag a 7800 cartridge ^(.a78^) onto this file to record a session with it.
    echo The cartridges built here are in work\, for example:
    for %%F in ("%DIR%\work\karateka7800*.a78") do echo    work\%%~nxF
    pause
    exit /b 1
)
set "CART=%~f1"
if not exist "%CART%" ( echo No such file: "%CART%" & pause & exit /b 1 )
if /i not "%~x1"==".a78" ( echo "%~nx1" is not an .a78 cartridge. & pause & exit /b 1 )
if not exist "%MAME%" ( echo Could not find MAME at "%MAME%". & pause & exit /b 1 )
if not exist "%INP%" mkdir "%INP%"

set "NAME=%~2"
if "%NAME%"=="" call :picknext "%~n1"
if exist "%INP%\%NAME%.inp" ( echo inp\%NAME%.inp already exists; pick another name. & pause & exit /b 1 )

copy /y "%CART%" "%INP%\%NAME%.a78" > nul
if errorlevel 1 ( echo Could not copy the cartridge to inp\%NAME%.a78 & pause & exit /b 1 )

rem skip MAME's once-per-launch warnings: a copy of your own ui.ini with
rem skip_warnings 1, searched before MAME's folder
if not exist "%DIR%\mame-ini" mkdir "%DIR%\mame-ini"
if exist "%MAMEDIR%\ui.ini" (
    findstr /v /b /c:"skip_warnings" "%MAMEDIR%\ui.ini" > "%DIR%\mame-ini\ui.ini"
) else (
    type nul > "%DIR%\mame-ini\ui.ini"
)
(echo skip_warnings             1)>> "%DIR%\mame-ini\ui.ini"

echo.
echo Cartridge: %~nx1  (copied to inp\%NAME%.a78)
echo Recording to inp\%NAME%.inp
echo Play as far as you like, then press Esc to stop.
echo.

rem button 2 on Space or Left Shift (mame-ctrlr\karateka7800.cfg): MAME's Left
rem Alt opens the window's menu under Windows, and the keys stop reaching MAME
"%MAME%" a7800 -inipath "%DIR%\mame-ini;%MAMEDIR%" -rompath "%DIR%\roms" ^
    -ctrlrpath "%DIR%\mame-ctrlr" -ctrlr karateka7800 ^
    -cart "%INP%\%NAME%.a78" -skip_gameinfo -window ^
    -input_directory "%INP%" -record "%NAME%.inp"

echo.
if exist "%INP%\%NAME%.inp" (
    rem the MAME build that made it (the .inp's header says only "MAME 0.287")
    for %%M in ("%MAME%") do (echo MAME %%~fM, %%~tM, %%~zM bytes)> "%INP%\%NAME%.mame.txt"
    for %%F in ("%INP%\%NAME%.inp") do echo Saved: inp\%%~nxF  ^(%%~zF bytes^), cartridge inp\%NAME%.a78
    echo To watch it: drag inp\%NAME%.inp onto "Play Karateka 7800 Recording.bat"
) else (
    echo WARNING: no recording was written.
    del "%INP%\%NAME%.a78" 2> nul
)
pause
endlocal
goto :eof

rem --- the cartridge's name and the next unused number, so nothing is ever
rem     overwritten -------------------------------------------------------------
:picknext
set /a N=1
:pn_loop
if %N% LSS 10 (set "NN=0%N%") else (set "NN=%N%")
if exist "%INP%\%~1-%NN%.inp" (
    set /a N+=1
    goto pn_loop
)
set "NAME=%~1-%NN%"
goto :eof
