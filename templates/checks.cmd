@echo off
rem checks.cmd - LOCAL trigger for the verify Stop hook (Windows). TEMPLATE (claude-md/templates/checks.cmd).
rem Copy to <project>\.claude\checks.cmd. Keep it gitignored and never commit it.
rem
rem Why this is separate from the committed .claude\guards.ps1:
rem - The verify hook auto-runs .claude\checks.cmd when Claude tries to finish, but only in projects
rem   listed in %USERPROFILE%\.claude\verify-allowed.txt (a user-authored allowlist outside every repo).
rem - A cloned or untrusted repo can ship any guards.ps1 it likes; it still can't make your machine
rem   auto-run it, because this one-line trigger is yours: create it only in projects you trust,
rem   after reading their .claude\guards.ps1.
rem - The guards themselves stay committed in guards.ps1, so CI and cloud sessions run them without it.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0guards.ps1" %*
exit /b %ERRORLEVEL%
