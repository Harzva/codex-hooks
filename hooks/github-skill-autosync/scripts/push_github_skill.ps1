param()

$ErrorActionPreference = "Continue"
$PSNativeCommandUseErrorActionPreference = $false

function Read-HookInput {
  $raw = [Console]::In.ReadToEnd()
  if ([string]::IsNullOrWhiteSpace($raw)) {
    return [pscustomobject]@{ cwd = (Get-Location).Path; hook_event_name = "Manual" }
  }
  return $raw | ConvertFrom-Json
}

function Get-RepoRoot([string]$cwd) {
  $root = & git -C $cwd rev-parse --show-toplevel 2>$null
  if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($root)) {
    return $null
  }
  return ($root | Select-Object -First 1).Trim()
}

function Test-GitHubRemote([string]$repoRoot) {
  $remotes = & git -C $repoRoot remote -v 2>$null
  return ($LASTEXITCODE -eq 0 -and ($remotes -match "github\.com[:/]"))
}

function Get-PrimaryRemoteUrl([string]$repoRoot) {
  $remoteUrl = (& git -C $repoRoot remote get-url origin 2>$null | Select-Object -First 1)
  if (-not [string]::IsNullOrWhiteSpace($remoteUrl)) {
    return $remoteUrl.Trim()
  }

  $remoteName = (& git -C $repoRoot remote 2>$null | Select-Object -First 1)
  if ([string]::IsNullOrWhiteSpace($remoteName)) {
    return ""
  }

  $remoteUrl = (& git -C $repoRoot remote get-url $remoteName.Trim() 2>$null | Select-Object -First 1)
  if ([string]::IsNullOrWhiteSpace($remoteUrl)) {
    return ""
  }
  return $remoteUrl.Trim()
}

function Test-SkillRepo([string]$repoRoot, [string]$cwd) {
  $skillRoots = @(
    (Join-Path $env:USERPROFILE ".codex\skills"),
    (Join-Path $env:USERPROFILE ".agents\skills")
  )

  foreach ($skillRoot in $skillRoots) {
    if ($repoRoot.StartsWith($skillRoot, [System.StringComparison]::OrdinalIgnoreCase) -or
        $cwd.StartsWith($skillRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
      return $true
    }
  }

  return (Test-Path -Path (Join-Path $repoRoot "SKILL.md"))
}

function Invoke-WithRepoLock([string]$repoRoot, [scriptblock]$body) {
  $safeName = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($repoRoot)).TrimEnd("=").Replace("+", "-").Replace("/", "_")
  $lockPath = Join-Path $env:TEMP "codex-hook-$safeName.lock"
  $deadline = (Get-Date).AddSeconds(30)

  while ($true) {
    try {
      New-Item -ItemType Directory -Path $lockPath -ErrorAction Stop | Out-Null
      break
    } catch {
      if ((Get-Date) -gt $deadline) {
        throw "Timed out waiting for hook lock: $lockPath"
      }
      Start-Sleep -Milliseconds 250
    }
  }

  try {
    & $body
  } finally {
    Remove-Item -Path $lockPath -Force -Recurse -ErrorAction SilentlyContinue
  }
}

function Ensure-GitIdentity([string]$repoRoot) {
  $name = (& git -C $repoRoot config user.name 2>$null | Select-Object -First 1)
  if ([string]::IsNullOrWhiteSpace($name)) {
    & git -C $repoRoot config user.name "Codex Auto Commit" | Out-Null
  }

  $email = (& git -C $repoRoot config user.email 2>$null | Select-Object -First 1)
  if ([string]::IsNullOrWhiteSpace($email)) {
    & git -C $repoRoot config user.email "codex-auto-commit@users.noreply.github.com" | Out-Null
  }
}

function Write-HookLog([string]$message) {
  $logDir = Join-Path $env:USERPROFILE ".codex\hooks\logs"
  New-Item -ItemType Directory -Force -Path $logDir | Out-Null
  $logPath = Join-Path $logDir "github-skill-autosync.log"
  Add-Content -Path $logPath -Value $message -Encoding UTF8
}

