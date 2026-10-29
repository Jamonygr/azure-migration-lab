#Requires -Version 7.2
[CmdletBinding()]
param(
    [Parameter(Mandatory)][guid]$SubscriptionId,
    [Parameter(Mandatory)][string]$Owner,
    [Parameter(Mandatory)][switch]$Execute,
    [switch]$KeepResources
)
$ErrorActionPreference='Stop'
if(!$Execute){throw 'Live validation creates billable Azure resources. Explicitly supply -Execute to run it.'}
$repo=Split-Path -Parent $PSScriptRoot
$journal=Join-Path $repo 'work/cheap-lab/journal.json'
if(Test-Path -LiteralPath $journal){throw 'Live validation requires a fresh cheap-lab workspace. Preserve prior evidence and use a separate checkout for a new run.'}
$invoke=Join-Path $PSScriptRoot 'Invoke-Lab.ps1'
$common=@{Environment='cheap-lab';SubscriptionId=$SubscriptionId;Owner=$Owner}
$started=$false
try {
    & $invoke @common -Stage preflight
    $started=$true
    foreach($stage in @('provision','seed','discover','assess-export','rehearse')){& $invoke @common -Stage $stage}
    & $invoke @common -Stage reset-target -ConfirmAction 'RESET TARGET cheap-lab'
    foreach($stage in @('migrate','validate','cutover','rollback')){& $invoke @common -Stage $stage}
    & $invoke @common -Stage reset-target -ConfirmAction 'RESET TARGET cheap-lab'
    foreach($stage in @('migrate','validate','cutover','accept')){& $invoke @common -Stage $stage}
    & $invoke @common -Stage retire-source -ConfirmAction 'RETIRE SOURCE cheap-lab'
} finally {
    if($started -and !$KeepResources){
        & $invoke @common -Stage destroy -ConfirmAction 'DESTROY cheap-lab'
    }
}
Write-Host 'Live validation completed; inspect work/cheap-lab/evidence for individual infrastructure and data checks.'
