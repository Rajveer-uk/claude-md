#requires -Version 5
# install-user-config.ps1 - install the claude-md user layer into ~/.claude (%USERPROFILE%\.claude) in one
# command: the security baseline (merged, never overwritten), the global working agreement (CLAUDE.md), the
# plugin packs, and optionally the guard / plan-gate / review-gate hooks. Windows twin of scripts/install-user-config.sh -
# same steps, same output lines, same exit codes; runs on Windows PowerShell 5.1 and PowerShell 7.
#
# Usage (from anywhere):
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\install-user-config.ps1
#       local: base pack, Plan default
#   ... install-user-config.ps1 -Packs base,council     more packs (base marketing council ecc)
#   ... install-user-config.ps1 -Hooks guard,plan-gate,review-gate  also install + register these hooks (.ps1, exec form)
#   ... install-user-config.ps1 -Cloud                  cloud preset: no Plan default, only the review-gate hook,
#                                                       marketplace = this clone (pinned ref)
# Options: -Dest <dir> (default %USERPROFILE%\.claude, else $HOME\.claude) ; -Marketplace <owner/repo | path>
#          (default: this repo's GitHub origin, else this folder) ; -Files (copy agents/skills/commands
#          instead of installing plugins; used automatically when the claude CLI is missing) ;
#          -ReplaceClaudeMd (replace a CLAUDE.md that isn't ours, after a backup) ; -Help
#
# Safety: settings.json is merged - deny/ask entries are only ever added, every other key and hook is
# kept (key order too), a timestamped backup is written before any change, and an unparseable or
# non-object file is left untouched (exit 1). It is read and written by a strict JSON reader/writer in
# this script (not ConvertFrom-Json/ConvertTo-Json, whose 5.1/7 quirks unwrap arrays, rewrite escapes and
# dates and accept comments), UTF-8 without BOM, via a temp file that must parse before it replaces the
# original. An existing CLAUDE.md from an older claude-md release is backed up and replaced; any other
# CLAUDE.md is kept and the new one is written next to it as CLAUDE.md.claude-md-new. Hooks are
# registered as {"command": "powershell.exe", "args": [..., "-File", "<dest>/hooks/<name>.ps1"]}, never
# twice (a guard.ps1 or guard.sh already registered counts). No network except the claude CLI fetching
# a GitHub marketplace; nothing outside -Dest is written.
# Needs: Windows PowerShell 5.1 or PowerShell 7 (no modules). Optional: the claude CLI (plugins), git
# (to read the GitHub origin).
# Exit: 0 installed (warnings possible) ; 1 a step failed ; 2 usage error.
[CmdletBinding(PositionalBinding = $false)]
param(
  [string[]]$Packs = @('base'),
  [string[]]$Hooks = @(),
  [switch]$Cloud,
  [switch]$Files,
  [string]$Dest = '',
  [string]$Marketplace = '',
  [switch]$ReplaceClaudeMd,
  [Alias('h')][switch]$Help,
  [Parameter(ValueFromRemainingArguments = $true)][string[]]$Rest
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$usage = 'usage: powershell -NoProfile -ExecutionPolicy Bypass -File scripts\install-user-config.ps1 [-Packs a,b] [-Hooks guard,plan-gate,review-gate] [-Cloud] [-Files] [-Dest dir] [-Marketplace src] [-ReplaceClaudeMd]'
$extra = @($Rest | Where-Object { $null -ne $_ })

if ($Help -or @($extra | Where-Object { @('--help', '-h', '-?', '/?') -contains $_ }).Count -gt 0) {
  foreach ($l in @(Get-Content -LiteralPath $PSCommandPath | Select-Object -Skip 1)) {
    if ($l -notmatch '^#') { break }
    $l -replace '^# ?', ''
  }
  exit 0
}
if ($extra.Count -gt 0) { [Console]::Error.WriteLine($usage); exit 2 }

$packList = @((($Packs -join ',') -split '[,\s]+') | Where-Object { $_ })
$hookList = @((($Hooks -join ',') -split '[,\s]+') | Where-Object { $_ })
foreach ($p in $packList) {
  if (@('base', 'marketing', 'council', 'ecc') -cnotcontains $p) {
    [Console]::Error.WriteLine("unknown pack: $p (base marketing council ecc)"); exit 2
  }
}
foreach ($h in $hookList) {
  if (@('guard', 'plan-gate', 'review-gate') -cnotcontains $h) {
    [Console]::Error.WriteLine("unknown hook: $h (guard plan-gate review-gate; format/verify run project code - register them by hand, see setup.md)"); exit 2
  }
}

$script:rc = 0
function Out-Ok([string]$m) { Write-Output "OK   $m" }
function Out-Note([string]$m) { Write-Output "NOTE $m" }
function Out-Warn([string]$m) { Write-Output "WARN $m" }
function Out-Fail([string]$m) { Write-Output "ERROR $m"; $script:rc = 1 }

if ($Cloud -and $hookList.Count -gt 0) {   # cloud: only review-gate (runs no project code, needs no allowlist)
  foreach ($h in $hookList) { if ($h -cne 'review-gate') { Out-Warn "-Hooks $h is ignored with -Cloud" } }
  $hookList = @($hookList | Where-Object { $_ -ceq 'review-gate' })
}

$onWindows = ($PSVersionTable.PSEdition -ne 'Core') -or ((Get-Variable IsWindows -ValueOnly -ErrorAction SilentlyContinue) -eq $true)
$homeDir = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
$cliHome = [IO.Path]::Combine($homeDir, '.claude')
if (-not $Dest) { $Dest = $cliHome }
$Dest = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Dest)   # .NET calls need a full path

