param()

$ErrorActionPreference = "Continue"
$PSNativeCommandUseErrorActionPreference = $false

function Read-HookInput {
  $raw = [Console]::In.ReadToEnd()
  if ([string]::IsNullOrWhiteSpace($raw)) {
    return [pscustomobject]@{
      cwd = (Get-Location).Path
      hook_event_name = "Manual"
      raw = ""
    }
  }

  try {
    $obj = $raw | ConvertFrom-Json
    $obj | Add-Member -NotePropertyName raw -NotePropertyValue $raw -Force
    return $obj
  } catch {
    return [pscustomobject]@{
      cwd = (Get-Location).Path
      hook_event_name = "Manual"
      raw = $raw
    }
  }
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

function Write-Utf8NoBom([string]$path, [string]$value) {
  $encoding = [System.Text.UTF8Encoding]::new($false)
  [System.IO.File]::WriteAllText($path, $value, $encoding)
}

function Write-HookLog([string]$message) {
  $logDir = Join-Path $env:USERPROFILE ".codex\hooks\logs"
  New-Item -ItemType Directory -Force -Path $logDir | Out-Null
  $logPath = Join-Path $logDir "auto-learning-from-failure.log"
  Add-Content -Path $logPath -Value $message -Encoding UTF8
}

function Get-InputValue($obj, [string[]]$names) {
  foreach ($name in $names) {
    if ($obj.PSObject.Properties.Name -contains $name) {
      $value = $obj.$name
      if (-not [string]::IsNullOrWhiteSpace([string]$value)) {
        return [string]$value
      }
    }
  }
  return ""
}

function Get-RecentTranscriptText($inputObject) {
  $paths = @(
    (Get-InputValue $inputObject @("transcript_path", "transcriptPath")),
    (Get-InputValue $inputObject @("conversation_path", "conversationPath")),
    (Get-InputValue $inputObject @("log_path", "logPath"))
  ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

  foreach ($path in $paths) {
    if (Test-Path -Path $path) {
      try {
        return (Get-Content -Path $path -Tail 900 -ErrorAction Stop) -join "`n"
      } catch {
      }
    }
  }

  $parts = @()
  foreach ($name in @("last_assistant_message", "lastAssistantMessage", "prompt", "raw")) {
    $value = Get-InputValue $inputObject @($name)
    if (-not [string]::IsNullOrWhiteSpace($value)) {
      $parts += $value
    }
  }
  return ($parts -join "`n")
}

function Redact-SensitiveText([string]$text) {
  $result = $text
  $result = [regex]::Replace($result, "(?i)(token|secret|password|api[_-]?key|authorization)(\s*[:=]\s*)([^\s`"']+)", '$1$2[REDACTED]')
  $result = [regex]::Replace($result, "ghp_[A-Za-z0-9_]{20,}", "ghp_[REDACTED]")
  $result = [regex]::Replace($result, "github_pat_[A-Za-z0-9_]{20,}", "github_pat_[REDACTED]")
  $result = [regex]::Replace($result, "sk-[A-Za-z0-9_-]{20,}", "sk-[REDACTED]")
  return $result
}

function Get-FailureMatches([string]$text) {
  $regexPatterns = @(
    "Exit code:\s*[1-9]",
    "exit=\s*[1-9]",
    "\bfailed\b",
    "\bfailure\b",
    "\berror\b",
    "\bfatal:",
    "\bException:",
    "timed out",
    "timeout",
    "Could not connect",
    "Connection was reset",
    "Failed to connect",
    "permission denied",
    "not found",
    "No such file",
    "LASTEXITCODE"
  )

  $literalPatterns = @(
    "重试",
    "失败",
    "报错",
    "错误",
    "超时",
    "网络",
    "阻断"
  )

  $lines = $text -split "`r?`n"
  $failureLines = [System.Collections.Generic.List[string]]::new()
  foreach ($line in $lines) {
    $matched = $false
    foreach ($pattern in $regexPatterns) {
      if ($line -match $pattern) {
        $matched = $true
        break
      }
    }
    if (-not $matched) {
      foreach ($pattern in $literalPatterns) {
        if ($line.Contains($pattern)) {
          $matched = $true
          break
        }
      }
    }
    if ($matched) {
      $trimmed = $line.Trim()
      if ($trimmed.Length -gt 280) {
        $trimmed = $trimmed.Substring(0, 280) + "..."
      }
      $failureLines.Add($trimmed)
    }
  }
  return $failureLines
}

function Get-StableSessionId($inputObject, [string]$cwd) {
  $sessionId = Get-InputValue $inputObject @("session_id", "sessionId", "conversation_id", "conversationId")
  if (-not [string]::IsNullOrWhiteSpace($sessionId)) {
    return $sessionId
  }

  $raw = "$cwd|$((Get-Date).ToString('yyyyMMddHH'))"
  $bytes = [Text.Encoding]::UTF8.GetBytes($raw)
  $sha = [Security.Cryptography.SHA256]::Create().ComputeHash($bytes)
  return ([BitConverter]::ToString($sha).Replace("-", "").Substring(0, 16).ToLowerInvariant())
}

$inputObject = Read-HookInput
$cwd = Get-InputValue $inputObject @("cwd")
if ([string]::IsNullOrWhiteSpace($cwd)) {
  $cwd = (Get-Location).Path
}

$text = Get-RecentTranscriptText $inputObject
if ([string]::IsNullOrWhiteSpace($text)) {
  Write-StopResult ""
  exit 0
}

if ($text -match "Auto Learning From Failure triggered" -or
    $text -match "Before sending the final answer, do a short auto-learning pass") {
  Write-StopResult ""
  exit 0
}

$matches = Get-FailureMatches $text
$retryCount = ([regex]::Matches($text, "(?i)\bretry\b|重试|again|再试")).Count
$toolFailureCount = ([regex]::Matches($text, "Exit code:\s*[1-9]|exit=\s*[1-9]|LASTEXITCODE")).Count
$networkFailureCount = ([regex]::Matches($text, "(?i)Could not connect|Failed to connect|Connection was reset|github\.com:443|网络")).Count
$failureCount = $matches.Count

$shouldCapture = ($failureCount -ge 5) -or ($toolFailureCount -ge 2) -or ($retryCount -ge 2 -and $failureCount -ge 3) -or ($networkFailureCount -ge 2)
if (-not $shouldCapture) {
  Write-StopResult ""
  exit 0
}

$sessionId = Get-StableSessionId $inputObject $cwd
$stateDir = Join-Path $env:USERPROFILE ".codex\hooks\state\auto-learning-from-failure"
New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
$statePath = Join-Path $stateDir "$sessionId.marker"
if (Test-Path -Path $statePath) {
  Write-StopResult ""
  exit 0
}

$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss K"
Set-Content -Path $statePath -Value $timestamp -Encoding UTF8

$captureDir = Join-Path $env:USERPROFILE ".codex\hooks\auto-learning-from-failure"
New-Item -ItemType Directory -Force -Path $captureDir | Out-Null
$safeSession = [regex]::Replace($sessionId, "[^A-Za-z0-9_.-]", "-")
$fileStamp = Get-Date -Format "yyyyMMdd-HHmmss"
$capturePath = Join-Path $captureDir "$fileStamp-$safeSession.md"

$snippets = $matches | Select-Object -Last 16 | ForEach-Object { "- " + (Redact-SensitiveText $_) }
$snippetText = ($snippets -join "`n")
$capture = @"
# Auto Learning From Failure

Created: $timestamp

Workspace:

```text
$cwd
```

Signals:

- Failure-like lines: $failureCount
- Tool failure markers: $toolFailureCount
- Retry markers: $retryCount
- Network failure markers: $networkFailureCount

Recent evidence:

$snippetText

Decision rubric:

- Choose `memory` for stable user, machine, account, or project facts.
- Choose `rule` for reusable behavior constraints or preferred fallback paths.
- Choose `skill` for repeatable multi-step workflows with docs, scripts, or examples.

"@

Write-Utf8NoBom $capturePath $capture
Write-HookLog "[capture] $timestamp session=$sessionId cwd=$cwd file=$capturePath failures=$failureCount toolFailures=$toolFailureCount retries=$retryCount networkFailures=$networkFailureCount"

$message = @"
Auto Learning From Failure triggered.

Capture file: $capturePath
Workspace: $cwd
Signals: failures=$failureCount, toolFailures=$toolFailureCount, retries=$retryCount, networkFailures=$networkFailureCount

Before sending the final answer, do a short auto-learning pass:
1. Decide whether the durable lesson should be a memory, rule, or skill.
2. Create or update exactly one durable asset only if the lesson is concrete and likely to prevent repeat failures in a new thread.
3. Prefer:
   - memory for stable local/user/project facts,
   - rule for broad behavior constraints or fallback policies,
   - skill for repeatable multi-step workflows worth packaging.
4. Keep secrets redacted. Do not store tokens, credentials, or private values.
5. Mention the chosen asset path in the final answer. If no durable lesson is trustworthy, say the capture was recorded but no asset was created.
"@

Write-StopResult $message
