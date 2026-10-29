# Migrate and verify file content

<p align="center">
  <img src="../images/cinematic/file-migration.png" alt="Files streaming from a source share into cloud storage" width="1000" />
</p>

*Transfer the sample files and verify their paths, counts, and content at the destination.*

## Objective

Transfer the demonstration share's contents to Azure Files and prove that the
expected paths and bytes arrived.

The source exposes a local folder as an SMB share. The baseline transfer uses
guest-side access directly to Azure Files through OAuth REST. No storage account
key is required and file payloads do not pass through blob staging.

## What the comparison means

| Check | Detects |
|---|---|
| Relative path set | Missing or extra files |
| File length | Truncation or unexpected replacement |
| SHA-256 content hash | Changes that retain the same filename and size |
| Preserved last-write timestamp | Unexpected metadata change in supported sample files |
| Transfer result | Failed API operations and incomplete work |

A file-count match is insufficient. Preserve the source and target manifests
with the migration run that produced them.

## What is outside this scenario

The content-copy path does not claim to preserve NTFS owner, ACL inheritance,
share permissions, alternate data streams, open-file locks, or application
semantics for a writable file share. Azure Files privileged OAuth access
bypasses ordinary file ACL checks. An SMB permissions migration must be tested
separately with the intended identity and client protocol.

## Run and inspect

~~~powershell
./scripts/Invoke-Lab.ps1 -Stage Rehearse @lab
./scripts/Invoke-Lab.ps1 -Stage Reset-Target @lab -ConfirmAction 'RESET TARGET cheap-lab'
./scripts/Invoke-Lab.ps1 -Stage Migrate @lab
./scripts/Invoke-Lab.ps1 -Stage Validate @lab
~~~

Inspect file manifests and mismatch details. Keep the source dataset stable
during the final-copy window. If a file changes between source manifest creation
and transfer, repeat the migration after resolving the writer.

## Failure exercise

In a disposable rehearsal, change one target file or remove it, then validate
again. Expected: the content comparison fails and cutover remains blocked.
Restore by a supported reset/rehearsal path; do not edit the manifest to fit the
damaged target.

## Deliverable

A path-and-hash comparison with no unexplained mismatches, plus a short note
explaining why that does not prove SMB identity compatibility.

## Related pages

- [Security model](../architecture/security-model.md)
- [Acceptance record](../../docs/templates/acceptance.md)
