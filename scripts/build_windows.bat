@echo off
rem MediaShelf Windows build script
setlocal
cd /d "%~dp0.."

rem China mirrors
set PUB_HOSTED_URL=https://pub.flutter-io.cn
set FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn

echo ==^> flutter pub get
call flutter --no-version-check --suppress-analytics pub get
if errorlevel 1 goto :err

echo ==^> flutter build windows --release
call flutter --no-version-check --suppress-analytics build windows --release
if errorlevel 1 goto :err

echo.
echo Build done: build\windows\x64\runner\Release\
goto :eof

:err
echo Build failed (exit code %errorlevel%)
exit /b 1
