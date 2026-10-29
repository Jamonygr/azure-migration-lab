# Environment profiles

<p align="center">
  <img src="../images/cinematic/source-to-cloud.png" alt="Source servers connected to a luminous cloud destination" width="1000" />
</p>

Profiles keep the same migration workflow while changing supporting network and
operations controls. All use West Europe, Windows Server 2022, source B2ms and
target B2s by default.

| Capability | cheap-lab | dev | lab | prod |
|---|---|---|---|---|
| Two VMs + SQL + Files | Yes | Yes | Yes | Yes |
| Private service endpoints | Yes | Yes | Yes | Yes |
| Explicit VM egress public IP | Yes | Yes | Yes | No |
| NAT egress | No | No | No | Yes |
| Monitoring | Yes | Yes | Yes | Yes |
| Workbook | No | No | Yes | Yes |
| VM backup | No | No | Yes | Yes |
| Owner-tag audit policy | No | No | No | Yes |
| Public RDP by default | No | No | No | No |
| Scheduled VM shutdown | 20:00 UTC | 20:00 UTC | 20:00 UTC | 20:00 UTC |

~~~mermaid
flowchart TD
    A["Choose a learning objective"] --> B["First complete migration: cheap-lab"]
    A --> C["Repeat development experiments: dev"]
    A --> D["Practice monitoring and backup: lab"]
    A --> E["Practice NAT and governance controls: prod"]
~~~

## Configuration decisions

Budget alerts require recipients. An empty `budget_emails` list leaves budget
resources disabled; the default amount is not a billing limit. Set recipients
deliberately before deployment. A null start date selects the first-apply month
and remains stable; specify a date only when the budget requires it.

The baseline uses the same small VM sizes across profiles. Production-like
controls do not imply production-sized capacity, high availability, or a
production migration guarantee.

Shutdown scheduling can interrupt a long migration. Choose a suitable session
window or review the profile's `auto_shutdown_time` before starting. Stopped
VMs still have chargeable disks and supporting resources.

## Isolate environments

Each profile has its own work directory, state files, journal, and resource
naming. Keep the selected environment consistent across all commands. Do not
copy one environment's journal or manifest into another to bypass setup.

A profile change is an infrastructure change. Read the plan for replacement,
role, network, and cost effects before applying it to an in-progress migration.

## Related pages

- [Costs](costs.md)
- [State and secrets](state-and-secrets.md)
- [Configuration flow](../architecture/configuration-flow.md)