if (-not (Test-Path -LiteralPath ([IO.Path]::Combine($repo, '.claude', 'settings.json')) -PathType Leaf) -or
    -not (Test-Path -LiteralPath ([IO.Path]::Combine($repo, 'global', 'CLAUDE.md')) -PathType Leaf)) {
  Write-Output "ERROR $repo is not a claude-md checkout"; exit 1
}
try { [void][IO.Directory]::CreateDirectory($Dest) } catch { Write-Output "ERROR cannot create $Dest"; exit 1 }
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'

function Get-Msg($err) { return $err.Exception.Message }

# ---- strict JSON (RFC 8259, like Python's json module): objects -> case-sensitive OrderedDictionary (key
# order kept), arrays -> ArrayList (a one-element array stays an array), numbers kept as their source text.
$script:rxWs = [regex]'\G[ \t\n\r]*'
$script:rxNum = [regex]'\G-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?'
$script:rxStr = [regex]'\G"((?:[^"\\\x00-\x1f]|\\(?:["\\/bfnrt]|u[0-9a-fA-F]{4}))*)"'
$script:rxEsc = [regex]'[\x00-\x1f"\\]'

function New-JsonObject { return , (New-Object System.Collections.Specialized.OrderedDictionary) }
function New-JsonArray { return , (New-Object System.Collections.ArrayList) }

function Get-JsonError([string]$msg) {
  $pos = $script:jp
  $before = $script:js.Substring(0, $pos)
  $line = $before.Split([char]10).Count
  $col = $pos - $before.LastIndexOf([char]10)
  return "${msg}: line $line column $col (char $pos)"
}

function Skip-JsonWs { $script:jp += $script:rxWs.Match($script:js, $script:jp).Length }

function Test-JsonLiteral([string]$lit) {
  return ($script:js.Length - $script:jp -ge $lit.Length) -and ($script:js.Substring($script:jp, $lit.Length) -ceq $lit)
}

function Read-JsonString {
  $m = $script:rxStr.Match($script:js, $script:jp)
  if (-not $m.Success) { throw (Get-JsonError 'Invalid string (unterminated, bad escape or control character)') }
  $script:jp += $m.Length
  # rxStr admits only the JSON escapes (\" \\ \/ \b \f \n \r \t \uXXXX); Regex.Unescape maps each to the same character
  return [regex]::Unescape($m.Groups[1].Value)
}

