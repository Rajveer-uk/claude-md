#requires -Version 5
# guards.ps1 - fix-once guard runner, Windows twin of guards.sh. TEMPLATE (claude-md/templates/guards.ps1):
# copy to <project>\.claude\guards.ps1 and COMMIT it next to .claude\guards.sh. Keep the step names
# in sync with guards.sh (ledger-integrity checks both runners).
#
# Usage:  powershell -NoProfile -ExecutionPolicy Bypass -File .claude\guards.ps1         full set - before done
#         powershell -NoProfile -ExecutionPolicy Bypass -File .claude\guards.ps1 -Fast   skips slow steps - mid-task only
# Output: one line per step - "OK <step>", "ERROR <step>: <reason>" or "SKIP <step>: <reason>" -
#         then one summary line. Full output of every step is appended to .claude\guards.log
#         (gitignore it). Every step runs; exit 1 if any step failed, 2 on a usage error.
# Env:    GUARD_BASE_REF      git ref the ledger must stay append-only against. Default: HEAD plus,
#                             when the branch has an upstream, its fork point (merge-base with @{u}),
#                             so a committed-but-unpushed row deletion is caught too. CI sets
#                             origin/<base branch> on pull requests and the pre-push commit on pushes.
#         ALLOW_GUARD_CHANGE  1 = skip the append-only check. Owner's explicit OK only.
#         CONTENT_DIRS        override the content-lint folder list below
#
# Add a check: step for any invariant a test can't cover (config, ops, content rules):
#   Step '<name>' [-Slow] { <commands> }   native exit code 0 = OK, other = ERROR. From PowerShell
#       code, output "ERROR: <reason>" and set $script:StepCode = 1 (never call exit inside a step);
#       "SKIP: <reason>" + $script:StepCode = 77 = SKIP.
# Reference it in REGRESSIONS.md as "check: <name>". Steps read files in this repo only - no
# network, no secrets, no production hosts. Needs PowerShell 5+; git is optional.
param([switch]$Fast, [switch]$Help)
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Continue'

# ---------------------------------------------------------------- configuration
# Full test suite (slow), PowerShell syntax. PS 5 has no '&&': use cmd /c "a && b" or separate lines; no 'exit'.
$TestCmd = ''
# $TestCmd = 'npm test --silent'
# $TestCmd = 'python -m pytest -q'
# $TestCmd = 'php artisan test'
# $TestCmd = 'go test ./...'

# Linter / type checker.
$LintCmd = ''
# $LintCmd = 'npm run lint --silent'
# $LintCmd = 'ruff check .'
# $LintCmd = 'cmd /c "vendor\bin\pint --test && vendor\bin\phpstan analyse --no-progress"'

# Folders content-lint scans for banned phrases (missing folders are ignored). A folder named
# brand is never scanned - it holds the rules. Keep in sync with .claude/rules/content.md paths.
# docs is not in the default list (engineering docs aren't brand copy) - add it if yours should be linted.
$ContentDirs = 'content blog posts copy marketing emails newsletters social landing-pages'
if ($env:CONTENT_DIRS) { $ContentDirs = $env:CONTENT_DIRS }
$BannedFile = 'brand/banned-phrases.txt'
$Ledger = 'REGRESSIONS.md'

# ---------------------------------------------------------------- setup
$Self = $MyInvocation.MyCommand.Path
$here = Split-Path -Parent $Self
$Twin = Join-Path $here 'guards.sh'

function Invoke-GitText([string[]]$GitArgs, [string]$Dir) {
  # Runs git and decodes its output as UTF-8 (PS 5 would use the console code page).
  try {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'git'
    $psi.Arguments = ($GitArgs | ForEach-Object { '"' + $_ + '"' }) -join ' '
    $psi.WorkingDirectory = $Dir
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $p = [System.Diagnostics.Process]::Start($psi)
    $out = $p.StandardOutput.ReadToEnd()
    $null = $p.StandardError.ReadToEnd()
    $p.WaitForExit()
    return @{ Code = $p.ExitCode; Out = $out }
  } catch {
    return @{ Code = 127; Out = '' }
  }
}

if ((Split-Path -Leaf $here) -eq '.claude') {
  $root = Split-Path -Parent $here
} else {
  $root = $here
  $top = Invoke-GitText @('rev-parse', '--show-toplevel') $here
  if ($top.Code -eq 0 -and $top.Out.Trim()) { $root = $top.Out.Trim() }
}
try { Set-Location -LiteralPath $root -ErrorAction Stop } catch { Write-Output "ERROR guards: cannot cd to $root"; exit 2 }
$rootFull = (Get-Location).Path

