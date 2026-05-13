# Contributing

Thanks for contributing.

## Setup

```bash
uv sync
./setup.sh
```

If `settings.json` is missing, setup generates it from `settings.json.template`.
You can customize machine-local path values before setup:

```bash
export CLAUDE_PROJECTS_ROOT="$HOME/projects"
export CLAUDE_PRIMARY_PROJECT="work"
```

## Branching

- Use `feature/*` for features
- Use `bug/*` for fixes

## Pull Requests

- Target base branch `dev` unless explicitly directed otherwise.
- Keep changes scoped to the request; avoid drive-by refactors.
- Include a clear summary and validation steps.
- Do not commit secrets, tokens, or machine-local/private artifacts.

## Quality Expectations

- Keep docs and examples portable.
- Prefer least-privilege automation defaults.
- Preserve behavior unless a change is explicitly requested.