function Read-JsonValue([int]$depth) {
  if ($depth -gt 200) { throw (Get-JsonError 'Nesting too deep') }
  Skip-JsonWs
  if ($script:jp -ge $script:js.Length) { throw (Get-JsonError 'Expecting value') }
  $c = $script:js[$script:jp]
  if ($c -eq [char]'{') {
    $o = New-JsonObject
    $script:jp++
    Skip-JsonWs
    if ($script:jp -lt $script:js.Length -and $script:js[$script:jp] -eq [char]'}') { $script:jp++; return , $o }
    while ($true) {
      Skip-JsonWs
      if ($script:jp -ge $script:js.Length -or $script:js[$script:jp] -ne [char]'"') {
        throw (Get-JsonError 'Expecting property name enclosed in double quotes')
      }
      $k = Read-JsonString
      Skip-JsonWs
      if ($script:jp -ge $script:js.Length -or $script:js[$script:jp] -ne [char]':') { throw (Get-JsonError "Expecting ':' delimiter") }
      $script:jp++
      $o[$k] = (Read-JsonValue ($depth + 1))
      Skip-JsonWs
      if ($script:jp -lt $script:js.Length) {
        $c = $script:js[$script:jp]
        $script:jp++
        if ($c -eq [char]',') { continue }
        if ($c -eq [char]'}') { return , $o }
        $script:jp--
      }
      throw (Get-JsonError "Expecting ',' delimiter")
    }
  }
  if ($c -eq [char]'[') {
    $a = New-JsonArray
    $script:jp++
    Skip-JsonWs
    if ($script:jp -lt $script:js.Length -and $script:js[$script:jp] -eq [char]']') { $script:jp++; return , $a }
    while ($true) {
      [void]$a.Add((Read-JsonValue ($depth + 1)))
      Skip-JsonWs
      if ($script:jp -lt $script:js.Length) {
        $c = $script:js[$script:jp]
        $script:jp++
        if ($c -eq [char]',') { continue }
        if ($c -eq [char]']') { return , $a }
        $script:jp--
      }
      throw (Get-JsonError "Expecting ',' delimiter")
    }
  }
  if ($c -eq [char]'"') { return (Read-JsonString) }
  if (Test-JsonLiteral 'true') { $script:jp += 4; return $true }
  if (Test-JsonLiteral 'false') { $script:jp += 5; return $false }
  if (Test-JsonLiteral 'null') { $script:jp += 4; return $null }
  $m = $script:rxNum.Match($script:js, $script:jp)
  if ($m.Success -and $m.Length -gt 0) { $script:jp += $m.Length; return [pscustomobject]@{ JsonNumber = $m.Value } }
  throw (Get-JsonError 'Expecting value')
}

function ConvertFrom-JsonText([string]$text) {
  $script:js = $text; $script:jp = 0
  $v = Read-JsonValue 0
  Skip-JsonWs
  if ($script:jp -lt $script:js.Length) { throw (Get-JsonError 'Extra data') }
  return , $v
}

function Read-JsonFile([string]$path) {
  $bytes = [IO.File]::ReadAllBytes($path)
  $text = (New-Object System.Text.UTF8Encoding($false, $true)).GetString($bytes)   # invalid UTF-8 throws
  if ($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF) { $text = $text.Substring(1) }
  return , (ConvertFrom-JsonText $text)
}

function ConvertTo-JsonString([string]$s) {
  $e = $script:rxEsc.Replace($s, [System.Text.RegularExpressions.MatchEvaluator] {
      param($m)
      switch ([int][char]$m.Value) {
        34 { return '\"' } 92 { return '\\' } 8 { return '\b' } 12 { return '\f' }
        10 { return '\n' } 13 { return '\r' } 9 { return '\t' }
      }
      return ('\u{0:x4}' -f [int][char]$m.Value)
    })
  return '"' + $e + '"'
}

