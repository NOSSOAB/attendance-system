@echo off
net session >nul 2>&1
if not %errorlevel% == 0 (
  echo Requesting Administrator permission to open TCP port 8000...
  powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)

netsh advfirewall firewall add rule name="Face Auth Mobile API 8000" dir=in action=allow protocol=TCP localport=8000
echo.
echo Firewall rule added for TCP port 8000.
pause
