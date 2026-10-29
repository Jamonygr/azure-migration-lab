# Lab security tradeoffs and exception register

These are documented lab design choices, not blanket scanner suppressions.
Any scanner-specific suppression must identify its resource and rule in code.

| Design choice | Purpose | Compensating control | Owner / review |
|---|---|---|---|
| Public IPs on cheap/dev/lab VMs for explicit egress | Avoid NAT cost in short learning sessions | Inbound NSG access denied by default; administration through Azure Run Command | Repository maintainer / 2027-01-29 |
| Local Terraform state for the initial workflow | Runnable lab without a pre-existing backend | Ignored work directory, restricted local access, no committed state or plan files | Repository maintainer / 2027-01-29 |
| Migration identity has SQL administrative privileges | Bootstrap schema and import demonstration data | Dedicated stable identity; application identity receives limited database permissions | Repository maintainer / 2027-01-29 |
| Azure Files privileged OAuth REST role for migration | Transfer and verify file content without account keys | Lab-only storage scope; no claim of SMB ACL preservation | Repository maintainer / 2027-01-29 |
| Small single-region instances and lab data | Keep the exercise affordable | No availability guarantee; reproducible seed and explicit teardown | Repository maintainer / 2027-01-29 |
| Backup vault soft delete disabled in lab/prod | Allow disposable backup teardown | Synthetic data only; seven daily recovery points while enabled; inspect cleanup | Repository maintainer / 2027-01-29 |
| Private IIS endpoint uses HTTP | Keep sample application setup small | Inbound internet access denied; synthetic content only; production requires TLS and certificate validation | Repository maintainer / 2027-01-29 |
| Local SQL Express trusts its self-signed certificate | Permit the source guest's local demonstration connection | Local source path only; Azure SQL target validates its server certificate | Repository maintainer / 2027-01-29 |
| Migration UAMI is attached to source VM | Run privileged transfer within the private network | Trusted synthetic host only; identity is not isolated from other processes on that VM | Repository maintainer / 2027-01-29 |

## Scoped scanner exceptions

Review date for every entry: **2027-01-29**. Owner: **repository maintainer**.
These apply only to the named file/resource. Remove an exception if its
justification no longer matches the implementation.

| Rule | Scope | Reason and compensating control |
|---|---|---|
| Trivy AZU-0016; Checkov CKV_AZURE_110, CKV_AZURE_42 | modules/keyvault/main.tf | Disposable vault permits purge; seven-day soft delete, private endpoint, RBAC and audit logs remain enabled |
| Trivy AZU-0068 | modules/windows-vm/main.tf | Module graph false positive: VM explicitly references its NIC; mocked root tests check wiring |
| Checkov CKV_AZURE_50 | modules/windows-vm/main.tf | VM extensions are needed for Azure Monitor and the management path; public management ports remain disabled by default |
| Checkov CKV_AZURE_151 | modules/windows-vm/main.tf | Host encryption is opt-in after SKU/subscription capability checks; disks retain platform encryption at rest |
| Checkov CKV2_AZURE_32 | modules/keyvault/main.tf | Foundation owns the vault private endpoint and DNS links; scanner cannot resolve cross-module for_each edges |
| Checkov CKV_AZURE_24 | modules/sql/main.tf | SQL auditing is enabled to 30-day Log Analytics; generic storage-audit 90-day retention does not match this lab destination |
| Checkov CKV2_AZURE_2 | modules/sql/main.tf | Paid Defender vulnerability assessment is outside baseline; SQL remains private, Entra-only, encrypted and audited |
| Checkov CKV_AZURE_224 | modules/sql/main.tf | Ledger would change the ordinary sample Catalog schema; integrity is checked with migration signatures |
| Checkov CKV_AZURE_229 | modules/sql/main.tf | Basic 2 GB single-region database is a deliberate lab tier; no zonal availability claim |
| Checkov CKV_AZURE_33 | modules/storage/main.tf | Queue storage is unused and shared keys disabled; used blob/file services emit diagnostics |
| Checkov CKV_AZURE_206 | modules/storage/main.tf | LRS holds disposable synthetic data; cross-region resilience is outside this exercise |
| Checkov CKV2_AZURE_1 | modules/storage/main.tf | Platform-managed encryption keys avoid a separate CMK lifecycle; access remains private and identity-based |
| Checkov CKV2_AZURE_33 | modules/storage/main.tf | Foundation creates blob/file private endpoints and DNS; scanner misses cross-module graph edges |
| Checkov CKV2_AZURE_21 | modules/storage/main.tf, artifacts container | Blob diagnostics collect read/write/delete events; for_each suffix is not resolved by scanner |
| Checkov CKV_GHA_7 | .github/workflows/lab.yml | Constrained manual inputs, protected main/environments, and argument-safe variable passing guard execution |

The `prod` profile demonstrates stronger network and operations settings.
Its name does not remove these limitations. See the
[hardening discussion](wiki/architecture/security-model.md).