# Same layout as Python's json.dump(indent=2, ensure_ascii=False).
function Add-JsonText($sb, $v, [string]$ind) {
  if ($null -eq $v) { [void]$sb.Append('null'); return }
  if ($v -is [bool]) { if ($v) { [void]$sb.Append('true') } else { [void]$sb.Append('false') }; return }
  if ($v -is [string]) { [void]$sb.Append((ConvertTo-JsonString $v)); return }
  if ($v -is [System.Collections.IDictionary]) {
    $keys = @($v.get_Keys())
    if ($keys.Count -eq 0) { [void]$sb.Append('{}'); return }
    $in2 = $ind + '  '
    [void]$sb.Append('{')
    for ($i = 0; $i -lt $keys.Count; $i++) {
      if ($i -gt 0) { [void]$sb.Append(',') }
      [void]$sb.Append("`n").Append($in2).Append((ConvertTo-JsonString ([string]$keys[$i]))).Append(': ')
      Add-JsonText $sb $v[$keys[$i]] $in2
    }
    [void]$sb.Append("`n").Append($ind).Append('}')
    return
  }
  if ($v -is [System.Management.Automation.PSCustomObject]) { [void]$sb.Append([string]$v.JsonNumber); return }
  if ($v -is [System.Collections.IList]) {
    if ($v.Count -eq 0) { [void]$sb.Append('[]'); return }
    $in2 = $ind + '  '
    [void]$sb.Append('[')
    for ($i = 0; $i -lt $v.Count; $i++) {
      if ($i -gt 0) { [void]$sb.Append(',') }
      [void]$sb.Append("`n").Append($in2)
      Add-JsonText $sb $v[$i] $in2
    }
    [void]$sb.Append("`n").Append($ind).Append(']')
    return
  }
  if ($v -is [int] -or $v -is [long]) { [void]$sb.Append($v.ToString([Globalization.CultureInfo]::InvariantCulture)); return }
  throw "cannot write a $($v.GetType().FullName) as JSON"
}

function ConvertTo-JsonText($v) {
  $sb = New-Object System.Text.StringBuilder
  Add-JsonText $sb $v ''
  return $sb.ToString()
}

# Temp file + re-parse + replace: the original is only ever swapped for a file that reads back.
function Write-JsonFile([string]$path, $obj) {
  $tmp = $path + '.tmp'
  try {
    [IO.File]::WriteAllText($tmp, (ConvertTo-JsonText $obj) + "`n", (New-Object System.Text.UTF8Encoding($false)))
    $null = Read-JsonFile $tmp
  } catch {
    if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    throw
  }
  if (Test-Path -LiteralPath $path -PathType Leaf) {
    try { [IO.File]::Replace($tmp, $path, [NullString]::Value) } catch { Move-Item -LiteralPath $tmp -Destination $path -Force }
  } else {
    Move-Item -LiteralPath $tmp -Destination $path -Force
  }
}

function Format-PyRepr($v) {
  if ($v -is [string]) { return "'$v'" }
  if ($v -is [bool]) { if ($v) { return 'True' } else { return 'False' } }
  return (ConvertTo-JsonText $v)
}

