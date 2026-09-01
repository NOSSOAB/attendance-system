@echo off
cd /d "%~dp0"
echo.
echo Enrolling face database from database_faces...
echo Folder name = identity shown on phone.
echo.
set "PYTHON=python"
if exist "%~dp0.venv\Scripts\python.exe" set "PYTHON=%~dp0.venv\Scripts\python.exe"
"%PYTHON%" enroll_faces.py
if errorlevel 1 goto fail

echo.
echo Done. On the phone, press "Tai nguoi" again to reload the list.
pause
exit /b 0

:fail
echo.
echo Enroll failed. Check the error above.
pause
exit /b 1
