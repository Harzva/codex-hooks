# Auto Learning From Failure Hook

Detect repeated failure patterns near the end of a Codex turn and prompt Codex to convert the lesson into the right durable asset.

## Purpose

Long agent threads often discover local facts the hard way: missing SDKs, broken network paths, account routing rules, platform-specific commands, or repository-specific pitfalls. If those lessons stay only in the thread, a new agent thread may repeat the same failed path.

This hook watches the Stop event for repeated failure signals and creates a capture file for review. It then asks Codex to choose one of three durable asset types:

| Asset | Use when |
| --- | --- |
| `memory` | The lesson is a stable user/environment/project fact that future threads should remember. |
| `rule` | The lesson is a broad behavioral rule or safety constraint that should guide future work. |
| `skill` | The lesson is a repeatable multi-step workflow worth packaging with docs/scripts/examples. |

## Install

From the `codex-hooks` repository root:

```powershell
.\install.ps1 -Hook auto-learning-from-failure
```

Install every hook module:

```powershell
.\install.ps1 -Hook all
```

## Output

Capture files are written to:

```text
%USERPROFILE%\.codex\hooks\auto-learning-from-failure
```

The hook also writes a small log to:

```text
%USERPROFILE%\.codex\hooks\logs\auto-learning-from-failure.log
```

## Trigger behavior

The hook is intentionally conservative. It triggers only when repeated failure or retry signals appear in the recent transcript or Stop hook input. It skips when the turn already appears to be handling a failure-learning capture, preventing loops.
