# GitHub Actions and state setup

The local repository is usable before it is published. The workflows become available after you create a GitHub repository and push this project. No workflow deploys Azure resources on a pull request or ordinary push.

## Credential-free checks

`Validate` runs on pull requests, pushes to `main`, and manual dispatch. It has only `contents: read`. It runs the same `scripts/quality/Test-Repository.ps1` entry point used locally, including provider-mocked Terraform tests. It never obtains an Azure identity token. Tool archives are pinned and verified against publisher checksums; action references are pinned to commits.

## Bootstrap a separate state account

Create a state resource group, StorageV2 account, and private blob container outside this lab's four Terraform states. Use a globally unique account name. Configure HTTPS, TLS 1.2+, disabled anonymous access, disabled shared-key access, blob versioning, container and blob soft delete, and a delete lock on the account. The operator and workflow identities need **Storage Blob Data Contributor** scoped to the state container.

The state account must be reachable from the selected runner. Hosted runners require a reachable authenticated blob endpoint; a private endpoint requires a self-hosted runner with the appropriate network and DNS access. Do not enable account keys to work around connectivity failures. State contains generated VM passwords even though the CLI manifests do not expose them.

Use a dedicated state account for this project. Never pass the lab's private migration artifact account as the backend: it is created after backend initialization and is destroyed with the lab.

## Register resource providers once

Before using a read-only planning identity, have a subscription administrator register `Microsoft.Compute`, `Microsoft.Network`, `Microsoft.Storage`, `Microsoft.KeyVault`, `Microsoft.Sql`, `Microsoft.OperationalInsights`, `Microsoft.Insights`, `Microsoft.ManagedIdentity`, and `Microsoft.DevTestLab`. Profiles with backup also require `Microsoft.RecoveryServices`; configured budget recipients require `Microsoft.Consumption`.

Use `az provider register --namespace <namespace> --subscription <subscription-id> --wait` for each required namespace during subscription setup. The lab preflight checks registration; Terraform automatic provider registration is disabled so a plan does not attempt subscription changes. Registration is separate from creating the lab's resources.

## Configure federated identities and environments

For each selected profile (`cheap-lab`, `dev`, `lab`, `prod`), create these GitHub environments:

| Environment | Purpose | Azure access |
| --- | --- | --- |
| `<profile>-plan` | Saved read-only infrastructure plan | Resource Reader plus state container data access |
| `<profile>-apply` | Provisioning and migration stages | Contributor on the disposable lab scope; narrowly scoped RBAC assignment administration as described below |
| `<profile>-destroy` | Explicit teardown | Resource deletion rights on the lab scope plus state data access |

Restrict each environment to the protected `main` branch. Require reviewers for `apply` and `destroy`, prevent self-review where supported, and disable administrator bypass if appropriate. Apply branch protection and required `Validate` status checks to `main`. The workflow also rejects dispatch from other branches.

Create an Entra application/service principal or user-assigned managed identity for each permission boundary. Add a GitHub OIDC federated credential with audience `api://AzureADTokenExchange`, issuer `https://token.actions.githubusercontent.com`, and subject `repo:OWNER/REPOSITORY:environment:ENVIRONMENT`. Set `OWNER/REPOSITORY` to the eventual destination repository, not an unrelated reference lab.

Provisioning creates resource groups, identities, role assignments, and optional custom policy definitions. Contributor alone cannot assign roles. Use an appropriately scoped **Role Based Access Control Administrator** assignment with delegation conditions for only the roles used by this lab; a disposable subscription can simplify the training setup. Document the assigned scope. State permissions do not grant deployment or guest Run Command permissions.

Add these GitHub **environment variables** (they identify resources; no client secrets are required):

| Variable | Value |
| --- | --- |
| `AZURE_CLIENT_ID` | Federated application or managed identity client ID |
| `AZURE_TENANT_ID` | Tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Authorized lab subscription ID |
| `LAB_OWNER` | Owner tag value |
| `STATE_RESOURCE_GROUP` | Backend resource group |
| `STATE_STORAGE_ACCOUNT` | Backend account name |
| `STATE_CONTAINER` | Existing private container, normally `tfstate` |

## Run a migration

Open the **Migration lab** workflow and select the profile and stage. `Plan` also accepts the selected stack. Plan `foundation` first; other stacks require prerequisite manifests from a successful `Provision` or earlier staged deployment. A complete first deployment uses `Provision`, which plans and applies each stack in dependency order. Review plan output and environment configuration before dispatching that operation.

Continue with `Seed`, `Discover`, `Assess-Export`, and the [scenario workbook](../wiki/scenarios/README.md). The workflow never treats a skipped assessment portal exercise as a completed assessment.

Destructive stages require the exact `ConfirmAction` text described in the [CLI guide](../wiki/reference/commands.md). The workflow passes the confirmation as an environment variable, not interpolated shell code. Acceptance requires a deliberate stage invocation and valid migration evidence. A GitHub environment approval does not bypass the script's migration state checks.

## Checkpoints and recovery

Terraform uses Azure blob leases and independent keys under `azure-migration-lab/<profile>/`. GitHub concurrency serializes all workflow stages for the same profile without canceling a running migration.

The workflow also downloads and uploads `azure-migration-lab/<profile>/checkpoint.zip` in the protected backend container. This archive contains only the journal, resource manifests, and inventory JSON. It preserves migration state across fresh runners. Terraform states, plans, database exports, guest packages, and secrets are never uploaded as public workflow artifacts. Blob versioning preserves prior checkpoints.

On failure, inspect the failing stage and checkpoint before retrying. A target containing imported SQL objects must be reset through `Reset-Target`; it is never dropped automatically. Do not run local and GitHub operations concurrently against the same profile. Local operators using remote state must also use the same checkpoint, with `scripts/quality/Sync-LabCheckpoint.ps1`, to avoid conflicting migration journals.

After teardown, retain the backend and its protected evidence until the run is reviewed. Its lifecycle is deliberately independent of the lab.
