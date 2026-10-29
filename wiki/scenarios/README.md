# Migration scenario workbook

<p align="center">
  <img src="../images/cinematic/migration-playbook.png" alt="Migration playbook with a luminous path from source to cloud" width="1000" />
</p>

Work through these phases in order. Record actual command results and evidence
locations in a copy of the [wave plan](../../docs/templates/wave-plan.md).
Do not tick a box because a command started; inspect its completion.

## Lifecycle map

~~~mermaid
stateDiagram-v2
    [*] --> Provisioned: Provision
    Provisioned --> Seeded: Seed
    Seeded --> Discovered: Discover
    Discovered --> Rehearsed: Rehearse
    Rehearsed --> Reset: Reset-Target
    Reset --> Rehearsed: Rehearse again
    Discovered --> Migrated: Migrate
    Reset --> Migrated: Migrate
    Migrated --> Validated: Validate
    Validated --> Cutover: Cutover
    Cutover --> RolledBack: Rollback
    RolledBack --> Reset: Reset-Target
    Cutover --> Accepted: Accept
    Accepted --> Retired: Retire-Source
    Retired --> Destroyed: Destroy
    Destroyed --> [*]
~~~

Destroy is also available from intermediate states with its confirmation phrase.
The diagram shows the normal learning route; the CLI enforces the complete
transition contract. Preflight, Plan, and Assess-Export are supporting operations.

## Phase 0 — Prepare and provision

- [ ] Select a profile and record the subscription, region, owner, and budget.
- [ ] Run Preflight and resolve prerequisites.
- [ ] Provision the foundation, source, target, and initial DNS state.
- [ ] Seed the sample workload; confirm source health and a working catalog.
- [ ] Record the Terraform plan/apply outputs and source baseline.

Guide: [Preparation](prepare.md). Deliverable: a working source and an identified,
isolated target.

## Phase 1 — Discover and assess

- [ ] Run Discover; inspect application, database, host, and file inventory.
- [ ] Record dependencies and compatibility limits.
- [ ] Run Assess-Export; optionally import into Azure Migrate for assessment.
- [ ] Select rebuild/redeploy for the application, Azure SQL for catalog data,
  and Azure Files for demonstration content.
- [ ] Define acceptance tests and the rollback deadline.

Guide: [Discovery and assessment](discover-assess.md). Deliverable: assessment
record and dependency map.

## Phase 2 — Rehearse

- [ ] Run Rehearse against the target while logical DNS remains on source.
- [ ] Inspect application deployment, SQL comparison, and file manifests.
- [ ] Confirm the rehearsal does not authorize final cutover.
- [ ] Record elapsed time and defects.
- [ ] Run Reset-Target before final migration; confirm the intended environment.

Guides: [Application](application-rehost.md), [SQL](sql-migration.md),
[Files](file-migration.md), [Rehearsal](rehearsal.md).

## Phase 3 — Final migration and validation

~~~powershell
./scripts/Invoke-Lab.ps1 -Stage Reset-Target @lab -ConfirmAction 'RESET TARGET cheap-lab'
./scripts/Invoke-Lab.ps1 -Stage Migrate @lab
./scripts/Invoke-Lab.ps1 -Stage Validate @lab
~~~

- [ ] Observe that source writes are fenced during the final copy.
- [ ] Compare final source/export/target database signatures.
- [ ] Compare every expected file and its content hash.
- [ ] Verify readiness against target data and the site's identity.
- [ ] Confirm target writes remain fenced.
- [ ] Attach the latest validation evidence to the cutover record.

A rehearsal result is not final migration evidence. Any changed input or failed
check must be understood before moving traffic.

## Phase 4 — Cutover and rollback practice

~~~powershell
./scripts/Invoke-Lab.ps1 -Stage Cutover @lab
./scripts/Invoke-Lab.ps1 -Stage Rollback @lab
~~~

- [ ] Check private DNS and an application response from the resolved site.
- [ ] Roll back before acceptance; confirm source behavior.
- [ ] Reset the disposable target, then repeat final migration and validation.
- [ ] Perform the final intended cutover and record its result.

Guide: [Cutover and rollback](cutover-rollback.md).

## Phase 5 — Accept and retire

- [ ] Complete the acceptance record with final checks and evidence.
- [ ] Run Accept only when target behavior is satisfactory.
- [ ] Confirm the source-retirement decision explicitly.
- [ ] Retire the source, inspect remaining resources, and run target checks.
- [ ] Destroy the remaining disposable lab when the exercise is complete.

Guide: [Acceptance and retirement](accept-retire.md). Deliverable: acceptance
record, retirement inventory, and teardown evidence.

## Design review prompts

Explain what would change for a 2 TB database, a writable SMB file server,
a domain-joined application, or a workload with a 30-second RPO. Separate
features this repository implements from engineering work those cases require.
