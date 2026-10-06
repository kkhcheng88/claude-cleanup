@echo off
rem ============================================================
rem  codex-p : launch Codex through the Clash Verge proxy (fail-closed)
rem  These variables affect ONLY this process and its children.
rem  If Clash Verge is not running, Codex fails instead of leaking
rem  the real IP (that is the intended fail-closed behaviour).
rem ============================================================
setlocal
set "HTTPS_PROXY=http://127.0.0.1:7897"
set "HTTP_PROXY=http://127.0.0.1:7897"
set "NO_PROXY=localhost,127.0.0.1,::1"
netstat -an | findstr /C:"127.0.0.1:7897" >nul 2>&1
if errorlevel 1 echo [proxy] WARNING: nothing is listening on 127.0.0.1:7897 - start Clash Verge or Codex will fail (fail-closed)
codex %*
endlocal
