#requires -Version 5
# verify.ps1 - OPTIONAL Stop hook (Windows). When the agent tries to finish, run the
# project's own checks (guards/lint/test) and BLOCK finishing (exit 2) while they fail,
# so the agent fixes it first.
# Register the SAME script under UserPromptSubmit too (recommended): there it only records the
# turn-start marker described below (hook_event_name tells the two apart).
#
# SAFE BY DEFAULT - it runs a project's .claude\checks.cmd ONLY when BOTH:
#   (a) that file exists, AND
#   (b) the project's path is listed in %USERPROFILE%\.claude\verify-allowed.txt
#       (one absolute path per line; '#' comments allowed). List specific project
#       roots, NOT a broad parent dir — subdirectories of a listed path are trusted too.
# The allowlist lives OUTSIDE any repo, so a cloned/untrusted repo that ships its own
# checks.cmd can NOT auto-run code. No-op otherwise; always fails open (exit 0 on error).
#
# Bounded retries: while the checks fail it blocks up to CLAUDE_VERIFY_MAX_BLOCKS times in a
# row (default 3; 0 = never block, only warn). The count is kept per session_id under
# %TEMP%\claude-verify and restarts with each new turn. Once the limit is reached it stops
# blocking and shows the owner a "checks still RED" message (JSON systemMessage) instead;
# a pass clears the count. Claude Code itself also ends the turn after 8 consecutive Stop-hook
# blocks (CLAUDE_CODE_STOP_HOOK_BLOCK_CAP), so values of 8 or more add nothing.
# What Claude sees on a block is kept short: the ERROR lines plus the last 20 other lines.
# The guard runner keeps the full output in .claude\guards.log. A custom checks.cmd (no
# .claude\guards.log) has no log to point at, so its output itself is shown: all of it up to
# 200 lines, beyond that the ERROR lines plus the first 100 and last 100 lines.
#
# It never blocks when a block cannot help:
#   * plan mode (hook input permission_mode "plan"): Claude cannot edit files, so it exits 0
#     without running the checks;
#   * unchanged tree: each red run stores a hash of the git working-tree state (git status +
#     diff vs HEAD + untracked file contents) for the session. If the checks (still run) are
#     red again and no file changed since the last red run (e.g. a question-only turn), it does
#     not block but shows the owner the same kind of "checks still RED" message instead.
#     Outside git (or without git) there is no hash, so it blocks as before;
#   * no file changed THIS turn (needs the UserPromptSubmit registration): on UserPromptSubmit it
#     stores the same tree hash as the turn-start marker for the session (never runs the checks,
#     prints nothing, always exits 0; outside git no marker). At Stop, if the tree still equals
#     that marker (e.g. a review-only turn in a project that was already red), Claude changed no
#     files, so it exits 0 without running the checks. No marker (not registered) = as before.
#
# Enable a TRUSTED project once:
#   Add-Content "$env:USERPROFILE\.claude\verify-allowed.txt" "D:\path\to\project"
# then create that project's .claude\checks.cmd (template: templates\checks.cmd), e.g.:
#   powershell -NoProfile -ExecutionPolicy Bypass -File .claude\guards.ps1
#   (or: vendor\bin\pint --test && vendor\bin\phpstan analyse)

