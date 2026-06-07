#requires -Version 5
# guard.ps1 - OPTIONAL PreToolUse guard for Claude Code (Windows / PowerShell).
#
# Adds *mechanical* enforcement on top of the settings.json deny-list, which only
# covers the Read tool and is bypassable from a shell:
#   * Bash: PROMPTS on network-egress commands; BLOCKS shell reads/copies of protected
#           secret paths (the Read deny-list cannot see shell reads - this guard can).
#   * Write/Edit of a generated "<framework>-expert.md" agent file: BLOCKS over-privileged
#           tools (anything beyond Read/Write/Edit/Grep/Glob), BLOCKS writes outside the
#           workspace, and PROMPTS if the Guardrails section is missing.
#
# It reads the hook JSON from stdin and prints a permission decision as JSON on stdout.
# ANY unexpected error exits 0 (defer to the normal permission flow) so it can never
# wedge a session. It deliberately does NOT touch the curated agents - only files
# whose name ends in "-expert.md" (the team-configurator generation convention).

try {
    $raw = [Console]::In.ReadToEnd()
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

$tool = [string]$in.tool_name

if ($tool -eq 'Bash') {
    $cmd = [string]$in.tool_input.command
    if (-not $cmd) { exit 0 }
    $lc = $cmd.ToLowerInvariant()

    $egress = @('curl','wget','invoke-webrequest','\biwr\b','invoke-restmethod','\birm\b','bitsadmin','ncat','telnet','\bnc\b','\bscp\b','\bsftp\b','\bftp\b')
    foreach ($p in $egress) {
        if ($lc -match $p) { Decide 'ask' "Possible network egress detected - confirm this does not move data off the machine." }
    }

    $readers = @('get-content','\bgc\b','\bcat\b','\btype\b','\bsls\b','select-string','\bmore\b','copy-item','\bcp\b','move-item','\bmv\b','out-file','set-content')
    $secrets = @('\.env\b','\.envrc','\.ssh','\.aws','\.azure','gcloud','secrets[\\/]','\.git-credentials','\.pgpass','\.my\.cnf','\.tfstate','\.tfvars','id_rsa','id_ed25519','\.pem\b','\.pfx\b','\.p12\b','\.key\b')
    $isRead = $false
    foreach ($r in $readers) { if ($lc -match $r) { $isRead = $true; break } }
    if ($isRead) {
        foreach ($s in $secrets) {
            if ($lc -match $s) { Decide 'deny' 'Blocked: shell read/copy of a protected secret path. The Read deny-list does not cover shell reads - this guard does.' }
        }
    }
    exit 0
}

if ($tool -eq 'Write' -or $tool -eq 'Edit') {
    $path = ([string]$in.tool_input.file_path) -replace '\\','/'
    if ($path -notmatch '\.claude/agents/.*-expert\.md$') { exit 0 }   # only police generated specialists

    $cwd = ([string]$in.cwd) -replace '\\','/'
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
