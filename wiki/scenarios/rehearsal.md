# Rehearse before the migration window

<p align="center">
  <img src="../images/cinematic/rehearsal-validation.png" alt="Cinematic rehearsal and validation checkpoint" width="1000" />
</p>

*Test the target directly while the normal application name continues to resolve to the source.*

## Objective

Exercise transfer and verification without switching the logical application
name away from the source.

~~~powershell
./scripts/Invoke-Lab.ps1 -Stage Rehearse @lab
~~~

Rehearsal is a complete experiment: observe source preparation, package/export,
private transfer, target deployment/import, and validation. It is useful even
when it fails, because it identifies work to complete before the real window.

## Review the result

- Did guest setup finish without manual configuration?
- Can each identity reach only the required services?
- Are database schema/content and file hashes identical?
- Does target readiness use the target database?
- Are target writes denied?
- Does the logical hostname still resolve to source?
- How long did each stage take?

Record observed times in the wave plan. A first run includes installation and
cache costs that may differ from later runs; keep those measurements separate.

## Reset a disposable target

~~~powershell
./scripts/Invoke-Lab.ps1 -Stage Reset-Target @lab -ConfirmAction 'RESET TARGET cheap-lab'
~~~

Reset is destructive to target migration content. Use the phrase matching the
selected environment. Reset is required after rehearsal or rollback before the
next final migration. Do not reset after acceptance or while a target contains
authoritative business data.

A reset invalidates earlier target evidence. Continue with a new rehearsal or
final Migrate and inspect its results rather than reusing the previous validation.

## Rehearsal exit criteria

Produce a short rehearsal report with commit, profile, dataset identity,
elapsed time, successful checks, failures, remediation, and remaining risk.
Every blocking failure must be resolved before final migration.

A successful rehearsal is permission to schedule the final copy, not evidence
that the final copy has happened. The source may have changed since rehearsal.

## Related pages

- [Scenario workbook](README.md)
- [Cutover and rollback](cutover-rollback.md)
- [Troubleshooting](../reference/troubleshooting.md)