try {
    $in = $null; $raw = ''
    try {
        # Read stdin as UTF-8 (Claude Code sends UTF-8; the console default would mangle non-ASCII paths).
        $reader = New-Object System.IO.StreamReader([Console]::OpenStandardInput(), [System.Text.Encoding]::UTF8)
        $raw = $reader.ReadToEnd()
        if ($raw) { $in = $raw | ConvertFrom-Json }
    } catch {}

    $cwd = if ($in -and $in.cwd) { [string]$in.cwd } else { (Get-Location).Path }
    $sid = if ($in -and $in.session_id) { [string]$in.session_id } else { '' }
    $active = [bool]($in -and ($in.stop_hook_active -eq $true))
    $mode = if ($in -and $in.permission_mode) { [string]$in.permission_mode } else { '' }
    $evt = if ($in -and $in.hook_event_name) { [string]$in.hook_event_name } else { '' }
    if (-not $evt -and ("$raw" -cmatch '"hook_event_name"\s*:\s*"UserPromptSubmit"')) { $evt = 'UserPromptSubmit' }   # bad JSON
    $turnStart = ($evt -ceq 'UserPromptSubmit')   # turn-start marker call: print nothing, always exit 0
    if ($mode -eq 'plan' -and -not $turnStart) { exit 0 }   # plan mode: Claude cannot edit files, so a block cannot help

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

    # ---- block counter (no counter file = old one-block-per-turn behaviour)
    $max = 3
    if ("$env:CLAUDE_VERIFY_MAX_BLOCKS" -match '^\d{1,4}$') { $max = [int]$env:CLAUDE_VERIFY_MAX_BLOCKS }
    $key = $sid -replace '[^A-Za-z0-9_-]', ''
    if ($key.Length -gt 100) { $key = $key.Substring(0, 100) }
    $mkey = $key                         # the turn-start marker needs a real session id
    if (-not $key) { $key = 'no-session' }
    $state = $null; $tstate = $null; $mstate = $null
    try {
        $tmp = if ($env:TEMP) { $env:TEMP } else { [System.IO.Path]::GetTempPath() }
        $dir = Join-Path $tmp 'claude-verify'
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        if (Test-Path -LiteralPath $dir -PathType Container) {
            $state = Join-Path $dir "$key.count"
            $tstate = Join-Path $dir "$key.tree"   # tree hash after the last red run of this session
            if ($mkey) { $mstate = Join-Path $dir "$mkey.start" }   # tree hash when this session's current turn started
        }
    } catch { $state = $null; $tstate = $null; $mstate = $null }

    $count = 0
    if ($active) {                       # a continuation we (or another Stop hook) caused
        if ($state -and (Test-Path -LiteralPath $state)) {
            $c = [string](Get-Content -LiteralPath $state -TotalCount 1 -ErrorAction SilentlyContinue)
            if ($c.Trim() -match '^\d{1,4}$') { $count = [int]$c.Trim() }
        } elseif (-not $state) {
            $count = $max                # can't count safely: allow this stop
        }
    }                                    # not active = first stop of a new turn: count 0

    function Get-TreeState([string]$Dir) {
        # Hash of the git working-tree state (status + diff vs HEAD + untracked file contents); '' outside git.
        if (-not (Get-Command git -ErrorAction SilentlyContinue)) { return '' }
        $oldLocks = $env:GIT_OPTIONAL_LOCKS; $oldEnc = $null
        try { $oldEnc = [Console]::OutputEncoding; [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
        try {
            $env:GIT_OPTIONAL_LOCKS = '0'
            $st = @(& git -C $Dir status --porcelain --untracked-files=all 2>$null)
            if ($LASTEXITCODE -ne 0) { return '' }
            $df = @(& git -C $Dir diff --no-ext-diff --no-textconv --binary HEAD 2>$null)
            if ($LASTEXITCODE -ne 0) {       # no commit yet
                $df = @(& git -C $Dir diff --no-ext-diff --no-textconv --binary --cached 2>$null) + @(& git -C $Dir diff --no-ext-diff --no-textconv --binary 2>$null)
            }
            $un = @(& git -C $Dir -c core.quotepath=off ls-files -o --exclude-standard 2>$null | ForEach-Object {
                $p = [string]$_; $h = '?'
                try { $h = (Get-FileHash -LiteralPath (Join-Path $Dir $p) -Algorithm SHA256 -ErrorAction Stop).Hash } catch {}
                "$p $h"
            })
            $text = (@($st) + @($df) + @($un)) -join "`n"
            $sha = [System.Security.Cryptography.SHA256]::Create()
            return ([BitConverter]::ToString($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($text))) -replace '-', '')
        } catch { return '' }
        finally {
            $env:GIT_OPTIONAL_LOCKS = $oldLocks
            if ($oldEnc) { try { [Console]::OutputEncoding = $oldEnc } catch {} }
        }
    }

    # ---- UserPromptSubmit: record the turn-start marker only (never run the checks here)
    if ($turnStart) {
        if ($mstate) {
            Remove-Item -LiteralPath $mstate -Force -ErrorAction SilentlyContinue   # never leave the previous turn's marker behind
            $start = [string](Get-TreeState $cwd)
            if ($start) { Set-Content -LiteralPath $mstate -Value $start -ErrorAction SilentlyContinue }
        }
        exit 0
    }

    # ---- run the project's checks directly (no cmd.exe string interpolation; same trust model)
    $pre = ''; $last = ''
    if ($tstate) {
        $pre = [string](Get-TreeState $cwd)
        if (Test-Path -LiteralPath $tstate) { $last = ([string](Get-Content -LiteralPath $tstate -TotalCount 1 -ErrorAction SilentlyContinue)).Trim() }
    }
    # Tree equals this turn's start marker: Claude changed no files this turn, so a block cannot help
    # (e.g. a review-only turn in a project that was already red). Skip the checks.
    if ($pre -and $mstate -and (Test-Path -LiteralPath $mstate)) {
        $start = ([string](Get-Content -LiteralPath $mstate -TotalCount 1 -ErrorAction SilentlyContinue)).Trim()
        if ($pre -eq $start) {
            if ($state) { Remove-Item -LiteralPath $state -Force -ErrorAction SilentlyContinue }
            exit 0
        }
    }
    $global:LASTEXITCODE = $null         # the git calls above must not leak an exit code into $code
    Push-Location -LiteralPath $cwd
    $out = & $checks 2>&1
    $code = $LASTEXITCODE
    Pop-Location
    if ($null -eq $code) { exit 0 }      # could not tell - fail open
    if ($code -eq 0) {
        if ($state) { Remove-Item -LiteralPath $state -Force -ErrorAction SilentlyContinue }
        if ($tstate) { Remove-Item -LiteralPath $tstate -Force -ErrorAction SilentlyContinue }
        exit 0
    }
    $unchanged = [bool]($pre -and ($pre -eq $last))
    if ($pre) {                          # remember the tree as the checks left it (they may write files)
        $post = [string](Get-TreeState $cwd)
        if ($post) { Set-Content -LiteralPath $tstate -Value $post -ErrorAction SilentlyContinue }
    }

    $lines = @($out | ForEach-Object { $s = [string]$_; if ($s.Length -gt 300) { $s.Substring(0, 300) } else { $s } })
    $errs = @($lines | Where-Object { $_ -match '^\s*ERROR' } | Select-Object -First 40)
    $rest = @($lines | Where-Object { $_ -notmatch '^\s*ERROR' } | Select-Object -Last 20)
    $log = 're-run .claude\checks.cmd for the full output'
    $hasLog = Test-Path -LiteralPath (Join-Path $cwd '.claude\guards.log')
    if ($hasLog) { $log = 'full log in .claude\guards.log' }
    $first = (@($errs | Select-Object -First 3) -join '; ')

    # Nothing changed since the last red run (e.g. a question-only turn): a block cannot help.
    if ($unchanged) {
        if ($state) { Remove-Item -LiteralPath $state -Force -ErrorAction SilentlyContinue }
        $msg = "verify: project checks are still RED (exit $code) and no file has changed since the last red run in this session, so this stop is not blocked - this work is NOT verified. "
        if ($first) { $msg += "Errors: $first. " }
        $msg += "Details: $log."
        [pscustomobject]@{ systemMessage = $msg } | ConvertTo-Json -Compress
        exit 0
    }

    if ($count -lt $max) {
        $count++
        if ($state) { Set-Content -LiteralPath $state -Value $count -ErrorAction SilentlyContinue }
        [Console]::Error.WriteLine("verify: project checks (.claude\checks.cmd) failed with exit $code (block $count of $max). Fix the cause - not the test or guard - then finish; $log.")
        if ($hasLog) {
            if ($errs.Count -gt 0) { [Console]::Error.WriteLine(($errs -join "`n")) }
            if ($rest.Count -gt 0) { [Console]::Error.WriteLine("--- last lines ---`n" + ($rest -join "`n")) }
        } elseif ($lines.Count -le 200) {   # custom checks.cmd: show its output, capped at 200 lines
            [Console]::Error.WriteLine("--- output ---`n" + ($lines -join "`n"))
        } else {
            if ($errs.Count -gt 0) { [Console]::Error.WriteLine(($errs -join "`n")) }
            [Console]::Error.WriteLine("--- output: first 100 of $($lines.Count) lines ---`n" + (@($lines | Select-Object -First 100) -join "`n"))
            [Console]::Error.WriteLine("--- ... $($lines.Count - 200) lines omitted ... last 100 lines ---`n" + (@($lines | Select-Object -Last 100) -join "`n"))
        }
        exit 2
    }

    # Limit reached: stop blocking, but tell the owner plainly (systemMessage is shown to the user).
    if ($state) { Remove-Item -LiteralPath $state -Force -ErrorAction SilentlyContinue }
    $msg = "verify: project checks are still RED (exit $code) after $max blocked stop(s) - this work is NOT verified. "
    if ($first) { $msg += "Errors: $first. " }
    $msg += "Details: $log. CLAUDE_VERIFY_MAX_BLOCKS sets how many fix attempts are forced."
    [pscustomobject]@{ systemMessage = $msg } | ConvertTo-Json -Compress
    exit 0
} catch { exit 0 }
