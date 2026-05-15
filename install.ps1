param(
  [string]$Hook = "github-skill-autosync",
  [string]$CodexHome = (Join-Path $env:USERPROFILE ".codex"),
  [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$HooksRoot = Join-Path $RepoRoot "hooks"
$TargetHooksJson = Join-Path $CodexHome "hooks.json"
$TargetHooksDir = Join-Path $CodexHome "hooks"
$TargetConfig = Join-Path $CodexHome "config.toml"
$BackupRoot = Join-Path $RepoRoot ".codex-backups"
$DeprecatedHookScripts = @(
  "failure_learning_capture.ps1"
)

function Write-Step([string]$message) {
  Write-Host "[codex-hooks] $message"
}

function Write-Utf8NoBom([string]$path, [string]$value) {
  $encoding = [System.Text.UTF8Encoding]::new($false)
  [System.IO.File]::WriteAllText($path, $value, $encoding)
}

function Copy-WithBackup([string]$source, [string]$target) {
  if (Test-Path -Path $target) {
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupDir = Join-Path $BackupRoot $stamp
    if (-not $DryRun) {
      New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
      Copy-Item -Path $target -Destination (Join-Path $backupDir (Split-Path $target -Leaf)) -Force
    }
    Write-Step "Backed up $target"
  }

  if (-not $DryRun) {
    $parent = Split-Path -Parent $target
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    Copy-Item -Path $source -Destination $target -Force
  }
  Write-Step "Installed $target"
}

function Install-HooksJson([string]$source, [string]$target, [string]$codexHome) {
  if (Test-Path -Path $target) {
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupDir = Join-Path $BackupRoot $stamp
    if (-not $DryRun) {
      New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
      Copy-Item -Path $target -Destination (Join-Path $backupDir (Split-Path $target -Leaf)) -Force
    }
    Write-Step "Backed up $target"
  }

  $escapedCodexHome = $codexHome.Replace("\", "\\")
  $rendered = (Get-Content -Path $source -Raw).Replace("__CODEX_HOME__", $escapedCodexHome)
  $sourceObject = $rendered | ConvertFrom-Json

  $targetObject = if (Test-Path -Path $target) {
    Get-Content -Path $target -Raw | ConvertFrom-Json
  } else {
    [pscustomobject]@{ hooks = [pscustomobject]@{} }
  }

  $merged = [ordered]@{ hooks = [ordered]@{} }

  if ($targetObject.hooks) {
    foreach ($event in $targetObject.hooks.PSObject.Properties) {
      $entries = @()
      foreach ($entry in @($event.Value)) {
        $entryJson = $entry | ConvertTo-Json -Depth 20 -Compress
        $isDeprecated = $false
        foreach ($scriptName in $DeprecatedHookScripts) {
          if ($entryJson -match [regex]::Escape($scriptName)) {
            $isDeprecated = $true
            break
          }
        }
        if (-not $isDeprecated) {
          $entries += $entry
        }
      }
      if ($entries.Count -gt 0) {
        $merged.hooks[$event.Name] = $entries
      }
    }
  }

  if ($sourceObject.hooks) {
    foreach ($event in $sourceObject.hooks.PSObject.Properties) {
      if (-not $merged.hooks.Contains($event.Name)) {
        $merged.hooks[$event.Name] = @()
      }

      $existingEntries = @($merged.hooks[$event.Name] | ForEach-Object { $_ | ConvertTo-Json -Depth 20 -Compress })
      foreach ($entry in @($event.Value)) {
        $entryJson = $entry | ConvertTo-Json -Depth 20 -Compress
        if ($existingEntries -notcontains $entryJson) {
          $merged.hooks[$event.Name] += $entry
        }
      }
    }
  }

  $output = $merged | ConvertTo-Json -Depth 20

  if (-not $DryRun) {
    $parent = Split-Path -Parent $target
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    Write-Utf8NoBom $target $output
  }
  Write-Step "Installed $target"
}

function Enable-CodexHooksFeature([string]$configPath) {
  if (-not (Test-Path -Path $configPath)) {
    if (-not $DryRun) {
      New-Item -ItemType Directory -Force -Path (Split-Path -Parent $configPath) | Out-Null
      Write-Utf8NoBom $configPath "[features]`ncodex_hooks = true`n"
    }
    Write-Step "Created config with codex_hooks enabled"
    return
  }

  $text = Get-Content -Path $configPath -Raw
  if ($text -match "(?m)^\s*codex_hooks\s*=\s*true\s*$") {
    Write-Step "codex_hooks already enabled"
    return
  }

  if ($text -match "(?m)^\s*\[features\]\s*$") {
    $updated = [regex]::Replace($text, "(?m)^(\s*\[features\]\s*)$", "`$1`ncodex_hooks = true", 1)
  } else {
    $updated = "[features]`ncodex_hooks = true`n`n$text"
  }

  if (-not $DryRun) {
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupDir = Join-Path $BackupRoot $stamp
    New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
    Copy-Item -Path $configPath -Destination (Join-Path $backupDir "config.toml") -Force
    Write-Utf8NoBom $configPath $updated
  }
  Write-Step "Enabled codex_hooks in $configPath"
}

function Get-HookNames([string]$requestedHook) {
  if ($requestedHook -eq "all") {
    return @(Get-ChildItem -Path $HooksRoot -Directory | ForEach-Object { $_.Name })
  }
  return @($requestedHook)
}

Write-Step "Repository: $RepoRoot"
Write-Step "Hook: $Hook"
Write-Step "Codex home: $CodexHome"
if ($DryRun) { Write-Step "Dry run mode: no files will be changed" }

Enable-CodexHooksFeature $TargetConfig
foreach ($hookName in Get-HookNames $Hook) {
  $HookRoot = Join-Path $HooksRoot $hookName
  $SourceHooksJson = Join-Path $HookRoot "codex\hooks.json"
  $SourceScripts = Join-Path $HookRoot "scripts"

  if (-not (Test-Path -Path $SourceHooksJson)) {
    throw "Missing source hooks.json: $SourceHooksJson"
  }
  if (-not (Test-Path -Path $SourceScripts)) {
    throw "Missing scripts directory: $SourceScripts"
  }

  Write-Step "Installing hook module: $hookName"
  Install-HooksJson $SourceHooksJson $TargetHooksJson $CodexHome

  foreach ($script in Get-ChildItem -Path $SourceScripts -Filter "*.ps1" -File) {
    Copy-WithBackup $script.FullName (Join-Path $TargetHooksDir $script.Name)
  }
}

foreach ($scriptName in $DeprecatedHookScripts) {
  $target = Join-Path $TargetHooksDir $scriptName
  if (Test-Path -Path $target) {
    if (-not $DryRun) {
      Remove-Item -Path $target -Force
    }
    Write-Step "Removed deprecated hook script $target"
  }
}

Write-Step "Install complete"