function Write-StopResult([string]$message) {
  if ([string]::IsNullOrWhiteSpace($message)) {
    [pscustomobject]@{ continue = $true } | ConvertTo-Json -Compress
  } else {
    [pscustomobject]@{
      continue = $true
      systemMessage = $message
    } | ConvertTo-Json -Compress
  }
}

$inputObject = Read-HookInput
$cwd = if ($inputObject.cwd) { [string]$inputObject.cwd } else { (Get-Location).Path }
$repoRoot = Get-RepoRoot $cwd
if (-not $repoRoot) { exit 0 }
if (-not (Test-GitHubRemote $repoRoot)) { exit 0 }
if (-not (Test-SkillRepo $repoRoot $cwd)) { exit 0 }

Invoke-WithRepoLock $repoRoot {
  Ensure-GitIdentity $repoRoot

  $finalCommit = $null
  $status = & git -C $repoRoot status --porcelain
  if (-not [string]::IsNullOrWhiteSpace(($status -join "`n"))) {
    & git -C $repoRoot add -A | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "git add failed before push" }

    $staged = & git -C $repoRoot diff --cached --name-only
    if (-not [string]::IsNullOrWhiteSpace(($staged -join "`n"))) {
      $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss K"
      & git -C $repoRoot commit --no-verify -m "chore(skill): auto-commit final Codex changes" -m "Created by Codex Stop hook at $timestamp before push." | Out-Null
      if ($LASTEXITCODE -ne 0) { throw "git commit failed before push" }
      $finalCommit = (& git -C $repoRoot rev-parse --short HEAD).Trim()
      $remoteUrlForFinalCommit = Get-PrimaryRemoteUrl $repoRoot
      $branchForFinalCommit = (& git -C $repoRoot branch --show-current).Trim()
      Write-HookLog "[commit] $timestamp repo=$repoRoot remote=$remoteUrlForFinalCommit branch=$branchForFinalCommit commit=$finalCommit subject=""chore(skill): auto-commit final Codex changes"""
    }
  }

  $marker = Join-Path $repoRoot ".git\codex-auto-commit-pending-push"
  if (-not (Test-Path -Path $marker)) {
    Write-StopResult ""
    exit 0
  }

  $branch = (& git -C $repoRoot branch --show-current).Trim()
  if ([string]::IsNullOrWhiteSpace($branch)) {
    throw "Cannot push detached HEAD"
  }

  $remoteUrl = Get-PrimaryRemoteUrl $repoRoot
  $headCommit = (& git -C $repoRoot rev-parse --short HEAD).Trim()
  $headSubject = (& git -C $repoRoot log -1 --pretty=%s).Trim()
  $upstream = & git -C $repoRoot rev-parse --abbrev-ref --symbolic-full-name "@{u}" 2>$null
  if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace(($upstream -join "`n"))) {
    & git -C $repoRoot push | Out-Null
    $pushTarget = ($upstream | Select-Object -First 1).Trim()
  } else {
    & git -C $repoRoot push -u origin $branch | Out-Null
    $pushTarget = "origin/$branch"
  }

  if ($LASTEXITCODE -ne 0) { throw "git push failed" }
  Remove-Item -Path $marker -Force -ErrorAction SilentlyContinue

  $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss K"
  $summary = @(
    "Codex hook synced GitHub skill repository.",
    "Repository: $repoRoot",
    "Remote: $remoteUrl",
    "Branch: $branch -> $pushTarget",
    "Latest commit: $headCommit $headSubject"
  ) -join "`n"

  Write-HookLog "[push] $timestamp repo=$repoRoot remote=$remoteUrl branch=$branch target=$pushTarget commit=$headCommit subject=""$headSubject"""
  Write-StopResult $summary
}
