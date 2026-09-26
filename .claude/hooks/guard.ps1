#requires -Version 5
# guard.ps1 - OPTIONAL PreToolUse guard for Claude Code (Windows / PowerShell).
#
# Keep in sync with guard.sh. Adds *mechanical* enforcement on top of the settings.json
# deny-list. Read/Edit deny rules now also cover the shell readers Claude Code recognises
# (cat/head/tail/sed/tee and < > redirect targets), but NOT grep -r, interpreters
# (python/node/...), npx, sh -c, or paths outside a rule's anchor (a **/ rule starts at the
# working directory, so home dirs need ~/ rules). Bash(...) denies do not apply to the
# PowerShell tool at all, and miss absolute paths such as C:\Windows\System32\curl.exe.
# This guard adds those:
#   * Shell tools - Bash, PowerShell (a separate tool on Windows) and Monitor (command, or ws url):
#       - BLOCKS reads/copies of protected secret paths (same list as the settings.json
#         deny-list, incl. ~\.aws, ~\.config\gh, ~\.claude\.credentials.json, .kube, .docker)
#         by shell readers AND interpreters (python, node, deno, bun, perl, ruby, php, pwsh,
#         bash -c / sh -c, source, rg, jq, npx ...);
#       - PROMPTS on shell commands that overwrite, move or delete a fix-once file
#         (REGRESSIONS.md, .claude\guards.*, .claude\checks.*, banned-phrases.txt);
#         appends (>>, tee -a, Add-Content) to the ledger or banned list pass;
#         an interpreter (python, node, ruby, perl, pwsh ...), sort -o, awk -i inplace or
#         ruby -i in the same command segment as such a file counts as a change (running a
#         guard runner, e.g. pwsh -File .claude\guards.ps1, does not);
#       - PROMPTS on whole-tree git reverts (git checkout/restore -- ., git reset --hard,
#         git checkout -f) when the repo root has a REGRESSIONS.md, and on any command that
#         sets or passes ALLOW_GUARD_CHANGE / GUARD_BASE_REF (they bypass or re-base the
#         ledger's append-only check);
#       - PROMPTS on network egress: curl/wget by any path, Invoke-WebRequest/RestMethod,
#         Start-BitsTransfer, bitsadmin, certutil -urlcache, WebClient, nc/ssh/scp/rsync/...,
#         an interpreter given a non-localhost URL, and a Monitor WebSocket source.
#   * Write/Edit of fix-once files (regression-guard skill):
#       - REGRESSIONS.md: PROMPTS only if an existing R-### row would disappear or change
#         (pure appends pass silently);
#       - .claude\guards.* and .claude\checks.* (not the .log): always PROMPTS;
#       - brand\banned-phrases.txt: PROMPTS if a non-comment line would be removed or changed.
#   * Write/Edit of a generated "<framework>-expert.md" agent file: BLOCKS over-privileged
#           tools (anything beyond Read/Write/Edit/Grep/Glob), BLOCKS writes outside the
#           workspace, and PROMPTS if the Guardrails section is missing.
#
# Register with matcher "Bash|PowerShell|Monitor|Write|Edit" (see settings.hooks.example.json).
# It reads the hook JSON from stdin and prints a permission decision as JSON on stdout.
# It matches command text, so it is a speed bump, not a sandbox.
# ANY unexpected error exits 0 (defer to the normal permission flow) so it can never
# wedge a session. It deliberately does NOT touch the curated agents - only files
# whose name ends in "-expert.md" (the team-configurator generation convention).

try {
    # Read stdin as UTF-8 (Claude Code sends UTF-8; the console default would mangle non-ASCII).
    $reader = New-Object System.IO.StreamReader([Console]::OpenStandardInput(), [System.Text.Encoding]::UTF8)
    $raw = $reader.ReadToEnd()
    if (-not $raw) { exit 0 }
    $in = $raw | ConvertFrom-Json
} catch { exit 0 }

