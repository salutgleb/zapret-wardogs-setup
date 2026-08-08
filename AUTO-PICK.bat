@echo off
:: ============================================================
::  AUTO-PICK - finds a strategy that works TODAY
::
::  Tries strategies one by one, checks Discord after each, and
::  stops on the first one where Discord fully answers. Leaves
::  that strategy running.
::
::  ALT11 is tried first (known-good for War Dogs).
::
::  NOTE ON PAREN-NAMED FILES: 20 of the 21 strategy files have
::  '(' and ')' in their names. cmd.exe expands %VAR% BEFORE it
::  parses block structure, so %S% inside an IF(...) block would
::  let the ')' close the block and abort the script. Every use
::  inside a block below is therefore !S!, and log writes lead
::  with the redirection. Do not "simplify" these back.
:: ============================================================

setlocal EnableDelayedExpansion
cd /d "%~dp0"
title AUTO-PICK - Discord + War Dogs

:: never let a strategy open the update page mid-cycle
set "NO_UPDATE_CHECK=1"

set "PREFERRED=general (ALT11).bat"
set "WINNER="
set "BEST="
set "BESTSCORE=0"
set "ANYSTARTED="
set "LOGFILE=%~dp0auto-pick-last-run.txt"

:: --- what decides pass/fail ---------------------------------
:: Discord only. Any HTTP code means the TLS handshake got
:: through the DPI; 000 means blocked. Codes differ per endpoint
:: (200/404/403) so we only care "answered" vs "did not answer".
set "T1=https://discord.com/"
set "T2=https://gateway.discord.gg/"
set "T3=https://cdn.discordapp.com/"
set "TOTAL=3"

:: --- informational only -------------------------------------
:: The War Dogs anticheat hosts are listed in lists\list-exclude.txt,
:: and hostlist-exclude wins over hostlist in winws. So no strategy
:: ever applies desync to them and their result cannot tell two
:: strategies apart. Reported at the end, never scored.
set "AC1=https://ac-knock.codefusion.technology/"
set "AC2=https://ac-fallback.codefusion.technology/"

cls
echo ============================================================
echo   AUTO-PICK - Discord + War Dogs
echo ============================================================
echo.

:: --- preflight ----------------------------------------------
net session >nul 2>&1
if errorlevel 1 (
    echo  [X] No administrator rights.
    echo      Right-click AUTO-PICK.bat -^> "Run as administrator".
    echo.
    pause
    exit /b 1
)
if not exist "%~dp0bin\winws.exe" (
    echo  [X] bin\winws.exe missing - download the whole repository,
    echo      not just this file.
    echo.
    pause
    exit /b 1
)
if not exist "%SystemRoot%\System32\curl.exe" (
    echo  [X] curl.exe not found - cannot test automatically.
    echo      Run the general*.bat files by hand instead.
    echo.
    pause
    exit /b 1
)

:: a leftover service would make every standalone strategy pause
sc query zapret >nul 2>&1 && (
    echo  [!] Removing a leftover 'zapret' service...
    net stop zapret >nul 2>&1
    sc delete zapret >nul 2>&1
)

:: guard against scoring ourselves on excluded traffic
if exist "%~dp0lists\list-exclude.txt" (
    findstr /I /C:"discord.com" "%~dp0lists\list-exclude.txt" >nul 2>&1 && echo  [!] discord.com is in list-exclude.txt - results will be meaningless
)

echo  Testing strategies. Allow a few minutes.
echo  Ctrl+C aborts, but leaves the last strategy running.
echo.
echo ------------------------------------------------------------
>"%LOGFILE%" echo AUTO-PICK run

:: --- preferred strategy first --------------------------------
call :try "%PREFERRED%"
if defined WINNER goto done

:: --- then everything else ------------------------------------
for /f "delims=" %%F in ('dir /b /a-d "general*.bat" 2^>nul') do (
    if not defined WINNER (
        if /i not "%%F"=="!PREFERRED!" call :try "%%F"
    )
)

:done
echo ------------------------------------------------------------
echo.
if defined WINNER goto report_win
goto report_fail

:: ============================================================
::  RESULT: SUCCESS
:: ============================================================
:report_win
echo   [OK] WORKING STRATEGY: !WINNER!
>>"%LOGFILE%" echo Working strategy: !WINNER!
echo.
echo   It is running now. Discord should work.
echo   Closing this window does not stop it.
echo.
call :check_ac
goto finish

:: ============================================================
::  RESULT: NOTHING FULLY PASSED
:: ============================================================
:report_fail
:: never leave a rejected strategy running while reporting failure
call :stop

if not defined ANYSTARTED (
    echo   [X] winws.exe never started on any strategy.
    echo       Almost always the antivirus quarantined WinDivert,
    echo       or this PC blocks driver installation.
    >>"%LOGFILE%" echo Nothing started - WinDivert blocked
    goto finish
)

