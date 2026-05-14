# GitHub Skill Autosync Hook

Auto-commit and final-push hooks for GitHub-backed Codex skill repositories.

This hook is part of the `codex-hooks` repository. The active Codex installation still lives in:

```text
C:\Users\<you>\.codex
```

Run the repository-level `install.ps1` to sync this hook into the local Codex root.

## Included hooks

- `PostToolUse`: auto-commit changes for GitHub-backed skill repositories.
- `Stop`: push completed GitHub skill changes after the Codex turn finishes.

The hook only activates when all of these are true:

- The current directory is inside a Git repository.
- The repository has a GitHub remote.
- The repository looks like a skill repository:
  - it is under `%USERPROFILE%\.codex\skills`, or
  - it is under `%USERPROFILE%\.agents\skills`, or
  - the repository root contains `SKILL.md`.

## Install

From the `codex-hooks` repository root:

```powershell
.\install.ps1 -Hook github-skill-autosync
```

Preview the planned changes:

```powershell
.\install.ps1 -Hook github-skill-autosync -DryRun
```

Install to a custom Codex home:

```powershell
.\install.ps1 -Hook github-skill-autosync -CodexHome "C:\Users\you\.codex"
```

## Files installed

```text
%USERPROFILE%\.codex\hooks.json
%USERPROFILE%\.codex\hooks\auto_commit_github_skill.ps1
%USERPROFILE%\.codex\hooks\push_github_skill.ps1
```

The installer also enables this feature in `%USERPROFILE%\.codex\config.toml`:

```toml
[features]
codex_hooks = true
```

## Safety notes

- Auto-commit uses `git add -A`, so each skill repository should maintain a correct `.gitignore`.
- Commit uses `--no-verify` because the goal is to guarantee a local commit after Codex changes.
- Push still depends on GitHub credentials, network access, remote permissions, and branch protection.
- Existing installed files are backed up under `.codex-backups` in this repository before replacement.