$FastMode = [bool]$Fast
foreach ($a in $args) {
  if ($a -eq '--fast') { $FastMode = $true }
  elseif ($a -eq '-h' -or $a -eq '--help') { $Help = $true }
  else { [Console]::Error.WriteLine('usage: powershell -NoProfile -ExecutionPolicy Bypass -File .claude\guards.ps1 [-Fast]'); exit 2 }
}
if ($Help) { Get-Content -LiteralPath $Self | Select-Object -Skip 1 -First 22; exit 0 }

$null = New-Item -ItemType Directory -Force -Path '.claude'
$Log = Join-Path $rootFull '.claude/guards.log'
if ((Test-Path -LiteralPath $Log) -and ((Get-Item -LiteralPath $Log).Length -gt 1MB)) {
  $keep = Get-Content -LiteralPath $Log -Tail 2000
  Set-Content -LiteralPath $Log -Value $keep -Encoding UTF8
}
function Write-Log([string[]]$Lines) { Add-Content -LiteralPath $Log -Value $Lines -Encoding UTF8 }
$fastNote = ''
if ($FastMode) { $fastNote = ' --fast' }
Write-Log @('', ('=== guards ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + $fastNote + ' ==='))

$script:ok = 0; $script:failed = 0; $script:skipped = 0; $script:failedNames = @(); $script:StepCode = $null
$esc = [char]27

function Get-Reason([string[]]$Lines, [int]$Code) {
  # The most useful single line of a step's output.
  $clean = @($Lines | ForEach-Object { ($_ -replace "$esc\[[0-9;]*[A-Za-z]", '') -replace "`r$", '' })
  $line = $null
  $hit = @($clean | Where-Object { $_ -match '^ERROR: ' } | Select-Object -First 1)
  if ($hit.Count -gt 0) { $line = $hit[0].Substring(7) }
  if (-not $line) {
    $hit = @($clean | Where-Object { $_ -cmatch '^\s*(FAILED|FAIL|--- FAIL|not ok)[\s:]|^E\s+\S|[A-Za-z]+(Error|Exception):|[Ff]ailed asserting|^\s*[0-9]+ (failed|errors?)' } | Select-Object -First 1)
    if ($hit.Count -gt 0) { $line = $hit[0] }
  }
  if (-not $line) {
    $hit = @($clean | Where-Object { ($_ -match 'fail|error|assert|not ok|panic|exception') -and ($_ -notmatch '^[\s=_*#-]*(FAILURES|ERRORS)?[\s=_*#-]*$') -and ($_ -notmatch '^Traceback') } | Select-Object -First 1)
    if ($hit.Count -gt 0) { $line = $hit[0] }
  }
  if (-not $line) {
    $hit = @($clean | Where-Object { $_ -match '\S' } | Select-Object -Last 1)
    if ($hit.Count -gt 0) { $line = $hit[0] }
  }
  if (-not $line) { $line = "exit $Code" }
  $line = $line.TrimStart()
  if ($line.Length -gt 300) { $line = $line.Substring(0, 300) + ' ... (see log)' }
  return $line
}

function Step {
  param([Parameter(Mandatory = $true)][string]$Name, [Parameter(Mandatory = $true)][scriptblock]$Body, [switch]$Slow)
  if ($Slow -and $FastMode) {
    Write-Output "SKIP ${Name}: --fast"; Write-Log "--- ${Name}: skipped (--fast)"
    $script:skipped++; return
  }
  $script:StepCode = $null
  $global:LASTEXITCODE = 0
  $lines = @(); $done = $false
  try {
    $lines = @(& $Body 2>&1 | ForEach-Object { "$_" })
    if ($null -ne $script:StepCode) { $code = [int]$script:StepCode }
    elseif ($LASTEXITCODE) { $code = [int]$LASTEXITCODE }
    else { $code = 0 }
    $done = $true
  } catch {
    $lines += "ERROR: $($_.Exception.Message)"; $code = 1; $done = $true
  } finally {
    if (-not $done) {   # 'exit' in a step (or in $TestCmd/$LintCmd) ends the whole run: fail closed, never exit 0
      $script:failed++; $script:failedNames += $Name
      $msg = "ERROR ${Name}: the step called exit (or was stopped), so the remaining steps did not run - remove 'exit' (the step's exit code is read from `$LASTEXITCODE)"
      $summary = "guards: FAIL - $($script:ok) ok, $($script:failed) failed ($($script:failedNames -join ', ')), $($script:skipped) skipped; stopped at $Name (log: .claude/guards.log)"
      Write-Output $msg; Write-Output $summary
      Write-Log @("--- $Name (called exit)", $msg, $summary)
      exit 1
    }
  }
  Write-Log (@("--- $Name (exit $code)") + $lines)
  if ($code -eq 0) {
    $note = @($lines | Where-Object { $_ -match '^NOTE: ' } | Select-Object -First 1)
    if ($note.Count -gt 0) { Write-Output "OK $Name ($($note[0].Substring(6)))" } else { Write-Output "OK $Name" }
    $script:ok++
  } elseif ($code -eq 77 -and @($lines | Where-Object { $_ -match '^SKIP: ' }).Count -gt 0) {
    $s = @($lines | Where-Object { $_ -match '^SKIP: ' })[0].Substring(6)
    Write-Output "SKIP ${Name}: $s"
    $script:skipped++
  } else {
    Write-Output ("ERROR ${Name}: " + (Get-Reason $lines $code))
    $script:failed++; $script:failedNames += $Name
  }
}

function Invoke-Configured([string]$VarName) {
  $cmd = Get-Variable -Name $VarName -Scope Script -ValueOnly
  if (-not $cmd) {
    if ($VarName -eq 'TestCmd') {   # an unset test suite must not pass the ledger's test: rows
      $ids = @(Get-GuardedIds 'test')
      if ($ids.Count -gt 0) {
        "ERROR: `$TestCmd not set but $Ledger has test: rows $($ids -join ',') - set `$TestCmd near the top of .claude\guards.ps1 (and TEST_CMD in guards.sh)"
        $script:StepCode = 1; return
      }
    }
    'SKIP: not configured'
    "Reminder: set `$$VarName near the top of .claude\guards.ps1 (and the matching variable in guards.sh)."
    $script:StepCode = 77; return
  }
  & ([scriptblock]::Create($cmd))
}

# ---------------------------------------------------------------- built-in steps
function Test-Binary([string]$FullName) {
  try {
    $fs = [System.IO.File]::OpenRead($FullName)
    try { $buf = New-Object byte[] 8000; $n = $fs.Read($buf, 0, 8000) } finally { $fs.Dispose() }
    return ([Array]::IndexOf($buf, [byte]0, 0, $n) -ge 0)
  } catch { return $true }
}

function Get-ContentFiles([string]$Path, [string[]]$SkipDirs) {
  $item = Get-Item -LiteralPath $Path -Force
  if (-not $item.PSIsContainer) { return $item }
  if ($SkipDirs -contains $item.Name) { return }
  $stack = New-Object System.Collections.Stack
  $stack.Push($item)
  while ($stack.Count -gt 0) {
    $dir = $stack.Pop()
    foreach ($c in @(Get-ChildItem -LiteralPath $dir.FullName -Force -ErrorAction SilentlyContinue)) {
      if ($c.PSIsContainer) { if ($SkipDirs -notcontains $c.Name) { $stack.Push($c) } }
      elseif ($c.Name -ne $Ledger) { $c }
    }
  }
}

function Invoke-ContentLint {
  $ids = @(Get-GuardedIds 'check' 'content-lint')   # rows citing this step must not pass while it is unconfigured
  if (-not (Test-Path -LiteralPath $BannedFile -PathType Leaf)) {
    if ($ids.Count -gt 0) { "ERROR: no $BannedFile but $Ledger has check: content-lint rows $($ids -join ',')"; $script:StepCode = 1; return }
    "SKIP: no $BannedFile"; $script:StepCode = 77; return
  }
  $phrases = @(Get-Content -LiteralPath $BannedFile -Encoding UTF8 | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') })
  if ($phrases.Count -eq 0) {
    if ($ids.Count -gt 0) { "ERROR: no phrases in $BannedFile but $Ledger has check: content-lint rows $($ids -join ',')"; $script:StepCode = 1; return }
    "SKIP: no phrases in $BannedFile yet"; $script:StepCode = 77; return
  }
  $dirs = @()
  foreach ($d in @($ContentDirs -split '\s+' | Where-Object { $_ })) {
    $d = $d.TrimEnd('/', '\')
    if ($d -match '^(\.[\\/])?brand([\\/].*)?$') { "ignored $d (brand/ holds the rules)"; continue }
    if (Test-Path -LiteralPath $d) { $dirs += $d }
  }
  if ($dirs.Count -eq 0) { "SKIP: none of CONTENT_DIRS exist ($ContentDirs)"; $script:StepCode = 77; return }
  "phrases: $($phrases.Count) | scanned: $($dirs -join ' ')"
  $hits = @()
  foreach ($d in $dirs) {
    foreach ($f in @(Get-ContentFiles $d @('brand', '.git', '.claude', 'node_modules'))) {
      if (Test-Binary $f.FullName) { continue }
      $rel = $f.FullName
      if ($rel.StartsWith($rootFull)) { $rel = $rel.Substring($rootFull.Length).TrimStart('\', '/') }
      $rel = $rel -replace '\\', '/'
      foreach ($m in @(Select-String -LiteralPath $f.FullName -Pattern $phrases -SimpleMatch -Encoding UTF8 -ErrorAction SilentlyContinue)) {
        $i = $m.Line.IndexOf($m.Pattern, [StringComparison]::OrdinalIgnoreCase)
        $txt = $m.Pattern
        if ($i -ge 0) { $txt = $m.Line.Substring($i, $m.Pattern.Length) }
        $hits += New-Object PSObject -Property @{ File = $rel; Line = [int]$m.LineNumber; Text = "${rel}:$($m.LineNumber) [$txt]" }
      }
    }
  }
  if ($hits.Count -eq 0) { return }
  $sorted = @($hits | Sort-Object File, Line | ForEach-Object { $_.Text })
  $shown = ($sorted | Select-Object -First 5) -join '; '
  if ($sorted.Count -gt 5) { $shown += "; +$($sorted.Count - 5) more" }
  "ERROR: $($sorted.Count) banned-phrase hit(s): $shown"
  $sorted
  $script:StepCode = 1
}

function Get-LedgerRows([string[]]$Lines) {
  # Normalised ledger rows; HTML comments and code fences are skipped.
  $inCom = $false; $fence = $false
  foreach ($raw in $Lines) {
    if ($null -eq $raw) { continue }
    $l = $raw -replace "`r$", ''
    if ($inCom) { if ($l.Contains('-->')) { $inCom = $false }; continue }
    if ($l -match '^\s*(```|~~~)') { $fence = -not $fence; continue }
    if ($fence) { continue }
    $i = $l.IndexOf('<!--')
    if ($i -ge 0) { if ($l.IndexOf('-->', $i) -lt 0) { $inCom = $true }; continue }
    if ($l -match '^\s*\|\s*R-[0-9]+\s*\|') {
      $n = (($l -replace '\s+', ' ') -replace ' ?\| ?', '|')
      if ($n.StartsWith(' ')) { $n = $n.Substring(1) }
      if ($n.EndsWith(' ')) { $n = $n.Substring(0, $n.Length - 1) }
      $n
    }
  }
}

function Test-StepDefined([string]$File, [string]$Name) {
  $n = [regex]::Escape($Name)
  if ($File -like '*.ps1') {
    return [bool](Select-String -LiteralPath $File -Pattern "^\s*Step\s+(-Name\s+)?['""]?$n['""]?(\s|$)" -Quiet)
  }
  return [bool](Select-String -LiteralPath $File -Pattern "^\s*step\s+['""]?$n['""]?(\s|$)" -CaseSensitive -Quiet)
}

function Get-GuardedIds([string]$Kind, [string]$Value = '') {
  # IDs of live (non-retired) ledger rows whose guard is <Kind>: - and, when given, exactly <Kind>: <Value>.
  if (-not (Test-Path -LiteralPath $Ledger -PathType Leaf)) { return }
  foreach ($row in @(Get-LedgerRows @(Get-Content -LiteralPath $Ledger -Encoding UTF8))) {
    $cells = @(($row -replace '\\\|', '%PIPE%') -split '\|')
    if ($cells.Count -lt 4) { continue }
    if (($cells[3] -replace '^[ _*~`]*', '') -match '^retired:') { continue }
    if ($cells[$cells.Count - 1] -eq '') { $g = $cells[$cells.Count - 3] } else { $g = $cells[$cells.Count - 2] }
    $g = $g.Replace('`', '').Trim()
    $ci = $g.IndexOf(':')
    if ($ci -lt 0) { continue }
    if ($g.Substring(0, $ci).Trim().ToLowerInvariant() -ne $Kind) { continue }
    if ($Value -and $g.Substring($ci + 1).Trim() -ne $Value) { continue }
    $cells[1].Trim()
  }
}

function Get-BaseRefs {
  # Append-only bases: GUARD_BASE_REF when set; otherwise HEAD plus, when the branch has an upstream,
  # its fork point (merge-base with @{u}) - a row deleted in an unpushed commit is caught too.
  if ($env:GUARD_BASE_REF) { return New-Object PSObject -Property @{ Ref = $env:GUARD_BASE_REF; Label = $env:GUARD_BASE_REF } }
  New-Object PSObject -Property @{ Ref = 'HEAD'; Label = 'HEAD' }
  $up = Invoke-GitText @('rev-parse', '--abbrev-ref', '--symbolic-full-name', '@{u}') $rootFull
  if ($up.Code -ne 0 -or -not $up.Out.Trim()) { return }
  $mb = Invoke-GitText @('merge-base', 'HEAD', '@{u}') $rootFull
  if ($mb.Code -ne 0 -or -not $mb.Out.Trim()) { return }
  $head = Invoke-GitText @('rev-parse', '--verify', '--quiet', 'HEAD') $rootFull
  $sha = $mb.Out.Trim()
  if ($sha -eq $head.Out.Trim()) { return }
  New-Object PSObject -Property @{ Ref = $sha; Label = "upstream $($up.Out.Trim()) fork point $($sha.Substring(0, [Math]::Min(7, $sha.Length)))" }
}

function Invoke-LedgerIntegrity {
  if (-not (Test-Path -LiteralPath $Ledger -PathType Leaf)) {
    # A ledger that existed at a base ref must not vanish.
    if ($env:ALLOW_GUARD_CHANGE -ne '1' -and (Get-Command git -ErrorAction SilentlyContinue)) {
      foreach ($b in @(Get-BaseRefs)) {
        & git cat-file -e "$($b.Ref):./$Ledger" 2>$null
        if ($LASTEXITCODE -eq 0) { "ERROR: $Ledger was deleted since $($b.Label) (owner OK = ALLOW_GUARD_CHANGE=1)"; $script:StepCode = 1; return }
      }
    }
    "SKIP: no $Ledger"; $script:StepCode = 77; return
  }
  $rows =@(Get-LedgerRows @(Get-Content -LiteralPath $Ledger -Encoding UTF8))
  $problems = New-Object System.Collections.Generic.List[string]

  $dups = @($rows | ForEach-Object { ($_ -split '\|')[1] } | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
  if ($dups.Count -gt 0) { $problems.Add('duplicate ID(s) ' + ($dups -join ',')) }

  foreach ($row in $rows) {
    $cells = @(($row -replace '\\\|', '%PIPE%') -split '\|')
    $id = $cells[1]
    $rule = $cells[3]
    if ($cells[$cells.Count - 1] -eq '') { $g = $cells[$cells.Count - 3] } else { $g = $cells[$cells.Count - 2] }
    $g = $g.Replace('`', '').Trim()
    if (($rule -replace '^[ _*~`]*', '') -match '^retired:') { continue }
    $ci = $g.IndexOf(':')
    if ($ci -lt 0) { $problems.Add("${id}: guard must start with test:, check: or review:"); continue }
    $kind = $g.Substring(0, $ci).Trim().ToLowerInvariant()
    $val = $g.Substring($ci + 1).Trim()
    if ($kind -eq 'test') {
      if ($val -notmatch '::') { $problems.Add("${id}: test guard needs <path>::<name>"); continue }
      $path = ($val.Substring(0, $val.IndexOf('::')).Trim()) -replace '^\./', ''
      $name = ($val.Substring($val.LastIndexOf('::') + 2) -replace '\[.*$', '').Trim()
      if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { $problems.Add("${id}: test file $path not found") }
      elseif (-not $name -or -not [bool](Select-String -LiteralPath $path -Pattern $name -SimpleMatch -CaseSensitive -Quiet)) {
        $problems.Add("${id}: test $name not found in $path")
      }
    } elseif ($kind -eq 'check') {
      if ($val -notmatch '^[A-Za-z0-9._-]+$') { $problems.Add("${id}: bad check step name '$val'") }
      elseif (-not (Test-StepDefined $Self $val)) { $problems.Add("${id}: check step $val missing in .claude/guards.ps1") }
      elseif ((Test-Path -LiteralPath $Twin) -and -not (Test-StepDefined $Twin $val)) {
        $problems.Add("${id}: check step $val missing in .claude/guards.sh (keep runners in sync)")
      }
    } elseif ($kind -eq 'review') {
      if (-not $val) { $problems.Add("${id}: review guard needs an observable outcome") }
    } else {
      $problems.Add("${id}: unknown guard type '$kind' (use test:, check: or review:)")
    }
  }

  if ($env:ALLOW_GUARD_CHANGE -eq '1') {
    'NOTE: append-only check bypassed by ALLOW_GUARD_CHANGE=1'
  } elseif ((Invoke-GitText @('rev-parse', '--is-inside-work-tree') $rootFull).Code -ne 0) {
    'append-only check skipped: git not found or not a git work tree'
  } else {
    $cur = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($r in $rows) { [void]$cur.Add($r) }
    foreach ($b in @(Get-BaseRefs)) {   # every base: HEAD (+ upstream fork point), or GUARD_BASE_REF
      $ref = $b.Ref
      if ((Invoke-GitText @('rev-parse', '--verify', '--quiet', "$ref^{commit}") $rootFull).Code -ne 0) {
        if ($env:GUARD_BASE_REF) { $problems.Add("GUARD_BASE_REF $ref not found (CI: checkout with fetch-depth: 0 - after a force push the old tip may be missing)") }
        else { 'append-only check skipped: no commit yet' }
        continue
      }
      $old = Invoke-GitText @('show', "${ref}:./$Ledger") $rootFull
      if ($old.Code -ne 0) { "append-only check skipped: $Ledger not in $($b.Label)"; continue }
      "append-only vs $($b.Label)"
      $missing = @()
      foreach ($r in @(Get-LedgerRows ($old.Out -split "`n"))) {
        if (-not $cur.Contains($r)) { $missing += ($r -split '\|')[1] }
      }
      if ($missing.Count -gt 0) {
        $problems.Add('row(s) ' + ($missing -join ',') + " removed or edited since $($b.Label) (ledger is append-only, owner OK = ALLOW_GUARD_CHANGE=1)")
      }
    }
  }

  "rows: $($rows.Count)"
  if ($problems.Count -eq 0) { return }
  "ERROR: $($problems.Count) ledger problem(s): " + ($problems -join '; ')
  $problems
  $script:StepCode = 1
}

# ---------------------------------------------------------------- steps (order = output order)
Step 'ledger-integrity' { Invoke-LedgerIntegrity }
Step 'content-lint' { Invoke-ContentLint }
Step 'lint' { Invoke-Configured 'LintCmd' }

# ---- project check: steps. Uncomment/adapt, add the same step to guards.sh, and reference it
# ---- in REGRESSIONS.md as "check: <name>".
# function Test-MysqlBinlogExpiry {   # R-00x ops/mysql: binlogs expire after 1 day
#   $f = 'infra/mysql/my.cnf'
#   if (-not (Test-Path -LiteralPath $f)) { "ERROR: $f not found"; $script:StepCode = 1; return }
#   if (-not (Select-String -LiteralPath $f -Pattern '^\s*binlog[_-]expire[_-]logs[_-]seconds\s*=\s*86400\s*$' -Quiet)) {
#     "ERROR: $f must set binlog_expire_logs_seconds=86400 (1 day)"; $script:StepCode = 1
#   }
# }
# Step 'mysql-binlog-expiry' { Test-MysqlBinlogExpiry }
#
# function Test-WorkerTopology {      # R-00x ops/workers: 6 stream workers + 1 queue worker
#   $f = 'infra/supervisor/workers.conf'
#   $s = @(Select-String -LiteralPath $f -Pattern '^\[program:stream-').Count
#   $q = @(Select-String -LiteralPath $f -Pattern '^\[program:queue-').Count
#   if ($s -ne 6 -or $q -ne 1) { "ERROR: $f has $s stream / $q queue workers, want 6 / 1"; $script:StepCode = 1 }
# }
# Step 'worker-topology' { Test-WorkerTopology }

Step 'tests' -Slow { Invoke-Configured 'TestCmd' }

# ---------------------------------------------------------------- summary
$total = $script:ok + $script:failed + $script:skipped
if ($script:failed -eq 0) {
  $summary = "guards: PASS - $($script:ok) ok, 0 failed, $($script:skipped) skipped of $total"
} else {
  $summary = "guards: FAIL - $($script:ok) ok, $($script:failed) failed ($($script:failedNames -join ', ')), $($script:skipped) skipped of $total"
}
if ($FastMode) { $summary += ' [--fast: not valid for done]' }
$summary += ' (log: .claude/guards.log)'
Write-Output $summary
Write-Log $summary
if ($script:failed -gt 0) { exit 1 }
exit 0
