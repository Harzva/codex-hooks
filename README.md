# Codex Hooks

A small collection of reusable local hooks for Codex.

Codex loads active hooks from the local Codex home:

```text
%USERPROFILE%\.codex
```

This repository is the source package. Use `install.ps1` to sync selected hooks into the local Codex root.

## Hooks

| Hook | Purpose |
| --- | --- |
| `github-skill-autosync` | Auto-commit GitHub-backed skill repository changes after tool use, then push when the Codex turn stops. |

## Layout

```text
codex-hooks/
  README.md
  install.ps1
  hooks/
    github-skill-autosync/
      README.md
      codex/hooks.json
      scripts/*.ps1
      docs/
```

## Install

Install the default hook:

```powershell
.\install.ps1
```

Install a named hook:

```powershell
.\install.ps1 -Hook github-skill-autosync
```

Preview the planned changes:

```powershell
.\install.ps1 -Hook github-skill-autosync -DryRun
```

The installer enables this feature in `%USERPROFILE%\.codex\config.toml`:

```toml
[features]
codex_hooks = true
```

## Notes

- Existing installed files are backed up under `.codex-backups`.
- Hook scripts should avoid hard-coded user paths; templates use `__CODEX_HOME__` and the installer renders it.
- Push operations still depend on GitHub credentials, network access, remote permissions, and branch protection.
