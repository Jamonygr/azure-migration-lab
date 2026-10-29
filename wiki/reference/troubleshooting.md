# Troubleshooting and recovery

<p align="center">
  <img src="../images/cinematic/rehearsal-validation.png" alt="Cinematic rehearsal and validation checkpoint" width="1000" />
</p>

Start with the failing stage's timestamped evidence. Identify whether the failure
belongs to infrastructure, guest setup, network/DNS, identity, data transfer,
validation, or lifecycle enforcement.

| Symptom | Inspect | Response |
|---|---|---|
| Preflight fails on SKU/quota | Region restrictions and available cores | Choose an explicit supported profile size or request quota |
| Terraform plan wants unexpected replacement | Environment, backend, profile and state path | Stop and reconcile ownership |
| Guest bootstrap times out | Run Command status, package download and install logs | Wait for a known installer or repair the failed prerequisite |
| Storage/SQL access denied | Managed identity selection and scoped role/database grants | Correct identity or permission; allow propagation |
| Service resolves publicly | Private DNS zone links and endpoint state | Repair private DNS |
| SQL import rejects schema | Supported object/schema check | Use the sample schema or design a separate migration |
| Row count matches but validation fails | Ordered signature and identity/schema details | Find the changed data; repeat consistent copy |
| File comparison fails | Relative paths, sizes, hashes, source writers | Resolve changes and repeat transfer |
| Target liveness succeeds, readiness fails | SQL endpoint, target principal and schema | Repair the data dependency |
| Cutover appears unchanged | DNS answer/cache and returned site | Verify from within the lab network |
| Stage transition rejected | Journal status and prior operation result | Use the supported next/recovery stage |
| Destroy leaves resources | Owning state, backup dependencies, role/lock errors | Retain state and resolve the exact blocker |

## Failed operation discipline

Do not delete the work directory to “start fresh” while Azure resources still
exist. That discards the ownership and evidence needed to recover.

A failed command can have made partial changes. Examine real data and DNS
before retrying. Preserve a target with accepted writes; Reset-Target is only
for disposable migration content.

## Identity propagation

New role assignments may take time to become effective. A bounded retry is
reasonable after confirming the correct identity and scope. Repeated access
denial with the wrong identity will not be repaired by waiting.

## Source unavailable before acceptance

Keep the target fenced while deciding the next step. Determine whether the final
migration evidence is complete and current. Do not accept solely to silence
a journal error. Restore source availability or document a deliberate recovery
decision with the required data checks.

## Evidence to share in an issue

Commit, tool versions, profile, failing stage, redacted error, expected behavior,
and whether resources remain. Exclude state, plans, tokens, passwords, and
customer data.

## Related pages

- [State and secrets](state-and-secrets.md)
- [Security policy](../../SECURITY.md)
