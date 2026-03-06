# All-Hands Onboarding Goal — Memory

## Project Purpose
Performance goal (40% weight) for 2026: proactively drive onboarding success for assigned sites in the OP (Optelligent) Jira project. Tracked via markdown + Jira.

## Key Structure
- `tracker.md` — master dashboard of all sites
- `scripts/new-site.sh <name> [--jira]` — creates site folder + optional Jira epic in OP
- `scripts/weekly-review.sh [date]` — creates weekly review file
- `scripts/jira-setup.sh` — one-time label/filter setup (already run, created OP-3179)
- `templates/` — checklists, check-in templates, all-hands runbook, calendar invites
- `sites/_template/` — per-site template folder
- `issues/issue-log.md` — central issue tracker

## Jira Setup
- Project: OP (Optelligent)
- Labels created: all-hands, onboarding, pre-go-live, post-go-live, site-health
- Setup ticket: OP-3179
- Saved filter needs manual creation (acli doesn't support filter create)
- JQL: `project = OP AND labels in (all-hands, onboarding, pre-go-live, post-go-live, site-health) ORDER BY created DESC`

## Playwright MCP Validation
- Template at `templates/site-validation-playwright.md` — 10-phase browser validation guide
- `scripts/prep-validation.sh <site>` sets up screenshot dir and prints kickoff prompt
- Screenshots saved to `screenshots/<site-name>/` (gitignored, binary evidence)
- Quick Validation section (6 checks) for time-constrained all-hands
- Targets Stark Web (Angular 19) at /Volumes/data/projects/tsp/stark-web
- Staging: stgcapi.staging.starktechgroup.com
- Key app concepts: asset tree (Sites → Equipment → Points), events/fault viewer, tagging, dashboards, admin config

## Role Context
- Kuda is a **contributor/reviewer** in all-hands, not the coordinator
- All-hands runbook is a personal playbook, not a coordination doc
- Goal emphasis: proactive weekly reviews that catch issues before all-hands is needed

## Technical Notes
- zsh `status` is read-only — use `site_status` in scripts
- Use `command cp` to bypass `-i` alias in zsh
- macOS `._*` files excluded via .gitignore
- Screenshots (png/jpeg) gitignored
