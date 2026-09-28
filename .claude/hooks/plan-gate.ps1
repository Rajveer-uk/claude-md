#requires -Version 5
# plan-gate.ps1 - OPTIONAL Stop hook (Windows). While an /implement-plan run still has open
# plan items or acceptance criteria, it keeps Claude from finishing (exit 2) and names the open
# items, a bounded number of times; then it stops blocking and warns "plan NOT complete".
# Linux/macOS twin: plan-gate.sh (same logic).
#
# Marker: it acts ONLY when <project>\.claude\plan-gate.local.json exists (gitignored by
# .claude/*.local.json). /implement-plan writes it at the start of a run and deletes it at the end:
#   {"session": "<session id>", "plans": ["specs/<slug>.md"]}
# "session" must equal this hook's session_id, so a marker from another session (or a committed
# one) never gates. A marker without "session" (or with an unsubstituted ${CLAUDE_SESSION_ID})
# counts only while it is less than 12 h old. Each plan path must be relative, without "..", ":"
# or symlinks/junctions, a regular file under the project, at most 1 MB; any other path is skipped.
#
# Open items (fenced code and HTML comments ignored): unchecked task boxes "- [ ]" / "* [ ]" /
# "1. [ ]"; "Status: todo | to do | pending | open | in progress | not started" (any case, also
# **Status**:, inline after the item text); Requirements rows "| AC<n> | ... |" whose Status cell is
# open | partial | not met. Everything else is closed: done, met, deferred, "Status: blocked - <reason>".
#
# It never blocks when a block cannot help: plan mode; no open item; a turn whose last line ends
# with "?" (Claude is asking the owner); a continuation in which no plan file changed since its
# last block (shows a systemMessage instead). It blocks at most CLAUDE_PLAN_GATE_MAX_BLOCKS times
# in a row per turn (default 3; 0 = never block, only warn), counted per session_id under
# %TEMP%\claude-verify (like verify.ps1); then it shows the owner a "plan NOT complete" message.
# Claude Code ends a turn after 8 consecutive Stop-hook continuations and that cap is shared by ALL
# Stop hooks (verify 3 + plan-gate 3 + the opt-in prompt check 1 = 7 fits).
#
# Safe on any repo: it reads only the marker and the plan files it names, runs no project code, no
# network, so it needs no allowlist. Any error: exit 0 (fail open). Register next to verify.ps1
# (exec form, see .claude/settings.hooks.example.json):
#   { "type": "command", "command": "powershell.exe", "args": ["-NoProfile", "-ExecutionPolicy", "Bypass",
#     "-File", "C:/Users/you/.claude/hooks/plan-gate.ps1"], "timeout": 15 }

try {
    $ErrorActionPreference = 'Stop'
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $in = $null; $raw = ''
    try {
        # Read stdin as UTF-8 (Claude Code sends UTF-8; the console default would mangle non-ASCII paths).
        $reader = New-Object System.IO.StreamReader([Console]::OpenStandardInput(), [System.Text.Encoding]::UTF8)
        $raw = $reader.ReadToEnd()
        if ($raw) { $in = $raw | ConvertFrom-Json }
    } catch { $in = $null }
    if (-not $raw) { exit 0 }

    $cwd = if ($in -and $in.cwd) { [string]$in.cwd } else { (Get-Location).Path }
    $marker = Join-Path $cwd '.claude\plan-gate.local.json'
    if (-not (Test-Path -LiteralPath $marker -PathType Leaf)) { exit 0 }   # no marker: the common, fast path

    $evt = if ($in -and $in.hook_event_name) { [string]$in.hook_event_name } else { '' }
    $sid = if ($in -and $in.session_id) { [string]$in.session_id } else { '' }
    $active = [bool]($in -and ($in.stop_hook_active -eq $true))
    $mode = if ($in -and $in.permission_mode) { [string]$in.permission_mode } else { '' }
    if (-not $in -and ($raw -cmatch '"permission_mode"\s*:\s*"plan"')) { $mode = 'plan' }   # bad JSON
    if ($mode -eq 'plan') { exit 0 }     # plan mode: Claude cannot edit files, so a block cannot help
    if ($evt -and ($evt -cne 'Stop')) { exit 0 }   # registered elsewhere (e.g. SubagentStop): never gate

    # ---- marker: {"session": "...", "plans": ["relative/path.md", ...]}
    $mi = Get-Item -LiteralPath $marker -Force
    if ($mi.Length -gt 65536) { exit 0 }
    $m = $null
    try { $m = [System.IO.File]::ReadAllText($mi.FullName, [System.Text.Encoding]::UTF8) | ConvertFrom-Json } catch { exit 0 }
    if (-not $m -or $m.GetType().FullName -ne 'System.Management.Automation.PSCustomObject') { exit 0 }
    $pp = $m.PSObject.Properties['plans']
    if (-not $pp -or -not ($pp.Value -is [System.Array])) { exit 0 }
    $plans = @()
    foreach ($x in $pp.Value) {
        if ($x -is [string] -and -not ($x -cmatch '[\x00-\x1f]')) { $plans += $x }
    }
    $msess = ''
    $sp = $m.PSObject.Properties['session']
    if ($sp -and ($sp.Value -is [string])) { $msess = [string]$sp.Value }
    if ($msess -ceq '${CLAUDE_SESSION_ID}' -or $msess -ceq '$CLAUDE_SESSION_ID') { $msess = '' }   # not substituted: no session
    if ($msess) {
        if ($msess -cne $sid) { exit 0 } # another session's (or a committed) marker never gates
    } elseif ($mi.LastWriteTimeUtc -le [DateTime]::UtcNow.AddHours(-12)) {
        exit 0                           # session-less marker older than 12 h
    }

    # ---- plan files: relative, no "..", no ":", no symlink/junction below cwd, regular file, <= 1 MB
    function Get-PlanFile([string]$Root, [string]$P) {
        if (-not $P) { return $null }
        if ($P.StartsWith('/') -or $P.StartsWith('\') -or $P.StartsWith('~') -or $P.Contains('..') -or $P.Contains(':')) { return $null }
        $d = $Root.TrimEnd('/', '\')
        foreach ($comp in ($P -split '[\\/]')) {
            if (-not $comp -or $comp -eq '.') { continue }
            $d = Join-Path $d $comp
            if (-not (Test-Path -LiteralPath $d)) { return $null }
            $it = Get-Item -LiteralPath $d -Force
            if ($it.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { return $null }
        }
        if (-not (Test-Path -LiteralPath $d -PathType Leaf)) { return $null }
        if ((Get-Item -LiteralPath $d -Force).Length -gt 1048576) { return $null }
        return $d
    }

    function Get-Plain([string]$S) { return ($S -creplace '[*_`]', '').Trim(' ', "`t") }
    function Test-Sep([string]$W) {
        $W = $W.TrimStart(' ', "`t")
        return ($W -eq '' -or $W -cmatch '^([,;.(:-]|\u00B7|\u2014|\u2013)')
    }
    function Test-Open([string]$V) {
        $mm = [regex]::Match($V, '^(todo|to[ -]?do|pending|open|in[ -]?progress|not[ -]?started)')
        return ($mm.Success -and (Test-Sep $V.Substring($mm.Length)))
    }
    function Test-AcOpen([string]$V) {
        $mm = [regex]::Match($V, '^(open|partial|not[ -]?met)')
        return ($mm.Success -and (Test-Sep $V.Substring($mm.Length)))
    }
    function Format-Item([string]$T) {
        $T = ($T -creplace '[*`]', '').Trim(' ', "`t") -replace "`t", ' '
        if (-not $T) { $T = '(no text)' }
        if ($T.Length -gt 80) { $T = $T.Substring(0, 80) }
        return ($T -creplace '[\x00-\x1f\x7f]', '')
    }

    # Returns the item text (<= 80 chars) of every open item in the file.
    function Get-OpenItems([string]$Path) {
        $items = New-Object System.Collections.Generic.List[string]
        $text = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
        $fence = ''; $incom = $false; $statcol = 0; $ctx = ''
        foreach ($ln in ($text -split "`n")) {
            $line = $ln
            if ($line.EndsWith("`r")) { $line = $line.Substring(0, $line.Length - 1) }
            if (-not $incom) {
                $t = $line.TrimStart(' ', "`t")
                $f3 = if ($t.Length -ge 3) { $t.Substring(0, 3) } else { $t }
                if (-not $fence -and ($f3 -ceq '```' -or $f3 -ceq '~~~')) { $fence = $f3; continue }
                if ($fence) { if ($f3 -ceq $fence) { $fence = '' }; continue }
            }
            $out = ''; $rest = $line
            while ($true) {
                if ($incom) {
                    $i = $rest.IndexOf('-->', [StringComparison]::Ordinal)
                    if ($i -lt 0) { $rest = ''; break }
                    $rest = $rest.Substring($i + 3); $incom = $false
                }
                $i = $rest.IndexOf('<!--', [StringComparison]::Ordinal)
                if ($i -lt 0) { $out += $rest; break }
                $out += $rest.Substring(0, $i); $rest = $rest.Substring($i + 4); $incom = $true
            }
            $line = $out
            if ($line -cmatch '^[ \t]*$') { continue }
            if ($line -cmatch '^[ \t]*([-*+]|[0-9]+[.)])[ \t]+\[[ \t]\]') {
                $items.Add((Format-Item ($line -creplace '^[ \t]*([-*+]|[0-9]+[.)])[ \t]+\[[ \t]\][ \t]*', '')))
                continue
            }
            if ($line -cmatch '^[ \t]*\|') {
                $c = $line.Replace('\|', [string][char]1).Split('|')
                $first = (Get-Plain $c[1]).ToLowerInvariant()
                if ($first -ceq 'ac') {
                    $statcol = 0
                    for ($k = 2; $k -lt $c.Length; $k++) { if ((Get-Plain $c[$k]).ToLowerInvariant() -ceq 'status') { $statcol = $k; break } }
                    continue
                }
                if ($first -cmatch '^ac[0-9]+$') {
                    $hit = $false
                    if ($statcol -gt 0) {
                        if ($statcol -lt $c.Length -and (Test-AcOpen (Get-Plain $c[$statcol]).ToLowerInvariant())) { $hit = $true }
                    } else {
                        for ($k = 2; $k -lt $c.Length - 1; $k++) { if (Test-AcOpen (Get-Plain $c[$k]).ToLowerInvariant()) { $hit = $true; break } }
                    }
                    if ($hit) {
                        $r = ''; if ($c.Length -gt 2) { $r = (Get-Plain $c[2]).Replace([string][char]1, '|') }
                        $items.Add((Format-Item ($first.ToUpperInvariant() + ': ' + $r)))
                    }
                    continue
                }
            }
            $s0 = [regex]::Replace($line, '`[^`]*`', '') -creplace '[*_]', ''
            $s = $s0.ToLowerInvariant()
            $mm = [regex]::Match($s, '(^|[^a-z0-9])status[ \t]*:[ \t]*')
            if ($mm.Success) {
                if (Test-Open $s.Substring($mm.Index + $mm.Length)) {
                    $n = $mm.Index + 1
                    if ($s.Substring($mm.Index).StartsWith('status')) { $n = $mm.Index }
                    $pre = $s0.Substring(0, $n) -creplace '^[ \t]*([-+>]|[0-9]+[.)])?[ \t]*', ''
                    $pre = $pre -creplace '([ \t,;:(|-]|\u00B7|\u2014|\u2013)+$', ''
                    if (-not $pre) { $pre = $ctx }
                    if (-not $pre) { $pre = $s0.Trim(' ', "`t") }
                    $items.Add((Format-Item $pre))
                }
                continue
            }
            if ($line -cmatch '^[ \t]*#') {
                $ctx = Get-Plain ($line -creplace '^[ \t]*#+[ \t]*', '')
            } elseif ($line -cmatch '^[ \t]*([-*+]|[0-9]+[.)])[ \t]+') {
                $ctx = Get-Plain ($line -creplace '^[ \t]*([-*+]|[0-9]+[.)])[ \t]+(\[[ xX]\][ \t]*)?', '')
            }
        }
        return ,$items
    }

    $total = 0; $names = @(); $items = @(); $hashIn = ''
    $nplans = 0
    foreach ($p in $plans) {
        $nplans++; if ($nplans -gt 20) { break }
        $f = $null
        try { $f = Get-PlanFile $cwd $p } catch { $f = $null }
        if (-not $f) { continue }
        try {
            $found = Get-OpenItems $f
            $sha = [System.Security.Cryptography.SHA256]::Create()
            $hashIn += $p + ':' + ([BitConverter]::ToString($sha.ComputeHash([System.IO.File]::ReadAllBytes($f))) -replace '-', '') + ';'
        } catch { continue }
        if ($found.Count -eq 0) { continue }
        $total += $found.Count
        $names += $p
        $items += @($found)
    }

    # ---- state: per-session counter + plan hash at the last block (same dir as verify.ps1)
    $key = $sid -replace '[^A-Za-z0-9_-]', ''
    if ($key.Length -gt 100) { $key = $key.Substring(0, 100) }
    if (-not $key) { $key = 'no-session' }
    $state = $null
    try {
        $tmp = if ($env:TEMP) { $env:TEMP } else { [System.IO.Path]::GetTempPath() }
        $dir = Join-Path $tmp 'claude-verify'
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        if (Test-Path -LiteralPath $dir -PathType Container) { $state = Join-Path $dir "$key.plangate" }
    } catch { $state = $null }
    function Clear-State { if ($state) { Remove-Item -LiteralPath $state -Force -ErrorAction SilentlyContinue } }

    if ($total -eq 0) { Clear-State; exit 0 }   # every item closed (or no readable plan): done

    # The turn ends with a question to the owner: let it stop (the answer starts a new turn).
    $msg = if ($in -and $in.last_assistant_message) { [string]$in.last_assistant_message } else { '' }
    $last = ''
    foreach ($l in ($msg -split "`n")) { $l = $l -replace "`r", ''; if ($l -notmatch '^[ \t\v\f]*$') { $last = $l } }
    $last = $last -creplace '[ \t\v\f*_`"'')]+$', ''
    if ($last.EndsWith('?')) { Clear-State; exit 0 }

    $max = 3
    $mx = "$env:CLAUDE_PLAN_GATE_MAX_BLOCKS"
    if ($mx -match '^[0-9]+$') { if ($mx.Length -gt 4) { $max = 9999 } else { $max = [int]$mx } }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $hash = [BitConverter]::ToString($sha.ComputeHash($utf8.GetBytes($hashIn))) -replace '-', ''
    $count = 0; $lastHash = ''
    if ($active) {                       # a continuation we (or another Stop hook) caused
        if ($state -and (Test-Path -LiteralPath $state)) {
            try {
                $parts = ([string](Get-Content -LiteralPath $state -TotalCount 1)).Trim() -split ' '
                if ($parts[0] -match '^[0-9]+$') { if ($parts[0].Length -gt 4) { $count = 9999 } else { $count = [int]$parts[0] } }
                if ($parts.Length -gt 1) { $lastHash = $parts[1] }
            } catch { $count = 0 }
        } elseif (-not $state) {
            $count = $max                # can't count safely: allow this stop
        }
    }                                    # not active = first stop of a new turn: count 0
    $nameStr = $names -join ', '
    if ($nameStr.Length -gt 120) { $nameStr = $nameStr.Substring(0, 117) + '...' }

    function Write-Bytes($Stream, [string]$Text) {
        $b = $utf8.GetBytes($Text + "`n"); $Stream.Write($b, 0, $b.Length); $Stream.Flush()
    }
    function Send-Message([string]$Text) {   # non-blocking message shown to the owner (systemMessage)
        $t = ($Text -replace "[`t`r`n]", ' ') -replace '[\x00-\x1f"\\]', ''
        Write-Bytes ([Console]::OpenStandardOutput()) ([pscustomobject]@{ systemMessage = $t } | ConvertTo-Json -Compress)
    }

    if ($active -and $count -gt 0 -and $lastHash -and ($hash -eq $lastHash)) {
        Clear-State
        Send-Message "plan-gate: $total item(s) still open in $nameStr and no plan file changed since the last nudge, so this stop is not blocked - plan NOT complete."
        exit 0
    }
    if ($count -ge $max) {
        Clear-State
        Send-Message "plan-gate: $total item(s) still open in $nameStr after $count nudges - plan NOT complete. CLAUDE_PLAN_GATE_MAX_BLOCKS sets how many nudges are forced."
        exit 0
    }

    $count++
    if ($state) { try { Set-Content -LiteralPath $state -Value "$count $hash" } catch {} }
    $list = @()
    for ($i = 0; $i -lt [Math]::Min(5, $items.Count); $i++) { $list += ('{0}) {1}' -f ($i + 1), $items[$i]) }
    $more = ''; if ($total -gt 5) { $more = " (+$($total - 5) more)" }
    $text = "plan-gate: $total open item(s) in $nameStr (nudge $count of $max). Implement them, or mark each Status: blocked " +
        [char]0x2014 + " <reason>. Never mark an item done that isn't. Open: " + ($list -join '; ') + $more
    while ($utf8.GetByteCount($text) -gt 600) { $text = $text.Substring(0, $text.Length - 1) }   # <= 600 bytes, like the .sh twin
    Write-Bytes ([Console]::OpenStandardError()) $text
    exit 2
} catch { exit 0 }
