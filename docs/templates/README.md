# Migration decision and evidence templates

Copy these into a private run-evidence folder and fill them with observed
results. The repository copies are blank templates, not completed approvals.

| Template | When to use |
|---|---|
| [Assessment](assessment.md) | Before choosing a migration method |
| [Dependency map](dependency-map.md) | During discovery |
| [Wave plan](wave-plan.md) | Before rehearsal and final scheduling |
| [Cutover checklist](cutover.md) | Before changing traffic |
| [Acceptance](acceptance.md) | Before enabling authoritative target writes |
| [Retirement](retirement.md) | Before removing source compute |
| [Run evidence](run-evidence.md) | Throughout the lifecycle |

Use resource labels and evidence paths. Keep subscription IDs, user identifiers,
private hostnames, logs, and screenshots in access-controlled storage. Never
paste credentials or Terraform state into a template.
