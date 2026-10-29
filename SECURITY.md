# Security policy

Use synthetic catalog records and demonstration documents only. The repository
is a learning environment and has not been certified for production use.

## Reporting a concern

For a credential exposure, revoke the credential immediately and remove it
from local evidence. Do not include tokens, state files, subscription details,
or private application data in a public issue. Use a private reporting channel
available on the hosting repository; if one is unavailable, contact the
repository owner privately.

For non-sensitive defects, report the affected commit, profile, expected
control, observed behavior, and a redacted reproduction.

## Security model

- Azure CLI identities administer infrastructure; managed identities perform
  guest application and migration access.
- Azure SQL uses Microsoft Entra authentication. Migration administration and
  the target application's database permissions are separate.
- SQL, Storage, and Key Vault data access use private networking.
- Lab VM public IPs in smaller profiles provide explicit egress. They are not
  permission to expose HTTP, RDP, SQL, or SMB to the internet.
- Local state contains administrative passwords. Protect it as a credential,
  including backups and CI artifacts.
- The write fence and lifecycle journal protect the migration exercise.
  They do not replace production transaction controls or immutable audit logs.

See [Security model](wiki/architecture/security-model.md) and
[State and secrets](wiki/reference/state-and-secrets.md).
