#requires -Version 5
# verify.ps1 - OPTIONAL Stop hook (Windows). When the agent tries to finish, run the
# project's own checks (lint/test) and BLOCK finishing (exit 2) if they fail, so the
# agent fixes it first.
#
# SAFE BY DEFAULT - it runs a project's .claude\checks.cmd ONLY when BOTH:
#   (a) that file exists, AND
#   (b) the project's path is listed in %USERPROFILE%\.claude\verify-allowed.txt
#       (one absolute path per line; '#' comments allowed). List specific project
#       roots, NOT a broad parent dir — subdirectories of a listed path are trusted too.
# The allowlist lives OUTSIDE any repo, so a cloned/untrusted repo that ships its own
# checks.cmd can NOT auto-run code. No-op otherwise; always fails open (exit 0 on error).
#
# Enable a TRUSTED project once:
#   Add-Content "$env:USERPROFILE\.claude\verify-allowed.txt" "D:\path\to\project"
# then create that project's .claude\checks.cmd, e.g.:
#   vendor\bin\pint --test && vendor\bin\phpstan analyse

try { $raw = [Console]::In.ReadToEnd(); if ($raw) { $in = $raw | ConvertFrom-Json } } catch {}
if ($in -and $in.stop_hook_active) { exit 0 }   # don't loop if we already blocked once

$cwd = if ($in -and $in.cwd) { [string]$in.cwd } else { (Get-Location).Path }
$checks = Join-Path $cwd '.claude\checks.cmd'
if (-not (Test-Path -LiteralPath $checks)) { exit 0 }   # opt-in per project

# Trust gate: the project must be on the user-authored allowlist (outside any repo).
$allow = Join-Path $env:USERPROFILE '.claude\verify-allowed.txt'
if (-not (Test-Path -LiteralPath $allow)) { exit 0 }
$cwdN = ($cwd -replace '/', '\').TrimEnd('\').ToLowerInvariant()
$ok = $false
foreach ($line in Get-Content -LiteralPath $allow) {
  $p = $line.Trim()
  if (-not $p -or $p.StartsWith('#')) { continue }
  $p = ($p -replace '/', '\').TrimEnd('\').ToLowerInvariant()
  if ($cwdN -eq $p -or $cwdN.StartsWith("$p\")) { $ok = $true; break }
}
if (-not $ok) { exit 0 }

# Run the project's checks directly (no cmd.exe string interpolation).
$out = & $checks 2>&1
$code = $LASTEXITCODE
if ($code -ne 0) {
  [Console]::Error.WriteLine("Project checks (.claude\checks.cmd) failed with exit $code - fix before finishing:")
  [Console]::Error.WriteLine(($out | Out-String))
  exit 2
}
exit 0
