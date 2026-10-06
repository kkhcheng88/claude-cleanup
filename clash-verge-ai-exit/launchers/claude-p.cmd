@echo off
rem ============================================================
rem  claude-p : launch Claude Code through the Clash Verge proxy (fail-closed)
rem  NOTE: ~/.claude/settings.json already carries the same env block,
rem        so this launcher is only for explicit control from cmd.
rem ============================================================
setlocal
set "HTTPS_PROXY=http://127.0.0.1:7897"
set "HTTP_PROXY=http://127.0.0.1:7897"
set "NO_PROXY=localhost,127.0.0.1,::1"
netstat -an | findstr /C:"127.0.0.1:7897" >nul 2>&1
if errorlevel 1 echo [proxy] WARNING: nothing is listening on 127.0.0.1:7897 - start Clash Verge or Claude Code will fail (fail-closed)
claude %*
endlocal
