@echo off
cd /d "%~dp0mobile_android"
set "JAVA_HOME=C:\Program Files\Android\Android Studio\jbr"
set "ANDROID_HOME=%LOCALAPPDATA%\Android\Sdk"
set "ANDROID_SDK_ROOT=%LOCALAPPDATA%\Android\Sdk"

echo Building Android thin-client APK...
call gradlew.bat assembleDebug
if errorlevel 1 goto fail

cd /d "%~dp0"
copy /Y "mobile_android\app\build\outputs\apk\debug\app-debug.apk" "outputs\face-auth-ec2-test-v2.0.1.apk"
echo.
echo APK ready:
echo %~dp0outputs\face-auth-ec2-test-v2.0.1.apk
pause
exit /b 0

:fail
echo.
echo APK build failed. Check Android SDK / Gradle output above.
pause
exit /b 1
