# Migration skills and evidence matrix

<p align="center">
  <img src="../images/cinematic/migration-playbook.png" alt="Migration playbook with a luminous path from source to cloud" width="1000" />
</p>

*Connect each migration capability to an exercise and evidence you can inspect.*

| Capability | Exercise | Evidence to produce |
|---|---|---|
| Inventory a workload | Discover | Host, app, database and file inventory |
| Identify dependencies | Assess | Runtime and migration dependency map |
| Select a destination | Architecture review | Rehost/replatform decision and constraints |
| Build isolated infrastructure | Provision | Plan, resource inventory, private topology |
| Use workload identity | SQL/application setup | Runtime principal and successful connection |
| Move relational data consistently | SQL scenario | Schema/content/identity comparison |
| Verify unstructured content | File scenario | Path/length/hash manifest comparison |
| Control change windows | Final migration | Fence and timing evidence |
| Change application routing | Cutover | DNS plus returned site identity |
| Recover before acceptance | Rollback | Source service restoration evidence |
| Establish data authority | Accept | Target write and closed rollback boundary |
| Remove obsolete compute | Retire-Source | Ownership-aware removal inventory |
| Keep automation reviewable | CI and tests | Static checks, artifacts and failure cases |
| Control cost | Teardown | Resource/state cleanup and residual-cost review |

## Design questions

- Why does a matching row count not prove database equivalence?
- Why is privileged OAuth file access not an SMB authorization test?
- Why does a private endpoint require both DNS and permissions?
- Why does source retirement preserve foundation-owned network resources?
- What changes once accepted target writes exist?
- Which evidence survives a CI runner replacement?

Answers should reference observed results or actual implementation. When a
capability has not been tested live, identify it as an intended behavior.

## Official context

The mapping is a practical study aid drawn from this repository's exercises.
For current examination requirements, use the official links in
[Certification alignment](README.md).
