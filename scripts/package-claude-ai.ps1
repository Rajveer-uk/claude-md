#requires -Version 5
# package-claude-ai.ps1 - validate skills and zip them for upload to a claude.ai account
# (Settings > Capabilities: code execution on; then Customize > Skills > + > Create skill > Upload a skill).
# Windows twin of scripts/package-claude-ai.sh - same checks, same output.
#
# Use it only for surfaces the account plugins don't reach: mobile, the API, cloud Code sessions,
# or an account without plugins. Where an account plugin (base / marketing / council) is installed,
# its skills are already there - uploading the same skill lists it twice (and it also syncs into
# signed-in local Claude Code as anthropic-skills:<name>, next to the plugin copy).
#
# Usage (from anywhere):
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\package-claude-ai.ps1
#       default set: regression-guard, work-quality-checker, ai-writing-tells, brand-voice, secure-code-reviewer,
#                    requirements-gate
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\package-claude-ai.ps1 <skill> ...
#       instead: skill folder paths, or bare names found under plugins\*\skills\ (e.g. caveman, council)
#
# Checks per skill - ERROR (not packaged): SKILL.md missing or its frontmatter unparseable; folder name
# differs from frontmatter `name`; name not ^[a-z0-9-]{1,64}$ or contains "anthropic"/"claude";
# description missing, over 1024 chars, or containing < or >; unquoted ": " in name/description.
# WARN (still packaged): description over 200 chars (help-center limit), SKILL.md body over 500 lines,
# frontmatter fields outside the Agent Skills set, symlinks/junctions (skipped). A missing skill folder is skipped.
#
# Output: dist\claude-ai\<name>.zip with the skill folder at the zip root (dist/ is gitignored), built with
# Compress-Archive; if that yields backslash entry names (older Windows PowerShell), the zip is rebuilt
# with forward slashes so claude.ai can read it. Exit 0 = all found skills packaged; 1 = an ERROR or
# nothing packaged; 2 = dist\ not writable.
param(
  [Parameter(Position = 0, ValueFromRemainingArguments = $true)][string[]]$Skill,
  [switch]$Help
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$outDir = Join-Path (Join-Path $repoRoot 'dist') 'claude-ai'
$defaultSkills = @(
  'plugins/base/skills/regression-guard',
  'plugins/base/skills/work-quality-checker',
  'plugins/marketing/skills/ai-writing-tells',
  'plugins/marketing/skills/brand-voice',
  'plugins/base/skills/secure-code-reviewer',
  'plugins/base/skills/requirements-gate'
)
$safeFields = @('name', 'description', 'license', 'allowed-tools', 'metadata', 'compatibility', 'version')
$junkFiles = @('.DS_Store', 'Thumbs.db', 'desktop.ini')
$junkDirs = @('.git', '__pycache__')
$secretNames = @('.env', '.env.*', '.envrc', '*.pem', '*.key', '*.p12', '*.pfx', '*.keystore', '*.jks',
  '*.ppk', 'id_rsa', 'id_rsa.*', 'id_ed25519', 'id_ed25519.*', '*_rsa', '*_ed25519', '*_ecdsa',
  '*_dsa', '.git-credentials', '.netrc', '.npmrc', '.pypirc', '.pgpass', '.my.cnf',
  'credentials', 'credentials.*', '*.credentials', '*.tfstate', '*.tfstate.backup', '*.tfvars',
  'gha-creds-*.json', '*service-account*.json')

if ($Help -or ($Skill -and ($Skill[0] -eq '-h' -or $Skill[0] -eq '--help'))) {
  foreach ($l in @(Get-Content -LiteralPath $PSCommandPath | Select-Object -Skip 1)) {
    if ($l -notmatch '^#') { break }
    $l -replace '^# ?', ''
  }
  exit 0
}

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

# Resolve an argument to a skill folder: a path (from the current dir or the repo root) or a bare name.
# Returns the full path, $null (not found) or 'AMBIGUOUS'.
function Resolve-SkillDir([string]$a) {
  $a = $a.TrimEnd('/', '\')
  if (-not $a) { return $null }
  if (Test-Path -LiteralPath $a -PathType Container) { return (Resolve-Path -LiteralPath $a).ProviderPath }
  $p = Join-Path $repoRoot $a
  if (Test-Path -LiteralPath $p -PathType Container) { return (Resolve-Path -LiteralPath $p).ProviderPath }
  if ($a -match '[\\/]') { return $null }
  $found = @()
  $pluginsDir = Join-Path $repoRoot 'plugins'
  if (Test-Path -LiteralPath $pluginsDir -PathType Container) {
    foreach ($pl in @(Get-ChildItem -LiteralPath $pluginsDir -Directory)) {
      $cand = Join-Path (Join-Path $pl.FullName 'skills') $a
      if (Test-Path -LiteralPath $cand -PathType Container) { $found += $cand }
    }
  }
  if ($found.Count -eq 1) { return $found[0] }
  if ($found.Count -gt 1) { return 'AMBIGUOUS' }
  return $null
}

function ConvertFrom-DoubleQuoted([string]$s) {
  $sb = New-Object System.Text.StringBuilder
  $i = 0
  while ($i -lt $s.Length) {
    $c = $s[$i]
    if ($c -eq '\' -and $i + 1 -lt $s.Length) {
      $n = $s[$i + 1]
      if ($n -eq 'u' -and $i + 5 -lt $s.Length -and $s.Substring($i + 2, 4) -match '^[0-9a-fA-F]{4}$') {
        [void]$sb.Append([char][Convert]::ToInt32($s.Substring($i + 2, 4), 16)); $i += 6; continue
      }
      switch -CaseSensitive ([string]$n) {
        'n' { [void]$sb.Append("`n") }
        't' { [void]$sb.Append("`t") }
        '0' { [void]$sb.Append([char]0) }
        default { [void]$sb.Append($n) }
      }
      $i += 2; continue
    }
    [void]$sb.Append($c); $i++
  }
  return $sb.ToString()
}

# Value of a top-level frontmatter key: plain, quoted or block scalar. $null = nested mapping/list.
function Get-Scalar([string]$key, [string]$raw, [string[]]$cont, $errors) {
  $raw = $raw.Trim()
  if ($raw.StartsWith('>') -or $raw.StartsWith('|')) {
    $nonblank = @($cont | Where-Object { $_.Trim() })
    if ($nonblank.Count -eq 0) { return '' }
    $ind = ($nonblank | ForEach-Object { $_.Length - $_.TrimStart(' ').Length } | Measure-Object -Minimum).Minimum
    $body = @($cont | ForEach-Object { if ($_.Trim()) { $_.Substring($ind) } else { '' } })
    if ($raw.StartsWith('|')) { return ($body -join "`n").Trim("`n") }
    $paras = New-Object System.Collections.Generic.List[string]
    $cur = New-Object System.Collections.Generic.List[string]
    foreach ($l in $body) {
      if ($l.Trim()) { $cur.Add($l.Trim()) } else { $paras.Add(($cur -join ' ')); $cur.Clear() }
    }
    $paras.Add(($cur -join ' '))
    return ($paras -join "`n").Trim("`n")
  }
  if ($raw -eq '' -and $cont.Count -gt 0) { return $null }
  $joined = ((@($raw) + @($cont | ForEach-Object { $_.Trim() })) -join ' ').Trim()
  if ($raw.StartsWith('"')) {
    $m = [regex]::Match($joined, '^"((?:[^"\\]|\\.)*)"\s*(#.*)?$')
    if (-not $m.Success) { $errors.Add("${key}: unterminated or malformed double-quoted value"); return $joined }
    return (ConvertFrom-DoubleQuoted $m.Groups[1].Value)
  }
  if ($raw.StartsWith("'")) {
    $m = [regex]::Match($joined, "^'((?:[^']|'')*)'\s*(#.*)?$")
    if (-not $m.Success) { $errors.Add("${key}: unterminated or malformed single-quoted value"); return $joined }
    return $m.Groups[1].Value.Replace("''", "'")
  }
  $value = (($joined -split '\s#', 2)[0]).Trim()   # plain scalar: " #" starts a comment
  if (($key -eq 'name' -or $key -eq 'description') -and ($value.Contains(': ') -or $value.EndsWith(':'))) {
    $errors.Add("${key}: unquoted "": "" breaks YAML - wrap the value in double quotes or use >-")
  }
  return $value
}

# Validate one skill folder and zip it. Prints OK/WARN/ERROR lines; returns $true when packaged.
function Invoke-PackageSkill([string]$src) {
  $srcItem = Get-Item -LiteralPath $src -Force
  $base = $srcItem.FullName.TrimEnd('\', '/')
  $folder = $srcItem.Name
  $errors = New-Object System.Collections.Generic.List[string]
  $warns = New-Object System.Collections.Generic.List[string]
  $zipPath = Join-Path $outDir "$folder.zip"

  $skillMd = Join-Path $base 'SKILL.md'
  if (-not (Test-Path -LiteralPath $skillMd -PathType Leaf)) {
    Write-Output "ERROR ${folder}: no SKILL.md in $base"
    return $false
  }
  $text = [IO.File]::ReadAllText($skillMd).TrimStart([char]0xFEFF)
  $lines = @($text -split "\r?\n")
  if ($text.EndsWith("`n") -and $lines.Count -gt 0) { $lines = @($lines[0..($lines.Count - 2)]) }

  $fields = @{}
  $bodyCount = 0
  if ($lines.Count -eq 0 -or $lines[0].Trim() -ne '---') {
    $errors.Add('SKILL.md must start with a --- frontmatter line')
  } else {
    $end = -1
    for ($k = 1; $k -lt $lines.Count; $k++) { if ($lines[$k].Trim() -eq '---') { $end = $k; break } }
    if ($end -lt 0) {
      $errors.Add('frontmatter has no closing --- line')
    } else {
      $fm = @(); if ($end -gt 1) { $fm = @($lines[1..($end - 1)]) }
      $bodyCount = $lines.Count - $end - 1
      $i = 0
      while ($i -lt $fm.Count) {
        $line = $fm[$i]
        if (-not $line.Trim() -or $line.TrimStart().StartsWith('#')) { $i++; continue }
        $m = [regex]::Match($line, '^([A-Za-z0-9_-]+):(?:[ \t]+(.*)|[ \t]*)$')
        if (-not $m.Success) {
          $snip = $line.Trim(); if ($snip.Length -gt 60) { $snip = $snip.Substring(0, 60) }
          $errors.Add("frontmatter line $($i + 2) is not 'key: value': $snip")
          $i++; continue
        }
        $j = $i + 1
        while ($j -lt $fm.Count -and ($fm[$j].StartsWith(' ') -or $fm[$j].StartsWith("`t") -or -not $fm[$j].Trim())) { $j++ }
        $cont = @(); if ($j - 1 -ge $i + 1) { $cont = @($fm[($i + 1)..($j - 1)]) }
        while ($cont.Count -gt 0 -and -not $cont[$cont.Count - 1].Trim()) {
          if ($cont.Count -eq 1) { $cont = @() } else { $cont = @($cont[0..($cont.Count - 2)]) }
        }
        $key = $m.Groups[1].Value
        if ($fields.ContainsKey($key)) { $errors.Add("frontmatter key '$key' appears twice") }
        $fields[$key] = Get-Scalar $key $m.Groups[2].Value $cont $errors
        $i = $j
      }
    }
  }

  $name = $fields['name']; $desc = $fields['description']
  if (-not ($name -is [string]) -or -not $name) {
    $errors.Add('frontmatter has no name')
  } else {
    if ($name -cne $folder) { $errors.Add("folder name '$folder' != frontmatter name '$name' (claude.ai rejects the upload)") }
    if ($name -cnotmatch '^[a-z0-9-]{1,64}$') { $errors.Add("name '$name' must be 1-64 chars of a-z, 0-9 and hyphens") }
    if ($name -match 'anthropic|claude') { $errors.Add("name '$name' must not contain 'anthropic' or 'claude'") }
  }
  if (-not ($desc -is [string]) -or -not $desc.Trim()) {
    $errors.Add('frontmatter has no description')
  } else {
    if ($desc.Length -gt 1024) { $errors.Add("description is $($desc.Length) chars (max 1024)") }
    elseif ($desc.Length -gt 200) { $warns.Add("description is $($desc.Length) chars - the help center says 200 max; uploads have accepted more, so test it") }
    if ($desc -match '[<>]') { $errors.Add('description contains < or > (not allowed)') }
  }
  $extra = @($fields.Keys | Where-Object { $safeFields -notcontains $_ } | Sort-Object)
  if ($extra.Count -gt 0) { $warns.Add('fields outside the Agent Skills set (claude.ai may ignore them): ' + ($extra -join ', ')) }
  if ($bodyCount -gt 500) { $warns.Add("SKILL.md body is $bodyCount lines (keep it under 500; move detail into references/)") }

  foreach ($w in $warns) { Write-Output "WARN ${folder}: $w" }
  if ($errors.Count -gt 0) {
    foreach ($e in $errors) { Write-Output "ERROR ${folder}: $e" }
    if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }   # never leave a stale zip
    return $false
  }

  $stage = Join-Path ([IO.Path]::GetTempPath()) ('claude-ai-skill-' + [guid]::NewGuid().ToString('N'))
  $tmpZip = Join-Path $outDir "$name.partial.zip"
  try {
    # Stage a clean copy: no junk files, no symlinks/junctions (they could pull in files from outside).
    $stageSkill = Join-Path $stage $name
    New-Item -ItemType Directory -Path $stageSkill -Force | Out-Null
    $linkDirs = @(Get-ChildItem -LiteralPath $base -Recurse -Force -Directory |
      Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint } | ForEach-Object { $_.FullName })
    foreach ($ld in $linkDirs) { Write-Output "WARN ${folder}: skipped symlinked folder $($ld.Substring($base.Length + 1))" }
    $count = 0
    foreach ($f in @(Get-ChildItem -LiteralPath $base -Recurse -Force -File)) {
      if (-not $f.FullName.StartsWith($base + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw "unexpected path outside the skill folder: $($f.FullName)"
      }
      $rel = $f.FullName.Substring($base.Length + 1)
      $parts = $rel -split '[\\/]'
      if (@($parts | Where-Object { $junkDirs -contains $_ }).Count -gt 0) { continue }
      if ($junkFiles -contains $f.Name -or $f.Extension -eq '.pyc') { continue }
      if (@($linkDirs | Where-Object { $f.FullName.StartsWith($_ + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) }).Count -gt 0) { continue }
      if ($f.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        Write-Output "WARN ${folder}: skipped symlink $($rel -replace '\\', '/')"
        continue
      }
      # Mirrors the settings.json secret deny-list: such files are never packaged, even if present on disk.
      $leaf = $f.Name.ToLowerInvariant()
      $dirParts = if ($parts.Count -gt 1) { $parts[0..($parts.Count - 2)] } else { @() }
      $isSecret = (@($dirParts | Where-Object { $_ -ieq 'secrets' }).Count -gt 0) -or
        (@($secretNames | Where-Object { $leaf -like $_ }).Count -gt 0)
      if ($isSecret) {
        Write-Output "WARN ${folder}: skipped secret-looking file $($rel -replace '\\', '/') (never uploaded)"
        continue
      }
      if (Get-Command git -ErrorAction SilentlyContinue) {
        & git -C $f.DirectoryName check-ignore -q -- $f.FullName 2>$null
        if ($LASTEXITCODE -eq 0) {
          Write-Output "WARN ${folder}: skipped git-ignored file $($rel -replace '\\', '/')"
          continue
        }
      }
      $dest = Join-Path $stageSkill $rel
      New-Item -ItemType Directory -Path (Split-Path -Parent $dest) -Force | Out-Null
      Copy-Item -LiteralPath $f.FullName -Destination $dest -Force
      $count++
    }

    if (Test-Path -LiteralPath $tmpZip) { Remove-Item -LiteralPath $tmpZip -Force }
    Compress-Archive -LiteralPath $stageSkill -DestinationPath $tmpZip -CompressionLevel Optimal -Force

    $zip = [IO.Compression.ZipFile]::OpenRead($tmpZip)
    try { $entries = @($zip.Entries | ForEach-Object { $_.FullName }) } finally { $zip.Dispose() }
    if (@($entries | Where-Object { $_.Contains('\') }).Count -gt 0) {
      # Windows PowerShell 5.1's Compress-Archive can write backslash entry names; rebuild with '/'.
      Remove-Item -LiteralPath $tmpZip -Force
      $stageBase = (Get-Item -LiteralPath $stageSkill -Force).FullName.TrimEnd('\', '/')
      $zip = [IO.Compression.ZipFile]::Open($tmpZip, [IO.Compression.ZipArchiveMode]::Create)
      try {
        foreach ($f in @(Get-ChildItem -LiteralPath $stageBase -Recurse -Force -File)) {
          $rel = $f.FullName.Substring($stageBase.Length + 1) -replace '\\', '/'
          [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $f.FullName, "$name/$rel", [IO.Compression.CompressionLevel]::Optimal)
        }
      } finally { $zip.Dispose() }
      $zip = [IO.Compression.ZipFile]::OpenRead($tmpZip)
      try { $entries = @($zip.Entries | ForEach-Object { $_.FullName }) } finally { $zip.Dispose() }
    }
    if ($entries -notcontains "$name/SKILL.md") { throw "$name/SKILL.md missing from the zip root" }
    Move-Item -LiteralPath $tmpZip -Destination $zipPath -Force
  } catch {
    if (Test-Path -LiteralPath $tmpZip) { Remove-Item -LiteralPath $tmpZip -Force -ErrorAction SilentlyContinue }
    Write-Output "ERROR ${folder}: zipping failed - $($_.Exception.Message)"
    return $false
  } finally {
    if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue }
  }

  $kb = [Math]::Max(1, [Math]::Round((Get-Item -LiteralPath $zipPath).Length / 1024))
  Write-Output "OK $name -> dist/claude-ai/$name.zip ($count files, $kb KB, description $($desc.Length) chars)"
  return $true
}

if (-not $Skill -or $Skill.Count -eq 0) { $Skill = $defaultSkills }
try { New-Item -ItemType Directory -Path $outDir -Force | Out-Null } catch {
  Write-Output "ERROR cannot create ${outDir}: $($_.Exception.Message)"; exit 2
}

$packaged = 0; $failed = 0; $skipped = 0; $warned = 0
foreach ($s in $Skill) {
  $dir = Resolve-SkillDir $s
  if ($dir -eq 'AMBIGUOUS') {
    Write-Output "WARN ${s}: several plugins ship a skill with this name - pass its folder path instead; skipped"
    $skipped++; continue
  }
  if (-not $dir) { Write-Output "WARN ${s}: skill folder not found - skipped"; $skipped++; continue }
  $ok = $false
  try {
    foreach ($line in @(Invoke-PackageSkill $dir)) {
      if ($line -is [bool]) { $ok = $line; continue }
      Write-Output $line
      if ([string]$line -like 'WARN *') { $warned++ }
    }
  } catch {
    Write-Output "ERROR ${s}: $($_.Exception.Message)"
    $ok = $false
  }
  if ($ok) { $packaged++ } else { $failed++ }
}

Write-Output ''
Write-Output "Summary: $packaged packaged, $failed failed, $skipped skipped, $warned warnings -> dist/claude-ai/"
Write-Output ''
Write-Output 'Upload: claude.ai > Settings > Capabilities (code execution on), then Customize > Skills > + > Create skill > Upload a skill, one zip at a time.'
Write-Output "Reminder: don't upload a skill that an installed account plugin already provides (base, marketing, council) - it would be listed twice."
Write-Output "Upload only for surfaces plugins don't reach: mobile, the API, cloud Code sessions. Uploaded skills also sync into signed-in"
Write-Output 'local Claude Code as anthropic-skills:<name>; check /skills (claude.ai sync group) and /context for duplicates.'

if ($failed -eq 0 -and $packaged -gt 0) { exit 0 }
exit 1
