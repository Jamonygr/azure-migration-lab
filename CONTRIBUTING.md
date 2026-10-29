# Contributing

Keep the lab understandable, reproducible, and honest about what it verifies.
A migration capability includes its source assumptions, working commands,
validation evidence, failure recovery, and cleanup.

## Change workflow

1. Work on a branch. Explain the learner-visible behavior in the pull request.
2. Update implementation and its scenario/reference documentation together.
3. Run the repository's static checks and relevant offline tests.
4. Report separately whether live Azure testing was run, on which profile,
   and whether cleanup completed.
5. Review the diff for state, credentials, tokens, customer data, and generated
   evidence before committing.

Use the version declared in `.terraform-version` and the checked-in provider
locks. Update dependency pins deliberately and regenerate references whenever
Terraform inputs or outputs change. Public interfaces include CLI stage names,
confirmation phrases, stack outputs, evidence formats, and application endpoints.

## Documentation

Pages live in `wiki/`; reusable decision records live in `docs/templates/`.
Use a page-specific banner, short explanations, executable PowerShell examples,
expected results, and links to related pages. Diagram nodes and arrows must
match actual infrastructure. Keep source simulation, assessment, application
rehosting, data migration, and VM replication distinct.

Never document a fabricated successful run. Record blocked or untested steps
with their reason and the next verification needed.

## Validation and security

Use [the testing guide](wiki/testing/lab-testing-guide.md). Exercise positive
and negative state transitions when changing migration stages. A test that
only confirms a helper function exists does not validate a migration.

Add narrow, justified scanner exceptions only when the lab requires them.
Document the affected resource, compensating control, owner, and review date
in [SECURITY_EXCEPTIONS.md](SECURITY_EXCEPTIONS.md).

Treat changes to cutover, acceptance, source retirement, and destroy as
lifecycle changes: verify stale evidence rejection, failed-operation recovery,
and correct resource ownership across state files.
