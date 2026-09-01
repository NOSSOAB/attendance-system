@echo off
setlocal
cd /d "%~dp0"
set "PYTHON=python"
if exist "%~dp0.venv\Scripts\python.exe" set "PYTHON=%~dp0.venv\Scripts\python.exe"

echo.
echo Face Auth PC Backend v2
echo =======================
echo.
echo Checking TCP port 8000...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$listeners = @(Get-NetTCPConnection -LocalPort 8000 -State Listen -ErrorAction SilentlyContinue); if ($listeners.Count -eq 0) { exit 0 }; $listener = $listeners[0]; $process = Get-CimInstance Win32_Process -Filter ('ProcessId = ' + $listener.OwningProcess) -ErrorAction SilentlyContinue; $isFaceAuth = $process -and $process.Name -like 'python*' -and $process.CommandLine -match 'uvicorn' -and (($process.CommandLine -match 'backend\.app:app') -or ($process.CommandLine -match 'api_server:app')); if ($isFaceAuth) { Write-Host ('Stopping previous Face Auth backend PID ' + $process.ProcessId); Stop-Process -Id $process.ProcessId -Force; Start-Sleep -Milliseconds 700; exit 0 }; Write-Host ('Port 8000 is used by another process: PID ' + $listener.OwningProcess); exit 2"
if errorlevel 2 goto portbusy

echo.
echo PC API addresses:
powershell -NoProfile -ExecutionPolicy Bypass -Command "$addresses = @(Get-NetIPAddress -AddressFamily IPv4); foreach ($item in $addresses) { if ($item.IPAddress -notlike '127.*' -and $item.PrefixOrigin -ne 'WellKnown') { '  http://' + $item.IPAddress + ':8000' } }"
echo.
echo Keep this window open while testing from the phone.
echo API docs: http://127.0.0.1:8000/docs
echo.
"%PYTHON%" -m uvicorn backend.app:app --host 0.0.0.0 --port 8000 --workers 1
if errorlevel 1 goto fail
goto end

:portbusy
echo.
echo Cannot start because port 8000 belongs to another application.
echo Close that application or change the backend port and the URL in the APK.
goto fail

:fail
echo.
echo Backend stopped with an error. Read the message above.

:end
pause
endlocal
