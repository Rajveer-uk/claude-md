#requires -Version 5
# format.ps1 - OPTIONAL PostToolUse hook (Windows): format the file that was just
# edited, using ONLY a formatter already present in the project (no installs, no
# network). Best-effort and silent; always exits 0 so it can never block work.
# Register on matcher "Edit|Write". Disable by removing it from settings.json.

try { $raw = [Console]::In.ReadToEnd(); if (-not $raw) { exit 0 }; $in = $raw | ConvertFrom-Json } catch { exit 0 }

$path = [string]$in.tool_input.file_path
if (-not $path -or -not (Test-Path -LiteralPath $path)) { exit 0 }
$cwd = [string]$in.cwd
if (-not $cwd) { $cwd = (Get-Location).Path }
$ext = [System.IO.Path]::GetExtension($path).ToLowerInvariant()

function LocalBin($rel) { $p = Join-Path $cwd $rel; if (Test-Path -LiteralPath $p) { $p } else { $null } }

try {
  switch -Regex ($ext) {
    '^\.(js|jsx|ts|tsx|mjs|cjs|json|css|scss|less|md|mdx|html|ya?ml|vue|svelte)$' {
      $pr = (LocalBin 'node_modules\.bin\prettier.cmd'); if (-not $pr) { $pr = LocalBin 'node_modules\.bin\prettier' }
      if ($pr) { & $pr --write --log-level warn -- "$path" 2>$null | Out-Null }
    }
    '^\.php$' {
      $pint = LocalBin 'vendor\bin\pint'
      if ($pint -and (Get-Command php -ErrorAction SilentlyContinue)) { & php "$pint" "$path" 2>$null | Out-Null }
    }
    '^\.py$' {
      if (Get-Command ruff -ErrorAction SilentlyContinue) { & ruff format "$path" 2>$null | Out-Null }
      elseif (Get-Command black -ErrorAction SilentlyContinue) { & black -q "$path" 2>$null | Out-Null }
    }
    '^\.go$' { if (Get-Command gofmt -ErrorAction SilentlyContinue) { & gofmt -w "$path" 2>$null | Out-Null } }
    '^\.rs$' { if (Get-Command rustfmt -ErrorAction SilentlyContinue) { & rustfmt "$path" 2>$null | Out-Null } }
  }
} catch {}
exit 0
