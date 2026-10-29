# Workload dependency map

- Workload / date:
- Discovery evidence:
- Author:

| Caller | Destination | Purpose | Protocol/port | Identity | Runtime or migration | Verification |
|---|---|---|---|---|---|---|
| Client | Logical application name | | | | Runtime | |
| IIS | Database | | | | Runtime | |
| Migration guest | Staging | | | | Migration | |
| Migration guest | Azure SQL | | | | Migration | |
| Migration guest | Azure Files | | | | Migration | |

## Diagram

Add a source/target flow diagram with private network boundaries. Show DNS and
identity dependencies as well as data paths.

## Hidden writers and readers

Scheduled tasks:
Background jobs:
External file clients:
Integrations:
Monitoring/backup dependencies:

## Migration consequence

Dependencies that must move together:
Dependencies that can remain on source:
Dependencies that prevent rollback after acceptance:
