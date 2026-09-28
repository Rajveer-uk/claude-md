#requires -Version 5
# review-gate.ps1 - OPTIONAL PreToolUse hook (Windows): no `git commit` until the diff being
# committed has been reviewed. Linux/macOS/cloud twin: review-gate.sh (same logic).
#
# Rule it enforces (the owner's): every change is verified before it is applied - code-reviewer and
# ponytail review the diff, every blocking finding is fixed, the guards are re-run, and only then is
# the change committed. A tiny diff (up to CLAUDE_REVIEW_GATE_INLINE_MAX changed lines, default 10)
# may use the inline checklist instead of the two agents.
#
# Two modes, one script:
#   Hook (stdin = PreToolUse JSON for Bash / PowerShell / Monitor): when the command runs `git commit`,
#     it fingerprints the diff that commit would record (`git diff --cached`, or `git diff HEAD` for
#     -a/--all) and denies the call unless a review was recorded for exactly that fingerprint. Any
#     edit after recording changes the fingerprint and needs a new review. It follows `cd`/`pushd`/
#     `Set-Location` and `git -C` (quoted or not), a path-prefixed `git`/`git.exe` (/ or \), global
#     options such as --no-pager, `sh -c '...'`, $(...), and commands on separate lines; a commit
#     whose repository it can't resolve, and a command holding more than one `git commit`, are denied.
#     Other commands and an empty diff (message-only amend) pass untouched. Unusual quoting (e.g. mixed
#     quotes inside one path) and a commit inside backticks (left out so a message may quote
#     `git commit`) are not followed - the rule, not only the hook, still applies.
#   Record (run by Claude after the review is clean; same arguments as review-gate.sh):
#     powershell -NoProfile -ExecutionPolicy Bypass -File C:/Users/you/.claude/hooks/review-gate.ps1 --record agents
#     powershell -NoProfile -ExecutionPolicy Bypass -File C:/Users/you/.claude/hooks/review-gate.ps1 --record inline   # no binary files
#     (add --all when the commit will use -a; add -C <dir> for another repo)
#
# The record lives outside the repo (%TEMP%\claude-verify, like verify.ps1), so nothing is
# committed or left in the project. Fingerprint = SHA-256 of git's raw output bytes; the marker
# (review-<key>.ps.json) is this script's own - a marker written by review-gate.sh is not read here.
# It proves a review step happened and was stated in the transcript, not how good the review was -
# the reviewers' findings stay visible in the chat.
# Env: CLAUDE_REVIEW_GATE=0 turns the hook off for that session (owner's call; visible in the
#      command); CLAUDE_REVIEW_GATE_INLINE_MAX (default 10; e.g. 50 for a lighter gate).
# Safe on any repo: runs only git read commands, no network, no project code. The hook fails open
# on any unexpected error (the permission gate and the guards still apply).
# Register (user scope, exec form, absolute path - see .claude/settings.hooks.example.json):
#   "PreToolUse": [ { "matcher": "Bash|PowerShell|Monitor", "hooks": [ { "type": "command", "command": "powershell.exe",
#     "args": ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "C:/Users/you/.claude/hooks/review-gate.ps1"] } ] } ]

$argv = @($args)
$utf8 = New-Object System.Text.UTF8Encoding($false)
$sp = '[ \t\n\v\f\r]'                    # POSIX [[:space:]]

function Write-Bytes($Stream, [string]$Text) {   # UTF-8, no BOM, LF
    $b = $utf8.GetBytes($Text + "`n"); $Stream.Write($b, 0, $b.Length); $Stream.Flush()
}
function Write-Out([string]$Text) { Write-Bytes ([Console]::OpenStandardOutput()) $Text }
function Write-Err([string]$Text) { Write-Bytes ([Console]::OpenStandardError()) $Text }

function ConvertTo-Arg([string]$A) {     # one argv element for ProcessStartInfo.Arguments
    if ($A -and $A -notmatch '[ \t\n\v"]') { return $A }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('"'); $bs = 0
    foreach ($ch in $A.ToCharArray()) {
        if ($ch -eq [char]92) { $bs++; continue }
        if ($ch -eq [char]34) { [void]$sb.Append([char]92, 2 * $bs + 1) }
        elseif ($bs -gt 0) { [void]$sb.Append([char]92, $bs) }
        [void]$sb.Append($ch); $bs = 0
    }
    if ($bs -gt 0) { [void]$sb.Append([char]92, 2 * $bs) }
    [void]$sb.Append('"')
    return $sb.ToString()
}

# Runs git with the given arguments; returns @{ Code = <exit code>; Out = <raw stdout bytes> }.
# Raw bytes, so no console encoding or CRLF handling can change what is hashed.
function Invoke-Git([string[]]$GitArgs) {
    $exe = Get-Command git -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $exe) { return @{ Code = 127; Out = [byte[]]@() } }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $exe.Path
    $psi.Arguments = (@($GitArgs | ForEach-Object { ConvertTo-Arg $_ }) -join ' ')
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.WorkingDirectory = (Get-Location -PSProvider FileSystem).ProviderPath
    $p = [System.Diagnostics.Process]::Start($psi)
    try {
        $p.StandardInput.Close()
        $errTask = $p.StandardError.ReadToEndAsync()   # drain stderr (discarded, like 2>/dev/null)
        $ms = New-Object System.IO.MemoryStream
        $p.StandardOutput.BaseStream.CopyTo($ms)
        $p.WaitForExit()
        [void]$errTask.Result
        return @{ Code = $p.ExitCode; Out = $ms.ToArray() }
    } finally { $p.Dispose() }
}

function Get-TopLevel([string]$Dir) {    # repo top level, or $null outside a work tree
    $r = Invoke-Git @('-C', $Dir, 'rev-parse', '--show-toplevel')
    if ($r.Code -ne 0) { return $null }
    $t = $utf8.GetString($r.Out).TrimEnd("`r", "`n")
    if (-not $t) { return $null }
    return $t
}

function Get-Sha256Hex([byte[]]$Bytes) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes)) -replace '-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

