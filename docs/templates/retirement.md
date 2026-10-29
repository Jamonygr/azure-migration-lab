# Source retirement and teardown record

- Workload / run:
- Acceptance record:
- Operator:
- Date/time:

## Source retirement

- [ ] Target accepted and controlled write tested.
- [ ] Source compute ownership identified from source state.
- [ ] Source no longer needed for the baseline rollback route.
- [ ] Correct environment confirmation phrase reviewed.
- [ ] Source retirement command completed.
- [ ] Source-owned VM/NIC/disks absent as expected.
- [ ] Foundation-owned source network retained intentionally.
- [ ] Stable migration identity still exists.
- [ ] Target readiness and routing still pass.

Evidence:
Remaining source-related resources and owner:

## Final lab destroy

- [ ] Cutover and workload resources removed before foundation.
- [ ] Four Terraform states reflect teardown.
- [ ] Expected Azure resource groups absent.
- [ ] Manually created assessment/appliance resources checked separately.
- [ ] Retained backup/storage items documented with deletion owner.
- [ ] Costs/residual resources reviewed.
- [ ] State/evidence retained securely until verification complete.

Result:
Outstanding cleanup:
Owner / deadline:
