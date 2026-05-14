param(
  [string]$Hook = "github-skill-autosync",
  [string]$CodexHome = (Join-Path $env:USERPROFILE ".codex"),
  [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$HookRoot = Join-Path $RepoRoot (Join-Path "hooks" $Hook)
$SourceHooksJson = Join-Path $HookRoot "codex\hooks.json"
$SourceScripts = Join-Path $HookRoot "scripts"
$TargetHooksJson = Join-Path $CodexHome "hooks.json"
$TargetHooksDir = Join-Path $CodexHome "hooks"
$TargetConfig = Join-Path $CodexHome "config.toml"
$BackupRoot = Join-Path $RepoRoot ".codex-backups"

function Write-Step([string]$message) {
  Write-Host "[codex-hooks] $message"
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
  $rendered | ConvertFrom-Json | Out-Null

  if (-not $DryRun) {
    $parent = Split-Path -Parent $target
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    Set-Content -Path $target -Value $rendered -Encoding UTF8
  }
  Write-Step "Installed $target"
}

function Enable-CodexHooksFeature([string]$configPath) {
  if (-not (Test-Path -Path $configPath)) {
    if (-not $DryRun) {
      New-Item -ItemType Directory -Force -Path (Split-Path -Parent $configPath) | Out-Null
      Set-Content -Path $configPath -Value "[features]`ncodex_hooks = true`n" -Encoding UTF8
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
    Set-Content -Path $configPath -Value $updated -Encoding UTF8
  }
  Write-Step "Enabled codex_hooks in $configPath"
}

if (-not (Test-Path -Path $SourceHooksJson)) {
  throw "Missing source hooks.json: $SourceHooksJson"
}
if (-not (Test-Path -Path $SourceScripts)) {
  throw "Missing scripts directory: $SourceScripts"
}

Write-Step "Repository: $RepoRoot"
Write-Step "Hook: $Hook"
Write-Step "Codex home: $CodexHome"
if ($DryRun) { Write-Step "Dry run mode: no files will be changed" }

Enable-CodexHooksFeature $TargetConfig
Install-HooksJson $SourceHooksJson $TargetHooksJson $CodexHome

foreach ($script in Get-ChildItem -Path $SourceScripts -Filter "*.ps1" -File) {
  Copy-WithBackup $script.FullName (Join-Path $TargetHooksDir $script.Name)
}

Write-Step "Install complete"