# Repo top level -> private marker path (dir created lazily); $null when no safe dir is available.
function Get-StateFile([string]$Top) {
    $tmp = if ($env:TEMP) { $env:TEMP } else { [System.IO.Path]::GetTempPath() }
    $dir = Join-Path $tmp 'claude-verify'
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) { return $null }
    if ((Get-Item -LiteralPath $dir -Force).Attributes -band [System.IO.FileAttributes]::ReparsePoint) { return $null }
    $k = $Top
    if ($env:OS -eq 'Windows_NT') { $k = $k.Replace('\', '/').ToLowerInvariant() }   # NTFS: case-insensitive
    $key = (Get-Sha256Hex ($utf8.GetBytes($k))).Substring(0, 16)
    return (Join-Path $dir "review-$key.ps.json")
}

# Fingerprint of the diff a commit would record:
# @{ Fp = <sha256 hex>|'-' (empty diff); N = <changed lines>; B = <binary files> }.
function Get-Fingerprint([string]$Top, [bool]$All) {
    $base = if ($All) { @('-C', $Top, 'diff', 'HEAD') } else { @('-C', $Top, 'diff', '--cached') }
    $d = Invoke-Git ($base + '--binary')
    if ($d.Code -ne 0 -or $d.Out.Length -eq 0) { return @{ Fp = '-'; N = 0; B = 0 } }
    $n = [long]0; $b = 0
    $s = Invoke-Git ($base + '--numstat')
    if ($s.Code -eq 0) {
        foreach ($ln in ($utf8.GetString($s.Out) -split "`n")) {
            $f = @($ln -split "[ \t]+" | Where-Object { $_ -ne '' })   # awk fields; binary files show '-'
            if ($f.Count -gt 0 -and $f[0] -cmatch '^[0-9]{1,15}\z') { $n += [long]$f[0] }
            elseif ($f.Count -gt 0 -and $f[0] -ceq '-') { $b++ }
            if ($f.Count -gt 1 -and $f[1] -cmatch '^[0-9]{1,15}\z') { $n += [long]$f[1] }
        }
    }
    return @{ Fp = (Get-Sha256Hex $d.Out); N = $n; B = $b }
}

$inlineMaxText = "$env:CLAUDE_REVIEW_GATE_INLINE_MAX"
if (-not ($inlineMaxText -cmatch '^[0-9]+\z')) { $inlineMaxText = '10' }
$inlineMax = if ($inlineMaxText.Length -gt 18) { [long]::MaxValue } else { [long]$inlineMaxText }

# ---------------------------------------------------------------- record mode
if ($argv.Count -gt 0 -and [string]$argv[0] -ceq '--record') {
    try {
        $ErrorActionPreference = 'Stop'
        $mode = if ($argv.Count -gt 1) { [string]$argv[1] } else { '' }
        $all = $false; $dir = (Get-Location -PSProvider FileSystem).ProviderPath
        $i = 2
        while ($i -lt $argv.Count) {
            $a = [string]$argv[$i]
            if ($a -ceq '--all' -or $a -ceq '-a') { $all = $true; $i++ }
            elseif ($a -ceq '-C') { $dir = if ($i + 1 -lt $argv.Count) { [string]$argv[$i + 1] } else { '.' }; $i += 2 }
            else { $i++ }
        }
        if (-not ($mode -ceq 'agents' -or $mode -ceq 'inline')) {
            Write-Err 'usage: review-gate.ps1 --record agents|inline [--all] [-C dir]'; exit 2
        }
        $top = Get-TopLevel $dir
        if (-not $top) { Write-Err "review-gate: $dir is not a git repo"; exit 1 }
        $fp = Get-Fingerprint $top $all
        if ($fp.Fp -eq '-') { Write-Out 'review-gate: nothing to commit - no review needed'; exit 0 }
        $n = $fp.N
        if ($mode -ceq 'inline' -and $n -gt $inlineMax) {
            Write-Err "review-gate: $n changed lines is more than the inline limit ($inlineMaxText) - run code-reviewer and ponytail on the diff, then --record agents"
            exit 1
        }
        if ($mode -ceq 'inline' -and $fp.B -gt 0) {
            Write-Err "review-gate: the diff changes $($fp.B) binary file(s), which the inline checklist can't cover - run code-reviewer and ponytail on the diff, then --record agents"
            exit 1
        }
        $sf = $null
        try { $sf = Get-StateFile $top } catch { $sf = $null }
        if (-not $sf) { Write-Err 'review-gate: no private state dir available'; exit 1 }
        $at = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ', [System.Globalization.CultureInfo]::InvariantCulture)
        try {
            [System.IO.File]::WriteAllText($sf, ('{"diff":"' + $fp.Fp + '","mode":"' + $mode + '","lines":' + $n + ',"at":"' + $at + '"}' + "`n"), $utf8)
        } catch { Write-Err "review-gate: cannot write $sf"; exit 1 }
        Write-Out "review-gate: recorded an $mode review for this diff ($n changed lines). Commit now; any further edit needs a new review."
        exit 0
    } catch {
        Write-Err "review-gate: record failed: $($_.Exception.Message)"; exit 1
    }
}

# ---------------------------------------------------------------- hook mode (fail open)
try {
    $ErrorActionPreference = 'Stop'
    if ("$env:CLAUDE_REVIEW_GATE" -ceq '0') { exit 0 }
    $in = $null; $raw = ''
    try {
        # Read stdin as UTF-8 (Claude Code sends UTF-8; the console default would mangle non-ASCII paths).
        $reader = New-Object System.IO.StreamReader([Console]::OpenStandardInput(), [System.Text.Encoding]::UTF8)
        $raw = $reader.ReadToEnd()
        if ($raw) { $in = $raw | ConvertFrom-Json }
    } catch { $in = $null }
    if (-not $raw -or -not $in) { exit 0 }
    $tool = [string]$in.tool_name
    if (-not ($tool -ceq 'Bash' -or $tool -ceq 'PowerShell' -or $tool -ceq 'Monitor')) { exit 0 }
    $cmd = [string]$in.tool_input.command
    $cwd = [string]$in.cwd
    # One line: a line continuation (\ in sh, ` in PowerShell) joins, any other line break separates commands.
    $cont = if ($tool -ceq 'PowerShell') { '`' } else { '\' }
    $one = $cmd.Replace("`r", '').Replace($cont + "`n", ' ').Replace("`n", ';')
    # One argument, quoted or bare. POSIX ERE (the .sh twin) takes the LONGEST alternative, .NET the
    # first that fits: a quoted form wins only when it holds a blank or ;&| (else the bare token is
    # at least as long), so the quoted branches require one - same matches as the .sh.
    $sep = '[ \t\n\v\f\r;&|]'
    $bare = '[^ \t\n\v\f\r;&|]'
    $garg = '("[^"]*' + $sep + '[^"]*"|' + "'[^']*" + $sep + "[^']*'|" + $bare + '+)'
    # git's global options before the subcommand
    $gopt = $sp + '+(-[Cc]' + $sp + '+' + $garg + '|--[a-z-]+(=' + $garg + ')?|-[pP])'
    # `git commit` (also /path/git, C:\path\git.exe, global options) at the start of any command
    # segment, or inside `sh -c '...'`; never `git commit-tree`
    $gcommit = '(^|[;&|({]|&&|\|\||-c' + $sp + '+["''])' + $sp + '*(' + $bare + '*[/\\])?git(\.exe)?(' + $gopt + ')*' + $sp + '+commit(' + $sp + '|[;&|)"'']|\z)'
    $gm = [regex]::Match($one, $gcommit)
    if (-not $gm.Success) { exit 0 }
    if (-not $cwd) { $cwd = (Get-Location -PSProvider FileSystem).ProviderPath }

    function Get-Unquoted([string]$V) {  # strip one pair of quotes; ~ and ~/x (or ~\x) -> home
        $o = [StringComparison]::Ordinal
        if ($V.StartsWith('"', $o)) { $V = $V.Substring(1) }
        if ($V.EndsWith('"', $o)) { $V = $V.Substring(0, $V.Length - 1) }
        if ($V.StartsWith("'", $o)) { $V = $V.Substring(1) }
        if ($V.EndsWith("'", $o)) { $V = $V.Substring(0, $V.Length - 1) }
        if ($V -ceq '~') { $V = $HOME }
        elseif ($V.StartsWith('~/', $o) -or $V.StartsWith('~\', $o)) { $V = $HOME + '/' + $V.Substring(2) }
        return $V
    }
    function Resolve-Dir([string]$P, [string]$Base) {   # rooted (/x, \x, C:\x, C:/x) wins, else Base/P
        if ($P.StartsWith('/', [StringComparison]::Ordinal) -or $P.StartsWith('\', [StringComparison]::Ordinal) -or
            $P -cmatch '^[A-Za-z]:[\\/]') { return $P }
        return $Base + [System.IO.Path]::DirectorySeparatorChar + $P
    }
    function Get-LastMatch([string]$Text, [string]$Re, [System.Text.RegularExpressions.RegexOptions]$Opt = 'None') {
        $ms = [regex]::Matches($Text, $Re, $Opt)
        if ($ms.Count -eq 0) { return '' }
        return $ms[$ms.Count - 1].Value
    }
    function Send-Deny([string]$Reason) {   # same JSON as guard.ps1's Decide; Write-Out keeps UTF-8/LF
        Write-Out ([pscustomobject]@{ hookSpecificOutput = [pscustomobject]@{ hookEventName = 'PreToolUse'
            permissionDecision = 'deny'; permissionDecisionReason = $Reason } } | ConvertTo-Json -Depth 3 -Compress)
    }
    # one commit per command: pad each separator so back-to-back commits count apart
    if ([regex]::Matches([regex]::Replace($one, '[;&|()]', ' $0 '), $gcommit).Count -gt 1) {
        Send-Deny 'review-gate: this command runs more than one git commit (or its message holds git commit after a line break, ; & | or (). Run one commit per command, each after its own review is recorded.'
        exit 0
    }

    $dir = $cwd
    # a `cd <dir>` earlier in the same command moves the commit (the last one before `git ... commit` wins)
    $before = $one.Substring(0, $gm.Index)
    $cdRe = '(^|[;&|({ \t\n\v\f\r])(cd|pushd|chdir|set-location|sl)' + $sp + '+(-path' + $sp + '+|-literalpath' + $sp + '+)?' + $garg
    $cdto = Get-LastMatch $before $cdRe 'IgnoreCase, CultureInvariant'
    if ($cdto) { $dir = Resolve-Dir (Get-Unquoted ($cdto -replace ('^.?[A-Za-z-]+' + $sp + '+(-[A-Za-z]*path' + $sp + '+)?'), '')) $dir }
    # `git -C <dir> commit`, quoted or not
    # (only from the first `git ... commit` segment - the command itself; a later one sits inside the message)
    $seg = $gm.Value
    $cdir = Get-LastMatch $seg ($sp + '-C' + $sp + '+' + $garg)
    if ($cdir) { $dir = Resolve-Dir (Get-Unquoted ($cdir -creplace ('^' + $sp + '-C' + $sp + '+'), '')) $dir }
    $top = Get-TopLevel $dir
    if (-not $top) {                     # fail closed: a commit whose repository is unknown
        Send-Deny "review-gate: can't tell which repository this commit runs in ($dir). Commit from the repository folder, or use git -C <repo> commit, after the review is recorded there."
        exit 0
    }
    $all = [regex]::IsMatch($one, 'commit(' + $sp + '+[^;&|]*)?' + $sp + '(-a|--all|-[a-zA-Z]*a[a-zA-Z]*)(' + $sp + '|[;&|)]|\z)')
    $fp = Get-Fingerprint $top $all
    if ($fp.Fp -eq '-') { exit 0 }       # nothing staged: message-only amend, --allow-empty
    $n = $fp.N
    $sf = $null
    try { $sf = Get-StateFile $top } catch { $sf = $null }
    if (-not $sf) { exit 0 }
    if (Test-Path -LiteralPath $sf -PathType Leaf) {
        $txt = ''
        try { $txt = [System.IO.File]::ReadAllText($sf, [System.Text.Encoding]::UTF8) } catch { $txt = '' }
        if ($txt.Contains('"diff":"' + $fp.Fp + '"')) { exit 0 }
    }
    $topArg = if ($top -match '\s') { '"' + $top + '"' } else { $top }
    $flag = ' -C "' + $top + '"'; if ($all) { $flag += ' --all' }
    $range = if ($all) { ' HEAD' } else { ' --cached' }
    $self = $PSCommandPath
    if ($self -match '\s') { $self = '"' + $self + '"' }
    Send-Deny "review-gate: this commit's diff ($n changed lines) has no recorded review. Before committing: run code-reviewer and ponytail on the diff (git -C $topArg diff$range), fix every blocking finding, re-run the guards, then record it with: powershell -NoProfile -ExecutionPolicy Bypass -File $self --record agents$flag (a diff of $inlineMaxText lines or fewer, with no binary file, may use the inline checklist: --record inline$flag). Then commit again. Any edit after recording needs a new review."
    exit 0
} catch { exit 0 }
