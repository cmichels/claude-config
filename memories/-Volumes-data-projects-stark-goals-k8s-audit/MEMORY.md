# K8s Audit Project Memory

## Project
- **Goal:** Kubernetes Cluster Audit & Improvement Recommendations (20% weight)
- **Deadline:** 2026-06-30
- **Plan:** `/Volumes/data/projects/stark-goals/k8s-audit/PLAN.md`
- **CLAUDE.md:** Created 2026-02-25 with full project context

## Cluster Access
- Context: `prod` (via `kubectx prod`)
- **Provider:** Azure AKS (managed)
- **Cluster Name:** STGCluster01
- **Resource Group:** SI-0000_PilotResourceGroup
- **Subscription:** d0e88d2d-0520-481a-94bd-129cb5573396
- **Tenant:** starktech.com
- **Portal:** https://portal.azure.com/#@starktech.com/resource/subscriptions/d0e88d2d-0520-481a-94bd-129cb5573396/resourceGroups/SI-0000_PilotResourceGroup/providers/Microsoft.ContainerService/managedClusters/STGCluster01/overview

## Key Files
- `PLAN.md` — master execution plan with 5 phases, task checklists, tooling list, report TOC
- `FINDINGS.md` — comprehensive findings with priority matrix (41 items)
- `REPORT.md` — formal audit report (Phase 4 deliverable) with exec summary, findings, roadmap, appendices
- `CLAUDE.md` — project instructions for Claude Code sessions
- `data/phase2/` — raw scan data (kubescape, popeye, AKS config, images, nodes)
- `data/phase3/` — analysis artifacts (deployment health, ingress, storage, Gatekeeper)

## Confluence Pages
- **Parent:** K8s Audit (ID: 2902818822)
- **Security Findings** (ID: 2904752129)
- **Cost Optimization** (ID: 2904489987)
- **Maintainability** (ID: 2904358916)
- **Priority Matrix & Roadmap** (ID: 2904784897)
- **Space ID:** 19464196 | **Cloud ID:** 7d1d0780-63ed-4375-90d5-5424cc8695a3

## Findings Summary
- **41 total findings:** 3 Critical, 12 High, 19 Medium, 7 Low
- Top criticals: No AAD (S-01), No network policies (S-02), ES 7.9.2 w/ 89 vulns (S-11)
- Phase 3 additions: ingress-nginx v1.8.1 (S-18), no SSL redirect (S-19), no rate limit (S-20), 14 deploys missing probes (S-21), Kafka OOM risk (M-12)
- Cluster: 6y old, 27 nodes, no autoscaling, Free SKU, kubenet, public API server
- Gatekeeper: 16 constraints all in dryrun (635 violations)
- Azure Policy: 15 non-compliant (Security Benchmark v3.0)
- Kubescape: NSA 67.2%, MITRE 65.7%
- Secrets: 106 env-var-mounted across pods
- ~$3,120/mo compute, CPU utilization 7% actual vs 58% requested (8x over)

## Installed Tools
- **Krew plugins:** who-can, access-matrix, np-viewer, outdated, resource-capacity, images, kubesec-scan, deprecations, score
- **Standalone (brew):** kubescape 4.0.2, trivy 0.69.1, popeye 0.22.1

## Decisions & Notes
- Confluence pages published 2026-02-25 (all 4 child pages under parent)
- FINDINGS.md is single source of truth; Confluence pages are published snapshots
- Phase 3 complete 2026-02-25: added 5 new findings (S-18 through S-21, M-12), total now 41
- Phase 4 complete 2026-02-25: REPORT.md authored with full structure
- Overall progress: 80% (Phase 5 stakeholder review remaining)
- Confluence pages need re-sync to reflect Phase 3 additions
