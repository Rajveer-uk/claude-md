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
#         ALLOW_GUARD_CHANGE  1 = skip the append-only check. Owner's explicit OK only. Also lets
#                             spec-integrity accept removed features.json entries and edited description/verify.
#         CONTENT_DIRS        override the content-lint folder list below
#         STUB_SCAN           0 = skip no-stubs (owner opt-out; shows as SKIP in the summary)
#
# Built-in steps: ledger-integrity, content-lint, lint, tests (slow), plus
#   no-stubs        lines added since the base refs (and untracked files) carry no TODO/FIXME/XXX/HACK
#                   without a ticket ref - TODO(#123) or TODO(ABC-12) - no not-implemented marker, elision
#                   comment ("... rest of code unchanged"), stub/placeholder comment, newly skipped test or
#                   conflict marker. A line with "stub-ok: <reason>" is exempt. Docs, brand/, .claude/ skipped.
#   spec-integrity  specs/*.md and SPEC.md: an AC row marked met needs Evidence and its test: paths must
#                   exist (open rows never fail). specs/*.features.json (+ a root features.json): valid JSON,
#                   passes: true needs evidence, no entry removed and description/verify unchanged vs the
#                   base refs.
#
# Add a check: step for any invariant a test can't cover (config, ops, content rules):
#   Step '<name>' [-Slow] { <commands> }   native exit code 0 = OK, other = ERROR. From PowerShell
#       code, output "ERROR: <reason>" and set $script:StepCode = 1 (never call exit inside a step);
#       "SKIP: <reason>" + $script:StepCode = 77 = SKIP.
# Reference it in REGRESSIONS.md as "check: <name>". Steps read files in this repo only - no
# network, no secrets, no production hosts. Needs PowerShell 5+; git is optional (no-stubs skips
# without it).
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

# Paths no-stubs never scans (git pathspec globs; * also matches /). Docs and the ledger are prose,
# brand/ and .claude/ hold the rules; vendored, built, lock and minified files aren't hand-written.
# Keep in sync with STUB_SKIP_PATHS in guards.sh.
$StubSkipPaths = '*.md *.mdx *.rst *.txt REGRESSIONS.md brand/* .claude/*
  vendor/* */vendor/* node_modules/* */node_modules/* dist/* */dist/* build/* */build/*
  *.lock package-lock.json */package-lock.json npm-shrinkwrap.json */npm-shrinkwrap.json
  pnpm-lock.yaml */pnpm-lock.yaml go.sum */go.sum *.min.js *.min.css'

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
if ($Help) { Get-Content -LiteralPath $Self | Select-Object -Skip 1 -First 35; exit 0 }

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

# no-stubs patterns - keep them identical in meaning to STUB_* in guards.sh (\s = [[:space:]] there).
# Case-sensitive (-cmatch): (1) TODO/FIXME/XXX/HACK markers ($StubTicket refs are removed first, so
# TODO(#123) and TODO(ABC-12) pass), (2) not-implemented markers, (5) newly skipped tests, (6) conflict
# markers. Case-insensitive (-match): (3) LLM elision comments, (4) stub / placeholder comments.
$StubTicket = '(TODO|FIXME|XXX|HACK)\((#?[0-9]+|[A-Z][A-Z0-9]+-[0-9]+)\)'
$StubCase = '(^|[^A-Za-z0-9_])(TODO|FIXME|XXX|HACK)([^A-Za-z0-9_]|$)' +
  '|NotImplemented(Error|Exception)|[Nn]ot[ _-][Ii]mplemented|notImplemented|unimplemented!\(|todo!\(' +
  '|(^|[^A-Za-z0-9_])(it|test|describe|context)\.(skip|todo)\(|(^|[^A-Za-z0-9_])x(it|test|describe)\(' +
  '|@pytest\.mark\.skip|@unittest\.skip|(^|[^A-Za-z0-9_])t\.Skip(Now)?\(|#\[ignore\]|markTestSkipped\(' +
  '|@(Disabled|Ignore)([^A-Za-z0-9_]|$)|^(<<<<<<<|>>>>>>>)( |$)'
