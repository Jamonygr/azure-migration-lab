# Validation record — 29 October 2026

<p align="center">
  <img src="../images/cinematic/rehearsal-validation.png" alt="Cinematic rehearsal and validation checkpoint" width="1000" />
</p>

*Track local checks and live migration evidence separately; artwork does not indicate a completed Azure run.*

## Local validation completed

The complete local quality gate passed on 29 October 2026. The initial
repository was authored and tested locally; a successful live Azure migration
is **not claimed**. The initial delivery commit is `ec856ea`.

| Validation area | Status | Evidence |
|---|---|---|
| Terraform formatting, initialization and validation | Passed | All four stacks; Terraform 1.15.8; AzureRM 4.57.0 and Random 3.6.3 locked |
| Terraform mocked tests | Passed | 19 tests: foundation 11, source 3, target 2, cutover 3 |
| TFLint and workflow syntax | Passed | TFLint 0.65.0, actionlint 1.7.12; shared profile variables intentionally exempt from unused-variable lint |
| PowerShell parsing and offline tests | Passed | 32 Pester tests; actual Windows PowerShell 5.1 guest syntax check and PowerShell 7 host parsing |
| Application build/tests | Passed | .NET SDK 10.0.403; locked NuGet restore; zero build warnings/errors; 11 application integration checks using the explicit test store |
| Browser behavior | Passed locally | Desktop/mobile rendering, three sample records, disabled write button during acceptance, no overflow or JavaScript errors; test store only |
| Documentation links and SVG structure | Passed | All local links including anchors and HTML images; 35 SVGs rendered with no text outside their viewboxes; diagrams and dashboard visually reviewed |
| Generated Terraform references | Passed | 12 module/stack references checked with terraform-docs 0.24.0 |
| Policy tests | Passed | Conftest 0.71.1: six allow/deny cases covering private services, shared keys, inbound rules, production public NICs, and teardown |
| Trivy configuration scan | Passed with scoped exceptions | Trivy 0.76.1: no unsuppressed MEDIUM/HIGH/CRITICAL findings; two rule exceptions limited to named files |
| Checkov infrastructure/workflow scans | Passed with scoped exceptions | Checkov 3.4.0: 106 passed, zero failed, 17 explicit resource/workflow exceptions |
| Secret scan | Passed | Gitleaks 8.30.1: no leaks detected in the local source tree |
| Azure provisioning | Not run | No live deployment evidence |
| Guest bootstrap and identity access | Not run | Requires disposable Azure run |
| SQL and file migration | Not run | Requires live comparison evidence |
| Cutover and rollback | Not run | Requires private DNS/application checks |
| Acceptance and source retirement | Not run | Requires complete lifecycle run |
| Azure teardown | Not run | No deployment created by the initial package |

## Cinematic artwork update — 29 October 2026

Added 12 PNG illustrations, updated the README and all 29 existing wiki chapter
covers, and added a visual gallery. This update changes documentation and
artwork only; the infrastructure, migration scripts, and application are unchanged.

| Validation area | Status | Evidence |
|---|---|---|
| Image decoding and dimensions | Passed | All 12 PNGs fully decoded; each is 1672 × 941 pixels; 30.63 MiB combined |
| Visual review | Passed | All titles checked for spelling, legibility, safe margins, and consistent cyan/violet/chrome styling |
| Documentation links | Passed | `node scripts/quality/Test-Documentation.mjs`; local links, anchors, and image references resolve; original 35 SVGs retained |
| Documentation preview | Passed locally | README, visual gallery, and SQL chapter rendered in Edge at desktop and mobile widths; no broken local images or page overflow |
| Whitespace check | Passed | `git diff --check` |
| Infrastructure/application/cloud checks | Not run for this update | Artwork-only scope; original package results and live-validation limitations remain as recorded above |

Preview screenshots and the image metadata report are in the ignored
`work/visual-cinematic/` folder. These local previews do not assert a published
GitHub rendering or a live Azure deployment.

## Reproduce the package checks

Run the [quality gate](lab-testing-guide.md) from the repository root:

~~~powershell
./scripts/quality/Test-Repository.ps1
~~~

The validating session used a task-local .NET SDK and Python environment without
changing the project to depend on those machine-specific paths. Runtime logs
remain in the ignored `work/full-validation-final.log` and `work/visual/`
directories. The browser snapshots use an in-memory test store; they do not
establish SQL connectivity, managed-identity permissions, or successful Azure
migration. Scanner exceptions and their compensating controls are listed in the
[exception register](../../SECURITY_EXCEPTIONS.md).

Local tests specifically cover partial-apply recovery, exact destruction
confirmations, stale validation rejection, mandatory reset after rehearsal,
the post-acceptance rollback boundary, quota-aware retries, failed guest results,
and checkpoint command failures. Cloud-only behaviors still require the opt-in
live harness and its dated evidence.

## How to update this record

For each executed check, record timestamp, commit, profile, exact command,
result, and the private evidence location or a redacted summary. Keep failed
checks visible with their disposition. Static-only changes must not change
live rows to passed.

A later live record should include elapsed migration time, tested data volume,
observed downtime, remaining limitations, and final resource cleanup.
