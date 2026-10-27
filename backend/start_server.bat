@echo off
cd /d %~dp0
call .venv\Scripts\activate.bat
set CVSAFE_DEMO=1
uvicorn app.main:app --host 0.0.0.0 --port 8000
pause
