@echo off
REM Prepara o app Flutter para Web
cd /d "%~dp0app"
call flutter create . --platforms=web
call flutter pub get
echo.
echo Pronto para rodar no Chrome: flutter run -d chrome
echo Ou para gerar o build web: flutter build web --release
pause