# ---- 1. security baseline -> settings.json (merge, add-only)
function Invoke-SettingsMerge {
  $src = [IO.Path]::Combine($repo, '.claude', 'settings.json')
  $dst = [IO.Path]::Combine($Dest, 'settings.json')
  try { $base = Read-JsonFile $src } catch { Out-Fail "cannot read the baseline $src ($(Get-Msg $_))"; return }
  $cur = New-JsonObject
  $exists = Test-Path -LiteralPath $dst
  if ($exists) {
    try { $cur = Read-JsonFile $dst } catch {
      Out-Fail "$dst does not parse ($(Get-Msg $_)) - left untouched; fix it, then run again"; return
    }
    if (-not ($cur -is [System.Collections.IDictionary])) { Out-Fail "$dst is not a JSON object - left untouched"; return }
  }
  $before = ConvertTo-JsonText $cur
  if (-not $cur.Contains('$schema')) { $cur['$schema'] = $base['$schema'] }
  if (-not $cur.Contains('permissions')) { $cur['permissions'] = New-JsonObject }
  $perms = $cur['permissions']
  if (-not ($perms -is [System.Collections.IDictionary])) { Out-Fail "${dst}: ""permissions"" is not an object - left untouched"; return }
  $added = @{}
  foreach ($k in @('deny', 'ask')) {
    if (-not $perms.Contains($k)) { $perms[$k] = New-JsonArray }
    $have = $perms[$k]
    if (-not ($have -is [System.Collections.IList])) { Out-Fail "${dst}: permissions.$k is not a list - left untouched"; return }
    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($r in $have) { if ($r -is [string]) { [void]$seen.Add($r) } }
    $new = New-JsonArray
    $want = $base['permissions'][$k]
    if ($want -is [System.Collections.IList]) {
      foreach ($r in $want) { if (-not ($r -is [string] -and $seen.Contains($r))) { [void]$new.Add($r) } }
    }
    foreach ($r in $new) { [void]$have.Add($r) }
    $added[$k] = $new.Count
  }
  $perms['disableBypassPermissionsMode'] = 'disable'
  $cur['useAutoModeDuringPlan'] = $false
  $notes = @()
  $pinned = 0
  $pinsPath = [IO.Path]::Combine($repo, 'templates', 'model-pins.json')
  if (Test-Path -LiteralPath $pinsPath) {   # model pins: set only the keys you have not set yourself
    try { $pinsDoc = Read-JsonFile $pinsPath } catch { Out-Fail "cannot read $pinsPath ($(Get-Msg $_))"; return }
    $pins = $pinsDoc['env']
    if ($pins -is [System.Collections.IDictionary] -and $pins.Count -gt 0) {
      if (-not $cur.Contains('env')) { $cur['env'] = New-JsonObject }
      $envObj = $cur['env']
      if (-not ($envObj -is [System.Collections.IDictionary])) { Out-Fail "${dst}: ""env"" is not an object - left untouched"; return }
      foreach ($k in @($pins.Keys)) {
        if (-not $envObj.Contains($k)) { $envObj[$k] = $pins[$k]; $pinned++ }
        elseif (-not ($envObj[$k] -is [string] -and $envObj[$k] -ceq $pins[$k])) {
          $notes += "$k is $(Format-PyRepr $envObj[$k]) (kept); the repo pins $(Format-PyRepr $pins[$k])"
        }
      }
    }
  }
  if (-not $Cloud) {
    $mode = $perms['defaultMode']
    if ($null -eq $mode) {
      $perms['defaultMode'] = 'plan'
    } elseif (-not ($mode -is [string] -and $mode -ceq 'plan')) {
      $notes += "permissions.defaultMode is $(Format-PyRepr $mode) (kept); the baseline default is ""plan"""
    }
  }
  if ((ConvertTo-JsonText $cur) -ceq $before) {
    Out-Ok "settings.json already has the baseline ($dst)"
  } else {
    try {
      if ($exists) { [IO.File]::Copy($dst, "$dst.$stamp.bak", $true) }
      Write-JsonFile $dst $cur
    } catch { Out-Fail "cannot write $dst ($(Get-Msg $_))"; return }
    $plan = if ($Cloud) { '' } else { ', Plan default' }
    $pinText = if ($pinned -gt 0) { ", $pinned model pin(s)" } else { '' }
    Out-Ok "settings.json merged: +$($added['deny']) deny, +$($added['ask']) ask$plan$pinText ($dst)"
  }
  foreach ($n in $notes) { Out-Note $n }
}
$rcBeforeMerge = $script:rc
Invoke-SettingsMerge
$settingsBad = ($script:rc -ne $rcBeforeMerge)

# ---- 2. global working agreement -> CLAUDE.md
function Test-SameFile([string]$a, [string]$b) {
  return [Convert]::ToBase64String([IO.File]::ReadAllBytes($a)) -ceq [Convert]::ToBase64String([IO.File]::ReadAllBytes($b))
}
function Test-OurClaudeMd([string]$path) {
  return [IO.File]::ReadAllText($path) -cmatch '(?m)^# Working agreement \(all projects\)'
}
$md = [IO.Path]::Combine($Dest, 'CLAUDE.md'); $srcMd = [IO.Path]::Combine($repo, 'global', 'CLAUDE.md')
try {
  if (-not (Test-Path -LiteralPath $md)) {
    [IO.File]::Copy($srcMd, $md, $false); Out-Ok "CLAUDE.md installed ($md)"
  } elseif (Test-SameFile $srcMd $md) {
    Out-Ok 'CLAUDE.md already current'
  } elseif ($ReplaceClaudeMd -or (Test-OurClaudeMd $md)) {
    [IO.File]::Copy($md, "$md.$stamp.bak", $true); [IO.File]::Copy($srcMd, $md, $true)
    Out-Ok "CLAUDE.md updated (backup: $md.$stamp.bak)"
  } else {
    [IO.File]::Copy($srcMd, "$md.claude-md-new", $true)
    Out-Warn "$md is your own file - kept; merge $md.claude-md-new into it by hand (or re-run with -ReplaceClaudeMd)"
  }
} catch { Out-Fail "cannot write $md ($(Get-Msg $_))" }

