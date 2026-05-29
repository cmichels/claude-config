# Architecture Overview

## Problem Statement

I created this repository to build and version Claude skills, slash commands, and tool interoperability in one place while enforcing coding standards and guardrails.

As the Claude iteration cycle accelerated (tuning prompts, tightening constraints, automating workflows), I needed an environment that supports fast changes, durable history, and safe experimentation.

This repository provides a centralized, portable config system that persists across machines and can be symlinked like a dotfiles setup.

## System Components

- `settings.json.template`: tracked portable permissions, hooks, plugin, and status-line configuration
- `setup.sh`: machine bootstrap that creates local artifacts from tracked templates
- `commands/`: reusable slash command workflows for repeatable operational tasks
- `agents/`: focused review and analysis agents for quality gates and workflow acceleration
- `bin/`: helper scripts for session orchestration and repository context
- `status-line.sh`: terminal status integration for active workflow context

## Runtime Model

- Tracked configuration is portable and repository-safe.
- Machine-local artifacts (`settings.json`, `.mcp.json`, session state) are generated and gitignored.
- Environment-specific path requirements are applied at setup time via:
  - `CLAUDE_PROJECTS_ROOT`
  - `CLAUDE_PRIMARY_PROJECT`

## Safety Boundaries

- Secrets and machine-local state are excluded from git.
- Internal notes and memory snapshots are kept local-only.
- Public docs and commands are sanitized to avoid employer-specific identifiers.

## Integration with pr-monitor

This repository works in conjunction with `pr-monitor` as part of a terminal-first execution loop:

- `claude-config` defines the operating environment, guardrails, and automation entry points.
- `pr-monitor` provides PR awareness and review workflow signal in the terminal.
- Together they reduce context switching and support faster, safer execution.

## Tradeoffs

- Template-driven local generation adds one setup step but preserves portability and privacy.
- Strong guardrails reduce accidental misuse at the cost of occasional permission tuning.
- Local customization is intentionally explicit rather than hidden to preserve reproducibility.
