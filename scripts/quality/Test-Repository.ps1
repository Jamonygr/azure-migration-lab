[CmdletBinding()]
param([switch]$SkipSecurity, [string]$DotNet = 'dotnet')
$ErrorActionPreference='Stop'
$repo=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Push-Location $repo
function Run([string]$Tool,[string[]]$Arguments){
    Write-Host "> $Tool $($Arguments -join ' ')"
    & $Tool @Arguments
    if($LASTEXITCODE -ne 0){throw "$Tool failed ($LASTEXITCODE)"}
}
try {
    Run terraform @('fmt','-check','-recursive','modules','stacks','environments')
    foreach($stack in @('foundation','source','target','cutover')){
        Run terraform @("-chdir=stacks/$stack",'init','-backend=false','-lockfile=readonly','-input=false')
        Run terraform @("-chdir=stacks/$stack",'validate')
        Run terraform @("-chdir=stacks/$stack",'test','-no-color')
    }
    Run tflint @('--init',"--config=$repo/.tflint.hcl")
    Run tflint @('--recursive',"--config=$repo/.tflint.hcl")
    Run conftest @('verify','--policy','policies')
    Run node @('scripts/quality/Test-Documentation.mjs')
    & "$PSScriptRoot/Update-TerraformDocs.ps1" -Check
    $parseErrors=@()
    Get-ChildItem scripts,tests -Recurse -File | Where-Object {$_.Extension -in '.ps1','.psm1'} | ForEach-Object {
        $tokens=$null;$errors=$null
        $null=[Management.Automation.Language.Parser]::ParseFile($_.FullName,[ref]$tokens,[ref]$errors)
        $parseErrors+=@($errors)
    }
    if($parseErrors.Count){throw ($parseErrors|Out-String)}
    Import-Module Pester -MinimumVersion 5.7.1
    $pester=Invoke-Pester -Path tests/powershell,tests/quality -PassThru -Output Detailed
    if($pester.FailedCount -gt 0 -or $pester.PassedCount -eq 0){throw 'PowerShell tests failed or none ran.'}
    Run $DotNet @('restore','app/MigrationLab/MigrationLab.csproj','--locked-mode')
    Run $DotNet @('build','app/MigrationLab/MigrationLab.csproj','-c','Release','--no-restore')
    & "$repo/tests/application/Test-Application.ps1" -DotNet $DotNet
    Run actionlint @('-color')
    if(-not $SkipSecurity){
        Run trivy @('config','--severity','MEDIUM,HIGH,CRITICAL','--exit-code','1','--ignorefile','.trivyignore.yaml','--skip-dirs','work,.git','.')
        Run checkov @('-d','.','--framework','terraform','github_actions','--skip-path','[\\/]work[\\/]','--compact')
        Run gitleaks @('dir','.','--redact','--no-banner','--config','.gitleaks.toml')
    }else{Write-Warning 'Security scanners explicitly skipped; this is not the full validation gate.'}
} finally { Pop-Location }