# ---- 3. packs: plugins via the claude CLI, else plain files
# Native calls: stderr dropped, never terminating (Windows PowerShell 5.1 turns redirected stderr into errors).
function Invoke-Native([string]$exe, [string[]]$argv) {
  $ErrorActionPreference = 'Continue'
  $global:LASTEXITCODE = 0
  try { $out = @(& $exe @argv 2>$null); $code = $LASTEXITCODE } catch { $out = @(); $code = 1 }
  if ($null -eq $code) { $code = 0 }
  return [pscustomobject]@{ Code = $code; Out = (@($out | ForEach-Object { [string]$_ }) -join "`n") }
}
function Test-SamePath([string]$a, [string]$b) {
  $x = [IO.Path]::GetFullPath($a).TrimEnd('\', '/'); $y = [IO.Path]::GetFullPath($b).TrimEnd('\', '/')
  if ($onWindows) { return $x -ieq $y }
  return $x -ceq $y
}
function Copy-Tree([string]$src, [string]$dst) {   # like cp -R: merges into an existing folder, overwrites files
  $src = (Get-Item -LiteralPath $src -Force).FullName.TrimEnd('\', '/')
  [void][IO.Directory]::CreateDirectory($dst)
  foreach ($d in @(Get-ChildItem -LiteralPath $src -Recurse -Force -Directory)) {
    [void][IO.Directory]::CreateDirectory([IO.Path]::Combine($dst, $d.FullName.Substring($src.Length + 1)))
  }
  foreach ($f in @(Get-ChildItem -LiteralPath $src -Recurse -Force -File)) {
    [IO.File]::Copy($f.FullName, [IO.Path]::Combine($dst, $f.FullName.Substring($src.Length + 1)), $true)
  }
}
function Copy-PackFiles([string]$p) {
  $pd = [IO.Path]::Combine($repo, 'plugins', $p)
  $ad = [IO.Path]::Combine($pd, 'agents')
  if (Test-Path -LiteralPath $ad -PathType Container) {
    foreach ($f in @(Get-ChildItem -LiteralPath $ad -File | Where-Object { $_.Name -clike '*.md' })) {
      [IO.File]::Copy($f.FullName, [IO.Path]::Combine($Dest, 'agents', $f.Name), $true)
    }
  }
  $sd = [IO.Path]::Combine($pd, 'skills')
  if (Test-Path -LiteralPath $sd -PathType Container) {
    foreach ($s in @(Get-ChildItem -LiteralPath $sd -Directory)) { Copy-Tree $s.FullName ([IO.Path]::Combine($Dest, 'skills', $s.Name)) }
  }
  $cd = [IO.Path]::Combine($pd, 'commands')
  if (Test-Path -LiteralPath $cd -PathType Container) {
    foreach ($c in @(Get-ChildItem -LiteralPath $cd -File | Where-Object { $_.Name -clike '*.md' })) {
      $name = if ($p -ceq 'marketing') { 'marketing-' + $c.Name } else { $c.Name }
      [IO.File]::Copy($c.FullName, [IO.Path]::Combine($Dest, 'commands', $name), $true)
    }
  }
}

if (-not $Marketplace) {
  if ($Cloud) {
    $Marketplace = $repo
  } else {
    $slug = ''
    if (Get-Command git -CommandType Application -ErrorAction SilentlyContinue) {
      $origin = (Invoke-Native 'git' @('-C', $repo, 'remote', 'get-url', 'origin')).Out.Trim()
      $m = [regex]::Match($origin, '^(?:https://github\.com/|git@github\.com:)([^/]+/[^/]+)$')
      if ($m.Success) { $slug = $m.Groups[1].Value -replace '\.git$', '' }
    }
    $Marketplace = if ($slug) { $slug } else { $repo }
  }
}
$useFiles = [bool]$Files
if (-not $useFiles -and -not (Test-SamePath $Dest $cliHome)) {
  Out-Note '-Dest is not ~/.claude, where the claude CLI installs plugins - copying the packs as plain files instead'; $useFiles = $true
}
$claudeExe = $null
if (-not $useFiles) {
  # An .exe/.cmd first (npm's claude.ps1 shim and its extensionless sh shim are not what cmd would run).
  $apps = @(Get-Command claude -CommandType Application -ErrorAction SilentlyContinue | Where-Object {
      -not $onWindows -or @('.exe', '.cmd', '.bat', '.com') -contains [IO.Path]::GetExtension([string]$_.Path).ToLowerInvariant() })
  $cmd = @($apps + @(Get-Command claude -ErrorAction SilentlyContinue) | Where-Object { $_ }) | Select-Object -First 1
  if ($cmd) { $claudeExe = if ($cmd.Path) { $cmd.Path } else { $cmd.Name } }
  else { Out-Note 'claude CLI not found - copying the packs as plain files instead of plugins'; $useFiles = $true }
}
if (-not $useFiles) {
  if ((Invoke-Native $claudeExe @('plugin', 'marketplace', 'list')).Out.Contains('claude-md-packs')) {
    if ((Invoke-Native $claudeExe @('plugin', 'marketplace', 'update', 'claude-md-packs')).Code -eq 0) {
      Out-Ok 'marketplace claude-md-packs refreshed'
    } else { Out-Warn 'marketplace claude-md-packs: refresh failed (kept the installed version)' }
  } elseif ((Invoke-Native $claudeExe @('plugin', 'marketplace', 'add', $Marketplace)).Code -eq 0) {
    Out-Ok "marketplace claude-md-packs added ($Marketplace)"
  } else {
    Out-Fail "claude plugin marketplace add $Marketplace failed - check the source (a private GitHub repo needs git credentials)"
  }
  foreach ($p in $packList) {
    if ((Invoke-Native $claudeExe @('plugin', 'install', "$p@claude-md-packs", '--scope', 'user')).Code -eq 0) {
      $null = Invoke-Native $claudeExe @('plugin', 'update', "$p@claude-md-packs")
      Out-Ok "plugin $p@claude-md-packs installed (user scope)"
    } else { Out-Fail "claude plugin install $p@claude-md-packs failed" }
  }
} else {
  try {
    foreach ($sub in @('agents', 'skills', 'commands')) { [void][IO.Directory]::CreateDirectory([IO.Path]::Combine($Dest, $sub)) }
    foreach ($p in $packList) {
      if ($p -ceq 'ecc') { Out-Warn 'ecc is not copied as files (about 15k always-on tokens; install it as a plugin per project)'; continue }
      try { Copy-PackFiles $p; Out-Ok "pack $p copied as files (agents, skills, commands) into $Dest" }
      catch { Out-Fail "cannot copy pack $p ($(Get-Msg $_))" }
    }
  } catch { Out-Fail "cannot create the agents/skills/commands folders in $Dest ($(Get-Msg $_))" }
}

# ---- 4. optional hooks (cloud: review-gate only): copy + register in exec form with absolute paths, never duplicated
function Test-HookRegistered($lst, [string]$n) {
  foreach ($e in $lst) {
    if (-not ($e -is [System.Collections.IDictionary])) { continue }
    $hs = $e['hooks']
    if (-not ($hs -is [System.Collections.IList])) { continue }
    foreach ($h in $hs) {
      if (-not ($h -is [System.Collections.IDictionary])) { continue }
      $texts = @()
      if ($h['command'] -is [string]) { $texts += $h['command'] }
      if ($h['args'] -is [System.Collections.IList]) { $texts += @($h['args'] | Where-Object { $_ -is [string] }) }
      foreach ($t in $texts) {
        if ($t.IndexOf("$n.ps1", [StringComparison]::OrdinalIgnoreCase) -ge 0 -or
            $t.IndexOf("$n.sh", [StringComparison]::OrdinalIgnoreCase) -ge 0) { return $true }
      }
    }
  }
  return $false
}
function Register-Hooks([string[]]$names, [string]$hd) {
  $dst = [IO.Path]::Combine($Dest, 'settings.json')
  try { $cur = Read-JsonFile $dst } catch { Out-Fail "$dst does not parse ($(Get-Msg $_)) - hooks not registered"; return }
  if (-not ($cur -is [System.Collections.IDictionary])) { Out-Fail "$dst is not a JSON object - hooks not registered"; return }
  if (-not $cur.Contains('hooks')) { $cur['hooks'] = New-JsonObject }
  $hooksObj = $cur['hooks']
  if (-not ($hooksObj -is [System.Collections.IDictionary])) { Out-Fail "${dst}: ""hooks"" is not an object - hooks not registered"; return }
  $hdFwd = $hd -replace '\\', '/'
  $changed = @()
  foreach ($n in $names) {
    $evt = if ($n -ceq 'plan-gate') { 'Stop' } else { 'PreToolUse' }
    if (-not $hooksObj.Contains($evt)) { $hooksObj[$evt] = New-JsonArray }
    $lst = $hooksObj[$evt]
    if (-not ($lst -is [System.Collections.IList])) { Out-Fail "${dst}: hooks.$evt is not a list - hooks not registered"; return }
    if (Test-HookRegistered $lst $n) { Out-Ok "hook $n already registered on $evt"; continue }
    $argv = New-JsonArray
    foreach ($a in @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "$hdFwd/$n.ps1")) { [void]$argv.Add($a) }
    $hook = New-JsonObject
    $hook['type'] = 'command'; $hook['command'] = 'powershell.exe'; $hook['args'] = $argv
    if ($n -ceq 'plan-gate') { $hook['timeout'] = 15 }
    $entry = New-JsonObject
    if ($n -ceq 'guard') { $entry['matcher'] = 'Bash|PowerShell|Monitor|Write|Edit' }
    if ($n -ceq 'review-gate') { $entry['matcher'] = 'Bash|PowerShell|Monitor' }
    $hl = New-JsonArray; [void]$hl.Add($hook); $entry['hooks'] = $hl
    [void]$lst.Add($entry)
    $changed += "$n on $evt"
  }
  if ($changed.Count -gt 0) {
    try {
      [IO.File]::Copy($dst, "$dst.$stamp.hooks.bak", $true)
      Write-JsonFile $dst $cur
    } catch { Out-Fail "cannot write $dst ($(Get-Msg $_)) - hooks not registered"; return }
    Out-Ok ('hooks registered: ' + ($changed -join ', '))
  }
}
if ($hookList.Count -gt 0 -and $settingsBad) {
  Out-Warn 'hooks not registered: settings.json could not be merged (see the ERROR above)'; $hookList = @()
}
if ($hookList.Count -gt 0) {
  $hd = [IO.Path]::Combine($Dest, 'hooks')
  $copied = @()
  try { [void][IO.Directory]::CreateDirectory($hd) } catch { Out-Fail "cannot create $hd" }
  foreach ($h in $hookList) {
    try {
      [IO.File]::Copy([IO.Path]::Combine($repo, '.claude', 'hooks', "$h.ps1"), [IO.Path]::Combine($hd, "$h.ps1"), $true)
      $copied += $h
    } catch { Out-Fail "cannot copy hook $h" }
  }
  if ($copied.Count -gt 0) { Register-Hooks $copied $hd }
}

if ($script:rc -eq 0) {
  $preset = if ($Cloud) { ' (cloud preset)' } else { '' }
  Write-Output "DONE claude-md user layer installed into $Dest$preset. Start a new session, then check /context (memory files) and /plugin or @agent- (agents)."
} else {
  Write-Output 'FAILED - fix the ERROR line(s) above and run again (safe to re-run).'
}
exit $script:rc
