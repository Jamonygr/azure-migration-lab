# Cutover checklist

- Run / profile / commit:
- Final migration evidence:
- Planned window:
- Operator / decision owner:
- Rollback deadline:

## Before cutover

- [ ] Source write fence confirmed.
- [ ] Final source/export/target SQL signatures match.
- [ ] Final file paths, lengths and hashes match.
- [ ] Target liveness and database-backed readiness pass.
- [ ] Target identifies itself correctly.
- [ ] Target writes remain blocked.
- [ ] Source remains available for rollback.
- [ ] Correct cutover state/backend selected.
- [ ] No unresolved blocking findings.

## Execute and observe

Command:
Start/end timestamps:
DNS answer before:
DNS answer after:
Application site through logical hostname:
Readiness and catalog checks:
Cache delay or unexpected behavior:

## Decision

- [ ] Continue validation before acceptance.
- [ ] Roll back before acceptance.

Reason:
Decision owner / timestamp:
Recovery evidence:
