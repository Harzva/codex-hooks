# Design Notes

## Why a repository

Codex loads hooks from the local Codex home, but source control should live outside that runtime directory.
This repository makes the hook reusable, reviewable, and easy to sync across machines.

## Runtime location

Installed files:

```text
%USERPROFILE%\.codex\hooks.json
%USERPROFILE%\.codex\hooks\*.ps1
```

Source files:

```text
codex\hooks.json
scripts\*.ps1
```

## Event model

- `PostToolUse` creates a commit immediately after a Codex tool changes a GitHub skill repository.
- `Stop` pushes the accumulated commits after the Codex turn has finished.

This keeps local history granular while avoiding remote pushes for every single tool call.

## Limits

- This hook cannot bypass GitHub branch protection.
- This hook cannot push without configured credentials.
- This hook intentionally trusts `.gitignore` to exclude generated or private files.

