# Migration foundations

<p align="center">
  <img src="../images/cinematic/security-foundations.png" alt="Shield and cloud representing migration security foundations" width="1000" />
</p>

A landing zone prepares a destination. A migration moves a workload into that
destination while controlling compatibility, data loss, downtime, and recovery.
This lab focuses on the adoption part of that journey.

## Strategy before tooling

Record why the workload is moving, who can accept it, and which outcomes are
measurable. For the sample catalog, useful outcomes are: all expected rows
arrive, file content matches, the application connects with its target identity,
the logical hostname reaches the intended site, and rollback remains possible
until acceptance.

Use [the assessment record](../../docs/templates/assessment.md) to capture
decisions. An attractive target architecture alone does not establish that
a workload can safely move.

## Migration choices used here

| Component | Source | Target | Method |
|---|---|---|---|
| Application host | Windows Server with IIS | Fresh Windows Server with IIS | Rebuild and redeploy |
| Catalog database | SQL Server Express | Azure SQL Database | Schema and demonstration data transfer |
| File content | Local directory exposed through SMB | Azure Files | Content copy and hash verification |
| Service name | Private DNS pointing at source | Same name pointing at target | Controlled DNS change |

Rehosting application code is different from replicating a VM. This exercise
does not preserve the source OS, machine identity, installed software inventory,
or every SQL Server/SMB feature.

## Discovery, assessment, and evidence

Discovery records what exists. Assessment asks whether it can move and what
must change. Rehearsal tests those assumptions. Acceptance confirms that the
result meets agreed criteria.

Azure Migrate's CSV import supports assessment without appliance discovery;
CSV-imported servers cannot be migrated through that import workflow.
See [Microsoft's CSV tutorial](https://learn.microsoft.com/azure/migrate/tutorial-discover-import).
Keep the portal assessment evidence separate from this lab's actual
application/data migration evidence.

## Define a migration window

The source write fence prevents new sample application writes during the final
copy. The duration of the fence is part of observed downtime. Rehearsal measures
the stages; it does not predict production throughput.

Record your target RPO and RTO, actual timings, and exceptions in the cutover
template. The demo's read-only interval and small dataset do not prove
production recovery objectives.

## Related pages

- [Architecture overview](overview.md)
- [Discovery and assessment](../scenarios/discover-assess.md)
- [Cutover checklist](../../docs/templates/cutover.md)