$StubNoCase = '(^|[\s{])(//|#|--|/\*)\s*(\.\.\.|\u2026)\s*(rest|remaining|existing|same|other)\s.*(code|unchanged|implementation)' +
  '|(^|[\s{])(//|#|--|/\*|<!--)\s*(stub|placeholder|dummy implementation)([^A-Za-z0-9_]|$)'
$StubOk = 'stub-ok:\s*\S'

function Invoke-NoStubs {
  # Stub markers in lines added since the base refs, plus every line of untracked files.
  if ($env:STUB_SCAN -eq '0') { 'SKIP: STUB_SCAN=0 (owner opt-out)'; $script:StepCode = 77; return }
  if ((Invoke-GitText @('rev-parse', '--is-inside-work-tree') $rootFull).Code -ne 0) {
    'SKIP: git not found or not a git work tree'; $script:StepCode = 77; return
  }
  $ord = [StringComparison]::Ordinal
  $excl = @($StubSkipPaths -split '\s+' | Where-Object { $_ } | ForEach-Object { ":(exclude)$_" })
  $recs = New-Object System.Collections.Generic.List[string]   # "<path>:<line><TAB><text>" per added line
  $bases = 0
  foreach ($b in @(Get-BaseRefs)) {   # every base: HEAD (+ upstream fork point), or GUARD_BASE_REF
    $ref = $b.Ref
    if ((Invoke-GitText @('rev-parse', '--verify', '--quiet', "$ref^{commit}") $rootFull).Code -ne 0) {
      if ($env:GUARD_BASE_REF) { "ERROR: GUARD_BASE_REF $ref not found (CI: checkout with fetch-depth: 0)"; $script:StepCode = 1; return }
      continue
    }
    $bases++
    "added lines vs $($b.Label)"
    $d = Invoke-GitText (@('-c', 'core.quotepath=off', 'diff', '-U0', '--no-color', '--no-ext-diff', '-M', '--src-prefix=a/', '--dst-prefix=b/', $ref, '--', '.') + $excl) $rootFull
    $hdr = $false; $f = ''; $n = 0
    foreach ($l in ($d.Out -split "`n")) {
      if ($l.StartsWith('diff --git ', $ord)) { $hdr = $true; continue }
      if ($hdr -and $l.StartsWith('+++ ', $ord)) { $f = $l.Substring(4) -replace '^b/', ''; continue }
      if ($l.StartsWith('@@ ', $ord)) { $hdr = $false; $n = 0; if ($l -match '^@@ -[0-9,]+ \+([0-9]+)') { $n = [int]$Matches[1] }; continue }
      if ($hdr) { continue }
      if ($l.StartsWith('+', $ord)) { $recs.Add("${f}:$n`t" + ($l.Substring(1) -replace "`r$", '')); $n++ }
    }
  }
  if ($bases -eq 0) { 'SKIP: no commit yet'; $script:StepCode = 77; return }
  $u = Invoke-GitText (@('-c', 'core.quotepath=off', 'ls-files', '-o', '--exclude-standard', '--', '.') + $excl) $rootFull
  $untracked = 0
  foreach ($f in @($u.Out -split "`n" | ForEach-Object { $_ -replace "`r$", '' } | Where-Object { $_ })) {
    $untracked++
    $full = Join-Path $rootFull $f
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { continue }
    if ((Get-Item -LiteralPath $full -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
    if (Test-Binary $full) { continue }
    $i = 0
    foreach ($l in @(Get-Content -LiteralPath $full -Encoding UTF8)) { $i++; $recs.Add("${f}:$i`t$l") }
  }
  "untracked files: $untracked"
  $seen = New-Object 'System.Collections.Generic.HashSet[string]'
  $hits = New-Object System.Collections.Generic.List[string]
  foreach ($r in $recs) {
    if (-not $seen.Add($r)) { continue }
    $tab = $r.IndexOf("`t", $ord)
    $t = $r.Substring($tab + 1)
    $s = $t -creplace $StubTicket, ' '
    if (($s -cmatch $StubCase -or $s -match $StubNoCase) -and $s -cnotmatch $StubOk) {
      $h = $r.Substring(0, $tab) + ': ' + $t.TrimStart(' ', "`t")
      if ($h.Length -gt 160) { $h = $h.Substring(0, 160) }
      $hits.Add($h)
    }
  }
  if ($hits.Count -eq 0) { return }
  $shown = @($hits | Select-Object -First 10) -join '; '
  if ($hits.Count -gt 10) { $shown += "; +$($hits.Count - 10) more" }
  "ERROR: $($hits.Count) stub marker(s) added (finish it, cite a ticket as TODO(#123), or add `"stub-ok: <reason>`" to the line): $shown"
  $hits | Select-Object -First 10
  $script:StepCode = 1
}

function Get-SpecCell($Cells, [int]$I) { if ($I -ge 1 -and $I -lt $Cells.Count) { return [string]$Cells[$I] }; return '' }
function Get-SpecNorm([string]$S) { return ($S -replace '[`*_]', '').Trim().ToLowerInvariant() }

function Get-JsonProp($Obj, [string]$Name) {
  # A parsed JSON object's property value (arrays come back whole), or $null. Names are case-sensitive.
  if ($Obj -isnot [System.Management.Automation.PSCustomObject]) { return $null }
  $p = $Obj.PSObject.Properties[$Name]
  if ($null -eq $p -or $p.Name -cne $Name) { return $null }
  return ,$p.Value
}

function ConvertFrom-FeatureJson([string]$Text) {
  $t = $Text.TrimStart([char]0xFEFF)
  if (-not $t.Trim()) { throw 'empty file' }
  return ,($t | ConvertFrom-Json -ErrorAction Stop)
}

function Get-FeatureList($Doc) {
  $fl = Get-JsonProp $Doc 'features'
  if ($null -ne $fl -and $fl -is [array]) { return ,$fl }
  return $null
}

function Get-FeatureIds($List) {
  $h = New-Object System.Collections.Specialized.OrderedDictionary
  foreach ($e in $List) {
    $id = Get-JsonProp $e 'id'
    if ($id -is [string] -and $id.Trim()) { $h[$id] = $e }
  }
  return ,$h
}

function Get-JsonText($V) {
  if ($null -eq $V) { return '' }
  if ($V -is [string]) { return $V }
  return [string](ConvertTo-Json -InputObject $V -Compress -Depth 10)
}

function Invoke-SpecIntegrity {
  # specs/*.md + SPEC.md Requirements rows; specs/*.features.json (+ a root features.json).
  $problems = New-Object System.Collections.Generic.List[string]
  $soft = New-Object System.Collections.Generic.List[string]   # changes vs a base ref: a NOTE under ALLOW_GUARD_CHANGE=1
  $ord = [StringComparison]::Ordinal
  $md = @()
  if (Test-Path -LiteralPath 'SPEC.md' -PathType Leaf) { $md += 'SPEC.md' }
  if (Test-Path -LiteralPath 'specs' -PathType Container) {
    $md += @(Get-ChildItem -LiteralPath 'specs' -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -clike '*.md' } | Sort-Object Name | ForEach-Object { 'specs/' + $_.Name })
  }
  # Tables whose header has AC and Status columns. A row whose Status is met (or done) needs a non-empty
  # Evidence cell, and each "test: <path>::<name>" in its Verify or Evidence cell must name an existing file.
  $rows = 0
  foreach ($f in $md) {
    $inCom = $false; $fence = $false; $tbl = 0; $ac = 0; $st = 0; $ev = 0; $vf = 0
    foreach ($raw in @(Get-Content -LiteralPath $f -Encoding UTF8)) {
      $l0 = $raw -replace "`r$", ''
      if ($inCom) { if ($l0.Contains('-->')) { $inCom = $false }; continue }
      if ($l0 -match '^\s*(```|~~~)') { $fence = -not $fence; $tbl = 0; continue }
      if ($fence) { continue }
      $ci = $l0.IndexOf('<!--', $ord)
      if ($ci -ge 0) { if ($l0.IndexOf('-->', $ci, $ord) -lt 0) { $inCom = $true }; continue }
      if ($l0 -notmatch '^\s*\|') { $tbl = 0; continue }
      $l = (($l0 -replace '\\\|', '%PIPE%') -replace '^\s*\|', '') -replace '\|\s*$', ''
      $c = @('') + @($l -split '\|')   # 1-based, like awk
      if ($tbl -eq 0) {
        $ac = 0; $st = 0; $ev = 0; $vf = 0
        for ($i = 1; $i -lt $c.Count; $i++) {
          $h = Get-SpecNorm $c[$i]
          if ($h -ceq 'ac') { $ac = $i } elseif ($h -ceq 'status') { $st = $i } elseif ($h -ceq 'evidence') { $ev = $i } elseif ($h.StartsWith('verify', $ord)) { $vf = $i }
        }
        if ($ac -and $st) { $tbl = 1 } else { $tbl = 2 }
        continue
      }
      if ($tbl -eq 2 -or $l -match '^[-:|\s]+$') { continue }
      $s = Get-SpecNorm (Get-SpecCell $c $st)
      if ($s -cnotmatch '^(met|done)([^a-z]|$)') { continue }
      $id = ((Get-SpecCell $c $ac) -replace '[`*_]', '').Trim()
      if ($s.StartsWith('met', $ord)) { $w = 'met' } else { $w = 'done' }
      $rows++
      $e = Get-SpecCell $c $ev
      if ((($e -replace '[\u2013\u2014]', '') -replace '[-`*_\s]', '') -eq '') { $problems.Add("${f}: $id is $w but its Evidence cell is empty") }
      $x = (Get-SpecCell $c $vf) + ' ' + $e
      $seenPath = New-Object 'System.Collections.Generic.HashSet[string]'
      while ($true) {
        $m = [regex]::Match($x, 'test:\s*[^\s`|:]+::')
        if (-not $m.Success) { break }
        $bc = ' '
        if ($m.Index -gt 0) { $bc = $x.Substring($m.Index - 1, 1) }
        $p = $m.Value; $x = $x.Substring($m.Index + $m.Length)
        if ($bc -cmatch '[A-Za-z0-9_]') { continue }
        $p = (($p -replace '^test:\s*', '') -replace '::$', '') -replace '^\./', ''
        if (-not $seenPath.Add($p)) { continue }
        $exists = $false
        try { $exists = Test-Path -LiteralPath $p -PathType Leaf } catch { $exists = $false }
        if (-not $exists) { $problems.Add("${f}: $id is $w but test file $p not found") }
      }
    }
  }

  # Feature lists: valid JSON, unique ids, passes: true needs evidence; vs every base ref no entry removed
  # and description/verify unchanged.
  $cur = @{}
  $jpaths = @()
  if (Test-Path -LiteralPath 'specs' -PathType Container) {
    $jpaths += @(Get-ChildItem -LiteralPath 'specs' -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -clike '*.features.json' } | Sort-Object Name | ForEach-Object { 'specs/' + $_.Name })
  }
  if (Test-Path -LiteralPath 'features.json' -PathType Leaf) { $jpaths += 'features.json' }
  $feats = 0
  foreach ($p in $jpaths) {
    try {
      $d = ConvertFrom-FeatureJson ([string](Get-Content -LiteralPath $p -Raw -Encoding UTF8 -ErrorAction Stop))
    } catch { $problems.Add("${p}: not valid JSON ($($_.Exception.Message))"); $cur[$p] = $null; continue }
    $fl = Get-FeatureList $d
    if ($null -eq $fl) {
      if ($p -eq 'features.json') {
        "$p has no `"features`" list - not a feature file, skipped"
        $cur[$p] = New-Object System.Collections.Specialized.OrderedDictionary; continue
      }
      $problems.Add("${p}: needs a `"features`" list"); $cur[$p] = $null; continue
    }
    $feats++
    $seen = New-Object 'System.Collections.Generic.HashSet[string]'
    $i = 0
    foreach ($e in $fl) {
      $i++
      $fid = Get-JsonProp $e 'id'
      if (-not ($fid -is [string] -and $fid.Trim())) { $problems.Add("${p}: feature $i has no `"id`""); continue }
      if (-not $seen.Add($fid)) { $problems.Add("${p}: duplicate id $fid") }
      $pass = Get-JsonProp $e 'passes'
      $evi = Get-JsonProp $e 'evidence'
      if ($null -ne $pass -and $pass -isnot [bool]) { $problems.Add("${p}: $fid `"passes`" must be true or false") }
      elseif ($pass -is [bool] -and $pass -and -not (($evi -is [string] -and $evi.Trim()) -or $evi -is [datetime])) {
        $problems.Add("${p}: $fid has `"passes`": true but no `"evidence`"")
      }
    }
    $cur[$p] = Get-FeatureIds $fl
  }
  $badRef = ''
  if ((Invoke-GitText @('rev-parse', '--is-inside-work-tree') $rootFull).Code -eq 0) {
    foreach ($b in @(Get-BaseRefs)) {
      $ref = $b.Ref
      if ((Invoke-GitText @('rev-parse', '--verify', '--quiet', "$ref^{commit}") $rootFull).Code -ne 0) {
        if ($env:GUARD_BASE_REF) { $badRef = $ref }
        continue
      }
      $ls = Invoke-GitText @('ls-tree', '-r', '--name-only', $ref, '--', 'specs', 'features.json') $rootFull
      foreach ($bp in @($ls.Out -split "`n" | Where-Object { $_ -cmatch '^(specs/[^/]+\.features\.json|features\.json)$' })) {
        $old = $null
        $sh = Invoke-GitText @('show', "${ref}:$bp") $rootFull
        if ($sh.Code -eq 0) { try { $old = Get-FeatureList (ConvertFrom-FeatureJson $sh.Out) } catch { $old = $null } }
        if ($null -eq $old) { continue }
        if (-not $cur.ContainsKey($bp)) { $soft.Add("$bp deleted since $($b.Label)"); continue }
        $now = $cur[$bp]
        if ($null -eq $now) { continue }
        $was = Get-FeatureIds $old
        foreach ($fid in @($was.Keys)) {
          if (-not $now.Contains($fid)) { $soft.Add("${bp}: $fid removed since $($b.Label)"); continue }
          foreach ($k in @('description', 'verify')) {
            if ((Get-JsonText (Get-JsonProp $was[$fid] $k)) -cne (Get-JsonText (Get-JsonProp $now[$fid] $k))) {
              $soft.Add("${bp}: $fid `"$k`" changed since $($b.Label)")
            }
          }
        }
      }
    }
  }
  if ($badRef -and $feats -gt 0) { $problems.Add("GUARD_BASE_REF $badRef not found (CI: checkout with fetch-depth: 0)") }

  if ($md.Count -eq 0 -and $feats -eq 0 -and $problems.Count -eq 0 -and $soft.Count -eq 0) {
    'SKIP: no specs (specs/*.md, SPEC.md or *.features.json)'; $script:StepCode = 77; return
  }
  "spec files: $($md.Count), met AC rows: $rows, feature files: $feats"
  $note = ''
  if ($soft.Count -gt 0) {
    $soft
    if ($env:ALLOW_GUARD_CHANGE -eq '1') { $note = "ALLOW_GUARD_CHANGE=1 approved $($soft.Count) features.json change(s), listed in .claude/guards.log" }
    else { foreach ($s in @($soft)) { $problems.Add("$s (owner OK = ALLOW_GUARD_CHANGE=1)") } }
  }
  if ($problems.Count -gt 0) {
    "ERROR: $($problems.Count) spec problem(s): " + ($problems -join '; ')
    $problems
    $script:StepCode = 1; return
  }
  if ($note) { "NOTE: $note" }
}

# ---------------------------------------------------------------- steps (order = output order)
Step 'ledger-integrity' { Invoke-LedgerIntegrity }
Step 'content-lint' { Invoke-ContentLint }
Step 'lint' { Invoke-Configured 'LintCmd' }
Step 'no-stubs' { Invoke-NoStubs }
Step 'spec-integrity' { Invoke-SpecIntegrity }

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