if not defined BEST (
    echo   [X] Every strategy started, but none reached Discord.
    echo       The network itself may be blocking, or DNS is poisoned.
    echo       Try service.bat -^> 11. Run Diagnostics
    >>"%LOGFILE%" echo All started, none reached Discord
    goto finish
)

echo   [!] No strategy passed all %TOTAL% Discord checks.
echo       Best was !BEST! at !BESTSCORE!/%TOTAL%.
echo       Restarting it - it may still be good enough.
>>"%LOGFILE%" echo Best: !BEST! (!BESTSCORE!/%TOTAL%)
echo.
pushd "%~dp0"
call "!BEST!" >nul 2>&1
popd
ping -n 4 127.0.0.1 >nul 2>&1
call :check_ac
goto finish

:finish
echo.
echo   ^(saved to auto-pick-last-run.txt^)
echo.
pause
exit /b

:: ============================================================
::  TRY ONE STRATEGY
:: ============================================================
:try
set "S=%~1"
if not exist "%~dp0%S%" exit /b
rem set /p strips leading spaces, so lead with a visible character
<nul set /p "=- %S% ... "

call :stop

pushd "%~dp0"
call "%S%" >nul 2>&1
popd

:: wait for winws.exe to appear at all
set "UP="
for /l %%i in (1,1,10) do if not defined UP (
    tasklist /FI "IMAGENAME eq winws.exe" 2>nul | find /I "winws.exe" >nul && set "UP=1"
    if not defined UP ping -n 2 127.0.0.1 >nul 2>&1
)
if not defined UP goto try_nostart
set "ANYSTARTED=1"

:: winws appearing in tasklist is NOT the same as WinDivert filtering.
:: The driver install + filter setup takes noticeably longer than
:: process creation, so probing immediately produces false failures.
ping -n 5 127.0.0.1 >nul 2>&1

:: discord.com decides fast-fail; the other two refine the score
set "SCORE=0"
call :probe "%T1%"
if "!ANSWERED!"=="0" goto try_fail
set /a SCORE+=1

call :probe "%T2%"
if "!ANSWERED!"=="1" set /a SCORE+=1

call :probe "%T3%"
if "!ANSWERED!"=="1" set /a SCORE+=1

if !SCORE! EQU %TOTAL% goto try_win
goto try_fail

:try_win
echo OK - Discord fully reachable
>>"%LOGFILE%" echo   !S! : PASS %TOTAL%/%TOTAL%
set "WINNER=!S!"
exit /b

:try_fail
echo failed ^(!SCORE!/%TOTAL%^)
>>"%LOGFILE%" echo   !S! : fail !SCORE!/%TOTAL%
if !SCORE! GTR !BESTSCORE! (
    set "BESTSCORE=!SCORE!"
    set "BEST=!S!"
)
exit /b

:try_nostart
echo did not start
>>"%LOGFILE%" echo   !S! : did not start
exit /b

:: ============================================================
::  PROBE ONE URL  ->  ANSWERED=1 if the DPI let it through
::  Retries once: a real block answers 000 twice, a startup
::  race usually does not.
:: ============================================================
:probe
set "ANSWERED=0"
set "CODE="
for /f "delims=" %%C in ('curl -s -o nul -w "%%{http_code}" --max-time 6 "%~1" 2^>nul') do set "CODE=%%C"
if not defined CODE set "CODE=000"
if not "!CODE!"=="000" goto probe_ok

ping -n 3 127.0.0.1 >nul 2>&1
set "CODE="
for /f "delims=" %%C in ('curl -s -o nul -w "%%{http_code}" --max-time 5 "%~1" 2^>nul') do set "CODE=%%C"
if not defined CODE set "CODE=000"
if "!CODE!"=="000" exit /b

:probe_ok
set "ANSWERED=1"
exit /b

:: ============================================================
::  ANTICHEAT REACHABILITY (informational, never scored)
:: ============================================================
:check_ac
echo   War Dogs anticheat check ^(not affected by the strategy^):
call :probe "%AC1%"
if "!ANSWERED!"=="1" (echo     ac-knock    : reachable) else (echo     ac-knock    : NO ANSWER)
call :probe "%AC2%"
if "!ANSWERED!"=="1" (echo     ac-fallback : reachable) else (echo     ac-fallback : NO ANSWER)
echo.
echo   These hosts sit in lists\list-exclude.txt, so zapret passes
echo   them through untouched. If they do not answer, no strategy
echo   will fix that - it is the network, not the bypass.
exit /b

:: ============================================================
::  STOP THE CURRENT BYPASS
:: ============================================================
:stop
tasklist /FI "IMAGENAME eq winws.exe" 2>nul | find /I "winws.exe" >nul && taskkill /IM winws.exe /F >nul 2>&1
ping -n 2 127.0.0.1 >nul 2>&1
exit /b
