@echo off
cd /d "%~dp0"
echo.
echo Installing Face Auth PC dependencies...
echo.
if not exist ".venv\Scripts\python.exe" (
    echo Creating isolated Python environment in .venv...
    python -m venv .venv
    if errorlevel 1 goto fail
)
set "PYTHON=%CD%\.venv\Scripts\python.exe"
"%PYTHON%" -m pip install --upgrade pip
if errorlevel 1 goto fail
"%PYTHON%" -m pip install -r requirements.txt
if errorlevel 1 goto fail

echo.
echo Checking face database...
"%PYTHON%" -c "import pickle; db=pickle.load(open('face_db.pkl','rb')); print('People:', ', '.join(sorted(db.get('persons', {}).keys())))"
if errorlevel 1 goto fail

echo.
echo Done. To run the PC API, double-click run_backend.bat
pause
exit /b 0

:fail
echo.
echo Setup failed. Read the error above.
pause
exit /b 1
