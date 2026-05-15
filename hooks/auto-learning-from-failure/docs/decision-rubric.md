# Decision Rubric

Use this rubric when a failure-learning capture asks Codex to create a durable asset.

## Choose memory

Use a memory when the lesson is a stable fact that should be remembered across threads:

- User account routing preferences.
- Local SDK/toolchain availability.
- Project-specific locations or secrets-handling rules.
- A recurring environmental limitation.

Keep it short and factual.

## Choose rule

Use a rule when the lesson should change Codex behavior:

- Do not use a known-broken command path.
- Prefer a verified fallback after a specific failure pattern.
- Always inspect a specific file before acting in this domain.
- Avoid exposing sensitive output.

Rules should be imperative and reusable.

## Choose skill

Use a skill when the lesson is a repeatable workflow:

- It needs steps, scripts, examples, or references.
- It applies to a class of future tasks, not a single project fact.
- It can be invoked by a clear task description.

Do not create a skill for a one-off workaround.