function Decide($decision, $reason) {
    [pscustomobject]@{
        hookSpecificOutput = [pscustomobject]@{
            hookEventName            = 'PreToolUse'
            permissionDecision       = $decision     # 'deny' | 'ask' | 'allow'
            permissionDecisionReason = $reason
        }
    } | ConvertTo-Json -Depth 6 -Compress
    exit 0
}

try {
$tool = [string]$in.tool_name
$cwd  = [string]$in.cwd

# --- pattern lists (lower-case .NET regex; guard.sh holds the same lists in ERE) ------------
# Commands that can read or copy a file's content: shell readers + interpreters.
$readers = 'get-content|\bgc\b|\bcat\b|\btype\b|\bsls\b|select-string|\bmore\b|\bless\b|\bhead\b|\btail\b|\bnl\b|\bcut\b|\bgrep\b|\begrep\b|\bsed\b|\bawk\b|\bbase64\b|\bxxd\b|\bod\b|\bstrings\b|\bdd\b|\btar\b|\brsync\b|format-hex|copy-item|\bcp\b|move-item|\bmv\b|out-file|set-content'
$readers += '|\brg\b|\bfindstr\b|\bjq\b|\byq\b|\bzip\b|\b7z\b|\bgpg\b|\bcertutil\b|\bxcopy\b|\brobocopy\b|readall(text|bytes|lines)'
$interp  = '\bpython[0-9.]*\b|\bnode\b|\bdeno\b|\bbunx?\b|\bnpx\b|\bperl\b|\bruby\b|\bphp\b|\bpwsh\b|powershell|\b(ba|z|da|k)?sh\s+-[a-z]*c\b'
$readers = '(?m)' + $readers + '|' + $interp + '|\bsource\b|(^|[;&|({])\s*\.\s+\S'
# Protected secret paths (mirrors the settings.json Read deny-list, incl. home-dir credentials).
$secrets = '\.env\b|\.envrc|\.ssh|\.aws|\.azure|gcloud|secrets[\\/]|\.git-credentials|\.pgpass|\.my\.cnf|\.tfstate|\.tfvars|id_rsa|id_ed25519|\.pem\b|\.pfx\b|\.p12\b|\.key\b'
$secrets += '|\.netrc|\.npmrc|\.pypirc|\.gnupg|\.kube|\.docker\b|\.config[\\/]gh\b|\.credentials\.json|\.keystore\b|\.jks\b|\.ppk\b|id_ecdsa|id_dsa|_rsa\b|_ed25519\b|_ecdsa\b|_dsa\b|gha-creds-\S*\.json|service-account\S*\.json|[\\/]credentials(\.[a-z0-9]+)?([^a-z0-9_./-]|$)'
# Network egress (substring match on curl/wget also catches ...\curl.exe and /usr/bin/curl).
$egress  = 'curl|wget|invoke-webrequest|\biwr\b|invoke-restmethod|\birm\b|bitsadmin|ncat|telnet|\bnc\b|\bscp\b|\bsftp\b|\bftp\b|\bssh\b|\brsync\b'
$egress += '|start-bitstransfer|certutil.*(urlcache|verifyctl)|net\.webclient|downloadstring|downloadfile'
# Fix-once files and the shell verbs that overwrite, move or delete them.
$fixonce = 'regressions\.md|\.claude[\\/](guards|checks)\.(sh|ps1|cmd|bat)\b|banned-phrases\.txt'
$mutate  = '\bsed\b.*\s(-[a-z]*i|--in-place)|\bperl\b.*\s-[a-z]*i|\b(rm|mv|cp|truncate|unlink|shred|ln|chmod|dd|install)\b|\bgit\s+(checkout|restore|rm|mv)\b'
$mutate += '|set-content|\bsc\b|remove-item|\bri\b|\bdel\b|\berase\b|move-item|\bmi\b|\bmove\b|rename-item|\bren\b|copy-item|\bcpi\b|\bcopy\b|clear-content|\bclc\b|new-item|\bni\b|writeall(text|bytes|lines)'
# In-place rewriters that name the file as an option value: sort -o, (g)awk -i inplace, ruby -i.
$mutate += '|\bsort\b.*\s(-[a-z]*o\s*|--output[=\s]+)["'']?[^\s"'']*(' + $fixonce + ')'
$mutate += '|\bg?awk\b.*\s(-i|--include)[=\s]*["'']?inplace\b|\bruby\b.*\s-[a-z]*i'
$redirect = '(^|[^>])>[|]?\s*["'']?[^\s>]*(' + $fixonce + ')'
$teeOver  = '(^|[^a-z0-9_-])tee\s[^|]*(' + $fixonce + ')'
$runner   = '\.claude[\\/](guards|checks)\.(sh|ps1|cmd|bat)\b'   # appending to these can switch a guard off
# Running a guard runner (pwsh -File <runner>, bash <runner>, & <runner>) is not an interpreter edit.
$runexec  = '((pwsh|powershell)(\.exe)?(\s.*)?\s-f(ile)?|(^|[^a-z0-9_-])(ba|z|da|k)?sh|&)\s+["'']?[^\s"'']*(' + $runner + ')'
# Env switches of the ledger's append-only check (guards.sh / guards.ps1 / CI).
$bypass   = 'allow_guard_change|guard_base_ref'
# git commands that revert the whole tree (or .claude\ or brand\) - they never name the ledger.
$revert   = '\bgit\b.*\s(checkout|restore)\b.*\s["'']?(\.|\.[\\/]|\.[\\/]\*\S*|\*\S*|:\S*|\.claude[\\/]?|brand[\\/]?)["'']?(\s|$)'
$revert  += '|\bgit\b.*\sreset\b.*\s--hard\b|\bgit\b.*\s(checkout|switch)\b.*\s(-f|--force|--discard-changes)(\s|$)'

if (@('Bash', 'PowerShell', 'Monitor') -contains $tool) {
    $cmd = [string]$in.tool_input.command
    if (-not $cmd) {
        $ws = [string]$in.tool_input.ws.url   # Monitor can stream a WebSocket instead of a command
        if ($ws) { Decide 'ask' "Monitor opens a network connection ($ws) - confirm this does not move data off the machine." }
        exit 0
    }
    $lc = $cmd.ToLowerInvariant()

    # 1. Secret read/copy -> deny. Code idioms like process.env / import.meta.env are not .env
    #    files, so they are neutralised before the secret match (a real .env path still matches).
    $lcs = $lc -replace '(process|import\.meta|deno|bun)\.env([^a-z0-9_]|$)', '${1}_envref${2}'
    if ($lc -match $readers -and $lcs -match $secrets) {
        Decide 'deny' 'Blocked: shell or interpreter read/copy of a protected secret path. The Read deny-list covers only some shell readers and paths - this guard covers the rest.'
    }

    # 2. Fix-once files overwritten/moved/deleted from the shell -> ask (checked per command
    #    segment split on ; && || and newlines; appends to the ledger or banned list pass).
    if ($lc -match $bypass) {
        Decide 'ask' "This command sets or passes ALLOW_GUARD_CHANGE / GUARD_BASE_REF: this bypasses or re-bases the fix-once ledger check - needs the owner's explicit OK."
    }
    $segs = @($lc -split '&&|\|\||;|\r?\n')
    if ($lc -match $revert) {   # whole-tree revert: can drop uncommitted ledger rows / guard edits
        $base = if ($cwd) { $cwd } else { (Get-Location).Path }
        $top = $base
        if (-not (Test-Path -LiteralPath (Join-Path $top 'REGRESSIONS.md') -PathType Leaf)) {
            $top = ''
            if (Get-Command git -ErrorAction SilentlyContinue) {
                $top = [string](@(& git -C $base rev-parse --show-toplevel 2>$null) | Select-Object -First 1)
            }
        }
        if ($top -and (Test-Path -LiteralPath (Join-Path $top 'REGRESSIONS.md') -PathType Leaf)) {
            foreach ($seg in $segs) {
                if ($seg -notmatch $revert) { continue }
                # 'git restore --staged <paths>' only unstages: the working tree is untouched.
                if (($seg -match '\brestore\b.*\s--staged\b') -and ($seg -notmatch '\s(--worktree|-w)\b|\b(checkout|reset|switch)\b')) { continue }
                Decide 'ask' "This git command reverts the whole working tree (or .claude\, brand\) in a repo with a REGRESSIONS.md - it can silently drop uncommitted ledger rows, banned phrases or guard changes. Guards are never weakened without the owner's explicit OK - confirm."
            }
        }
    }
    if ($lc -match $fixonce) {
        foreach ($seg in $segs) {
            if ($seg -notmatch $fixonce) { continue }
            $hit = ($seg -match $mutate) -or ($seg -match $redirect)
            if ($seg -match $interp) {       # an interpreter can rewrite any file it names
                # ... unless it only runs a guard runner
                if ([regex]::Matches($seg, $runexec).Count -lt [regex]::Matches($seg, $fixonce).Count) { $hit = $true }
            }
            if (($seg -match $teeOver) -and ($seg -notmatch 'tee\s+(-a|--append)')) { $hit = $true }
            if (($seg -match 'out-file') -and ($seg -notmatch '-append')) { $hit = $true }
            if ($seg -match $runner) {                     # runners: appends count as edits too
                if ($seg -match ('>>\s*["'']?[^\s>]*(' + $runner + ')')) { $hit = $true }
                if ($seg -match ('(^|[^a-z0-9_-])tee\s[^|]*(' + $runner + ')')) { $hit = $true }
                if ($seg -match 'add-content|\bac\b|out-file') { $hit = $true }
            }
            if ($hit) { Decide 'ask' "This command may change, move or delete a fix-once file (REGRESSIONS.md, .claude\guards.*, .claude\checks.*, banned-phrases.txt). Guards are never weakened without the owner's explicit OK - confirm. Appends to REGRESSIONS.md or banned-phrases.txt (>>, tee -a, Add-Content) pass without asking." }
        }
    }

    # 3. Network egress -> ask.
    if ($lc -match $egress) {
        Decide 'ask' 'Possible network egress detected - confirm this does not move data off the machine.'
    }
    if ($lc -match $interp) {
        foreach ($m in [regex]::Matches($lc, '(https?|ftps?|wss?)://([^/\s?#"''<>]+)')) {
            $h = $m.Groups[2].Value -replace '^[^@]*@', ''
            if ($h -notmatch '^(localhost|127\.[0-9.]+|0\.0\.0\.0|\[::1\])(:[0-9]+)?$') {
                Decide 'ask' 'Interpreter command with a network URL - possible egress that the curl/wget deny rules do not see. Confirm this does not move data off the machine.'
            }
        }
    }
    exit 0
}

if ($tool -eq 'Write' -or $tool -eq 'Edit') {
    $rawPath = [string]$in.tool_input.file_path
    if (-not $rawPath) { exit 0 }

    # --- Fix-once files -------------------------------------------------------------------
    $lp = '/' + ($rawPath -replace '\\', '/').ToLowerInvariant()
    $kind = ''
    if ($lp -like '*/regressions.md') { $kind = 'ledger' }
    elseif ($lp -like '*/.claude/guards.log' -or $lp -like '*/.claude/checks.log') { }
    elseif ($lp -like '*/.claude/guards.*' -or $lp -like '*/.claude/checks.*') {
        Decide 'ask' "Editing a guard runner or checks wrapper ($rawPath). Guards are never weakened without the owner's explicit OK - confirm this change keeps every guard at least as strict."
    }
    elseif ($lp -like '*/brand/banned-phrases.txt') { $kind = 'phrases' }

    if ($kind) {
        $abs = $rawPath
        if (-not [System.IO.Path]::IsPathRooted($abs)) { $abs = Join-Path $(if ($cwd) { $cwd } else { '.' }) $abs }
        $before = ''
        if (Test-Path -LiteralPath $abs -PathType Leaf) {
            $before = [System.IO.File]::ReadAllText($abs, [System.Text.Encoding]::UTF8) -replace "`r", ''
        }
        if ($tool -eq 'Write') {
            $after = ([string]$in.tool_input.content) -replace "`r", ''
        } else {
            $old = ([string]$in.tool_input.old_string) -replace "`r", ''
            $new = ([string]$in.tool_input.new_string) -replace "`r", ''
            if ($old -and $before.Contains($old)) {                  # replay the edit on the file
                if ($in.tool_input.replace_all -eq $true) {
                    $after = $before.Replace($old, $new)
                } else {
                    $i = $before.IndexOf($old, [System.StringComparison]::Ordinal)
                    $after = $before.Substring(0, $i) + $new + $before.Substring($i + $old.Length)
                }
            } else {                                                  # can't place it: compare the snippets
                $before = $old; $after = $new
            }
        }
        $filter = if ($kind -eq 'ledger') { '^\s*\|\s*R-[0-9]+' } else { '^\s*[^#\s]' }
        $afterLines = @($after -split "`n")
        $gone = @(($before -split "`n") | Where-Object { ($_ -cmatch $filter) -and ($afterLines -cnotcontains $_) })
        if ($gone.Count -gt 0) {
            if ($kind -eq 'ledger') {
                $ids = (@([regex]::Matches(($gone -join ' '), 'R-[0-9]+') | Select-Object -First 5 | ForEach-Object { $_.Value }) -join ' ')
                Decide 'ask' "This edit removes or changes existing REGRESSIONS.md row(s): $ids - rows are never deleted or rewritten without the owner's explicit OK (retire with 'retired:'). Pure appends pass without asking."
            } else {
                $first = (@($gone | Select-Object -First 3) -join '; ')
                Decide 'ask' "This edit removes or changes banned phrase line(s) in brand/banned-phrases.txt ($first). Banned phrases are never removed without the owner's explicit OK."
            }
        }
        exit 0
    }

    # --- Generated specialists (unchanged policy) -----------------------------------------
    $path = $rawPath -replace '\\','/'
    if ($path -notmatch '\.claude/agents/.*-expert\.md$') { exit 0 }   # only police generated specialists

    $cwd = $cwd -replace '\\','/'
    $isAbsolute = ($path -match '^[A-Za-z]:/') -or ($path.StartsWith('/'))
    if ($isAbsolute -and $cwd -and -not $path.ToLower().StartsWith($cwd.ToLower())) {
        Decide 'deny' "Blocked: refusing to write a generated agent outside the project workspace ($path)."
    }

    $content = if ($tool -eq 'Write') { [string]$in.tool_input.content } else { [string]$in.tool_input.new_string }
    if ($content) {
        $toolsLine = ($content -split "`n") | Where-Object { $_ -match '^\s*tools\s*:' } | Select-Object -First 1
        if ($toolsLine) {
            $declared = ($toolsLine -replace '^\s*tools\s*:\s*','') -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
            $allowed  = @('Read','Write','Edit','Grep','Glob')
            $bad = @($declared | Where-Object { $allowed -notcontains $_ })
            if ($bad.Count -gt 0) {
                Decide 'deny' ("Blocked: generated agent requests disallowed tool(s): " + ($bad -join ', ') + ". Generated specialists may use only Read/Write/Edit/Grep/Glob.")
            }
        }
        if ($content -notmatch '(?im)^\s*##\s*Guardrails') {
            Decide 'ask' 'Generated agent is missing a Guardrails section - review the file before enabling it.'
        }
    }
    exit 0
}

exit 0
} catch { exit 0 }
