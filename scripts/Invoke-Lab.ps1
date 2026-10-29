#Requires -Version 7.2
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('preflight','plan','provision','seed','discover','assess-export','rehearse','reset-target','migrate','validate','cutover','rollback','accept','retire-source','destroy')][string]$Stage,
    [ValidateSet('foundation','source','target','cutover')][string]$Stack = 'foundation',
    [ValidateSet('cheap-lab','dev','lab','prod')][string]$Environment = 'cheap-lab',
    [Parameter(Mandatory)][guid]$SubscriptionId,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Owner,
    [string]$ConfirmAction,
    [string]$BackendResourceGroup,
    [string]$BackendStorageAccount,
    [string]$BackendContainer = 'tfstate',
    [switch]$PlanOnly
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'migration/Lab.Core.psm1') -Force
$repo = Split-Path -Parent $PSScriptRoot
$work = Join-Path $repo "work/$Environment"
$journalPath = Join-Path $work 'journal.json'
$manifestDir = Join-Path $work 'manifests'
$run = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssfffZ') + '-' + ([guid]::NewGuid().ToString('N').Substring(0,8))
$evidence = Join-Path $work "evidence/$run-$Stage"
[IO.Directory]::CreateDirectory($evidence) | Out-Null
[IO.Directory]::CreateDirectory($manifestDir) | Out-Null
if ($Stage -eq 'destroy') { Assert-LabConfirmation $ConfirmAction "DESTROY $Environment" }
if ($Stage -eq 'reset-target') { Assert-LabConfirmation $ConfirmAction "RESET TARGET $Environment" }
if ($Stage -eq 'retire-source') { Assert-LabConfirmation $ConfirmAction "RETIRE SOURCE $Environment" }
if ($Stage -eq 'plan') { $PlanOnly = $true }
if ($PlanOnly -and $Stage -notin @('provision','plan')) { throw '-PlanOnly applies to provision/plan only.' }

function Read-Manifest([string]$Name) { Read-LabJson (Join-Path $manifestDir "$Name.json") }
function Set-Status([string]$Status) {
    $journal.status = $Status
    $journal.history = @($journal.history) + @{stage=$Stage;status=$Status;run=$run;utc=[DateTime]::UtcNow.ToString('o');evidence=$evidence}
    Write-LabJson $journal $journalPath
}
function Invoke-Tf([string]$Stack,[ValidateSet('apply','destroy','output')][string]$Operation='apply',[hashtable]$Extra=@{}) {
    $sandbox = Join-Path $work 'terraform'
    $stackPath = Join-Path $sandbox "stacks/$Stack"
    [IO.Directory]::CreateDirectory($stackPath) | Out-Null
    [IO.Directory]::CreateDirectory((Join-Path $work 'state')) | Out-Null
    # Only copy source files; never copy an initialized backend or someone else's state.
    Copy-Item -LiteralPath (Join-Path $repo 'modules') -Destination $sandbox -Recurse -Force
    Get-ChildItem -LiteralPath (Join-Path $repo "stacks/$Stack") -File | Where-Object { $_.Name -match '\.tf$|^\.terraform\.lock\.hcl$' } | Copy-Item -Destination $stackPath -Force
    $vars = @{subscription_id=$SubscriptionId.ToString();owner=$Owner}
    foreach ($key in $Extra.Keys) { $vars[$key]=$Extra[$key] }
    if ($Stack -ne 'foundation') { $vars.foundation_manifest = Read-Manifest 'foundation' }
    if ($Stack -eq 'cutover') { $vars.source_manifest = Read-Manifest 'source' }
    if ($Stack -eq 'cutover') { $vars.target_manifest = Read-Manifest 'target' }
    Write-LabJson $vars (Join-Path $stackPath 'runtime.auto.tfvars.json')
    $init = @("-chdir=$stackPath",'init','-input=false','-reconfigure')
    $override = Join-Path $stackPath 'backend_override.tf'
    if ($BackendStorageAccount) {
        if (!$BackendResourceGroup) { throw 'BackendResourceGroup is required with BackendStorageAccount.' }
        [IO.File]::WriteAllText($override, (Get-LabBackendConfiguration azurerm))
        $init += @("-backend-config=resource_group_name=$BackendResourceGroup","-backend-config=storage_account_name=$BackendStorageAccount","-backend-config=container_name=$BackendContainer","-backend-config=key=azure-migration-lab/$Environment/$Stack.tfstate",'-backend-config=use_azuread_auth=true')
    } else {
        [IO.File]::WriteAllText($override, (Get-LabBackendConfiguration local))
        $init += "-backend-config=path=$((Join-Path $work "state/$Stack.tfstate") -replace '\\','/')"
    }
    Invoke-LabNative terraform $init (Join-Path $evidence "$Stack-init.log") | Out-Null
    if ($Operation -ne 'output') {
        $plan = Join-Path $evidence "$Stack.tfplan"
        $args = @("-chdir=$stackPath",'plan','-input=false',"-var-file=$(Join-Path $repo "environments/$Environment.tfvars")","-var-file=$(Join-Path $stackPath 'runtime.auto.tfvars.json')","-out=$plan")
        if ($Operation -eq 'destroy') { $args += '-destroy' }
        $humanPlan=Invoke-LabNative terraform $args (Join-Path $evidence "$Stack-plan.log")
        # Terraform's human plan masks sensitive values; the native boundary also redacts credentials.
        # Keep the machine-readable plan private, but make the reviewable plan visible in CI logs.
        Write-Host $humanPlan
        $policyFile=Join-Path $evidence "$Stack-plan.json"
        [IO.File]::WriteAllText($policyFile,(Invoke-LabNative terraform @("-chdir=$stackPath",'show','-json',$plan)))
        if(Get-Command conftest -ErrorAction SilentlyContinue){
            Invoke-LabNative conftest @('test',$policyFile,'-p',(Join-Path $repo 'policies')) (Join-Path $evidence "$Stack-policy.log") | Out-Null
        }elseif($BackendStorageAccount){throw 'Remote apply/plan requires conftest. Install the pinned CI tool before proceeding.'}
        else{Write-Warning 'Conftest is unavailable; local policy gate was not run. Review the plan before deployment.'}
        if ($PlanOnly) { Write-Host "Saved $Stack plan: $plan"; return }
        if(!$journal.ContainsKey('started_stacks')){$journal.started_stacks=@()}
        if($Operation -eq 'apply' -and $Stack -notin $journal.started_stacks){$journal.started_stacks=@($journal.started_stacks)+$Stack}
        # Persist before the first create: remote CI can recover partial applies without output manifests.
        Write-LabJson $journal $journalPath
        Invoke-LabNative terraform @("-chdir=$stackPath",'apply','-input=false',$plan) (Join-Path $evidence "$Stack-apply.log") | Out-Null
    }
    if ($Operation -ne 'destroy') {
        $m = Invoke-LabNative terraform @("-chdir=$stackPath",'output','-json','manifest') | ConvertFrom-Json -AsHashtable
        Write-LabJson $m (Join-Path $manifestDir "$Stack.json")
    } else {
        $remaining=''
        try{$remaining=Invoke-LabNative terraform @("-chdir=$stackPath",'state','list')}
        catch{if($_.Exception.Message -notmatch 'No state file was found'){throw}}
        if($remaining.Trim()){throw "Terraform state is not empty after destroying $Stack."}
    }
}
function Invoke-Guest([string]$Role,[string]$Action,[hashtable]$Extra=@{}) {
    $f = Read-Manifest 'foundation'
    $vm = Read-Manifest $Role
    $ctx = @{foundation=$f;vm=$vm;role=$Role;action=$Action;run_id=$run}
    foreach ($n in @('source','target')) { $p=Join-Path $manifestDir "$n.json"; if (Test-Path -LiteralPath $p) { $ctx[$n]=Read-LabJson $p } }
    foreach ($key in $Extra.Keys) { $ctx[$key]=$Extra[$key] }
    $json = $ctx | ConvertTo-Json -Depth 20 -Compress
    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json))
    $scriptText = "`$Context = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$encoded')) | ConvertFrom-Json`n" + (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'guest/Invoke-Guest.ps1') -Raw)
    if ([Text.Encoding]::UTF8.GetByteCount($scriptText) -gt 65536) { throw 'Guest command payload exceeds the 64 KiB lab payload limit. Keep the sample source small.' }
    $guestPath = Join-Path $evidence "$Role-$Action.ps1"
    [IO.File]::WriteAllText($guestPath,$scriptText)
    $raw = Invoke-LabNative az @('vm','run-command','invoke','--subscription',$SubscriptionId.ToString(),'--ids',$vm.vm_id,'--command-id','RunPowerShellScript','--scripts',"@$guestPath",'--output','json','--only-show-errors') (Join-Path $evidence "$Role-$Action-response.json")
    $result = Get-LabGuestResult $raw
    Write-LabJson $result (Join-Path $evidence "$Role-$Action.json")
    return $result
}
function New-SourceArchive {
    $sourceDir = Join-Path $repo 'app/MigrationLab'
    $zip = Join-Path $evidence 'app-source.zip'
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::Open($zip,'Create')
    try {
        Get-ChildItem -LiteralPath $sourceDir -Recurse -File | Where-Object { $_.FullName -notmatch '[\\/](bin|obj)[\\/]' -and $_.Extension -in @('.cs','.csproj','.json','.config','.css','.html') } | ForEach-Object {
            $relative=[IO.Path]::GetRelativePath($sourceDir,$_.FullName) -replace '\\','/'
            [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive,$_.FullName,$relative) | Out-Null
        }
    } finally { $archive.Dispose() }
    if ((Get-Item -LiteralPath $zip).Length -gt 15000) { throw 'Sample source archive is too large for the embedded bootstrap channel.' }
    return [Convert]::ToBase64String([IO.File]::ReadAllBytes($zip))
}
function Test-Preflight {
    foreach ($tool in @('az','terraform')) { if (!(Get-Command $tool -ErrorAction SilentlyContinue)) { throw "Install required tool: $tool" } }
    $account=Invoke-LabNative az @('account','show','--subscription',$SubscriptionId.ToString(),'-o','json') | ConvertFrom-Json -AsHashtable
    if ($account.id -ne $SubscriptionId.ToString()) { throw 'Azure subscription mismatch.' }
    $profile=Get-Content -LiteralPath (Join-Path $repo "environments/$Environment.tfvars") -Raw
    $requiredProviders=@('Microsoft.Compute','Microsoft.Network','Microsoft.Storage','Microsoft.KeyVault','Microsoft.Sql','Microsoft.OperationalInsights','Microsoft.Insights','Microsoft.ManagedIdentity','Microsoft.DevTestLab')
    if($profile -match '(?m)^enable_backup\s*=\s*true'){$requiredProviders+='Microsoft.RecoveryServices'}
    if($profile -match '(?m)^budget_emails\s*=\s*\[\s*"'){$requiredProviders+='Microsoft.Consumption'}
    $providers=Invoke-LabNative az @('provider','list','--subscription',$SubscriptionId.ToString(),'--query','[].{namespace:namespace,state:registrationState}','-o','json') | ConvertFrom-Json -AsHashtable
    $missing=@($requiredProviders|Where-Object {$namespace=$_;!@($providers|Where-Object {$_.namespace -eq $namespace -and $_.state -eq 'Registered'}).Count})
    if($missing.Count){throw "Subscription providers require one-time owner setup: $($missing -join ', '). Run az provider register --namespace <namespace> --subscription $SubscriptionId --wait for each, then retry. Preflight makes no registration changes."}
    $project=[regex]::Match($profile,'(?m)^project\s*=\s*"([^"]+)"').Groups[1].Value
    if(!$project){$project='azmig'}
    $location=[regex]::Match($profile,'(?m)^location\s*=\s*"([^"]+)"').Groups[1].Value
    if (!$location) { $location='westeurope' }
    $all=Invoke-LabNative az @('vm','list-skus','--subscription',$SubscriptionId.ToString(),'--location',$location,'--resource-type','virtualMachines','--all','-o','json') | ConvertFrom-Json -AsHashtable
    $usage=Invoke-LabNative az @('vm','list-usage','--subscription',$SubscriptionId.ToString(),'--location',$location,'-o','json') | ConvertFrom-Json -AsHashtable
    $existing=Invoke-LabNative az @('vm','list','--subscription',$SubscriptionId.ToString(),'--query','[].{id:id,size:hardwareProfile.vmSize,location:location}','-o','json') | ConvertFrom-Json -AsHashtable
    $requested=@{}; $total=0
    foreach ($name in @('source_vm_size','target_vm_size')) {
        $size=[regex]::Match($profile,"(?m)^$name\s*=\s*`"([^`"]+)`"").Groups[1].Value
        if (!$size) { $size=if($name -eq 'source_vm_size'){'Standard_B2ms'}else{'Standard_B2s'} }
        $sku=@($all | Where-Object { $_.name -eq $size }) | Select-Object -First 1
        if (!$sku -or @($sku.restrictions | Where-Object {$_.type -eq 'Location'}).Count) { throw "$size is unavailable in $location. Choose an explicit profile size; no automatic upgrade is performed." }
        if($profile -match '(?m)^enable_vm_encryption_at_host\s*=\s*true'){
            $capability=@($sku.capabilities | Where-Object {$_.name -eq 'EncryptionAtHostSupported'}) | Select-Object -First 1
            if(!$capability -or $capability.value -ine 'true'){throw "$size does not advertise encryption at host support. Choose a supported size explicitly."}
            $feature=Invoke-LabNative az @('feature','show','--subscription',$SubscriptionId.ToString(),'--namespace','Microsoft.Compute','--name','EncryptionAtHost','-o','json') | ConvertFrom-Json -AsHashtable
            if($feature.properties.state -ne 'Registered'){throw 'Microsoft.Compute/EncryptionAtHost feature must be registered before enabling host encryption.'}
        }
        $cores=[int](@($sku.capabilities | Where-Object {$_.name -eq 'vCPUs'})[0].value)
        if (!$requested.ContainsKey($sku.family)) { $requested[$sku.family]=0 }
        $requested[$sku.family]+=$cores; $total+=$cores
    }
    # Credit only VMs at this lab's exact expected ARM IDs. This also handles a partial
    # source/target apply whose VM exists before its output manifest was saved.
    foreach($role in @('source','target')){
        $id="/subscriptions/$SubscriptionId/resourceGroups/rg-$project-$Environment-$role/providers/Microsoft.Compute/virtualMachines/vm-$project-$Environment-$role"
        $vm=@($existing|Where-Object {$_.id -ieq $id -and $_.location -ieq $location})|Select-Object -First 1
        if(!$vm){continue}
        $oldSku=@($all|Where-Object {$_.name -eq $vm.size})|Select-Object -First 1
        if(!$oldSku){throw "Cannot determine allocated cores for existing lab VM $id."}
        $oldCores=[int](@($oldSku.capabilities|Where-Object {$_.name -eq 'vCPUs'})[0].value)
        if($requested.ContainsKey($oldSku.family)){$requested[$oldSku.family]=[math]::Max(0,$requested[$oldSku.family]-$oldCores)}
        $total-=$oldCores
    }
    $requested.cores=[math]::Max(0,$total)
    foreach ($family in $requested.Keys) {
        $quota=@($usage | Where-Object { $_.name.value -ieq $family }) | Select-Object -First 1
        if (!$quota) { throw "Could not establish available quota for $family in $location." }
        if ($quota.currentValue+$requested[$family] -gt $quota.limit) { throw "Insufficient $family quota in ${location}: need $($requested[$family]) additional cores." }
    }
    Write-LabJson @{subscription=$account.id;location=$location;requested_cores=$requested;checked_utc=[DateTime]::UtcNow.ToString('o')} (Join-Path $evidence 'preflight.json')
}
function Validate-CurrentMigration {
    $validation=Invoke-Guest source validate
    if($validation.migration_run -ne $journal.migration_run){throw 'Guest migration manifest does not match the current journal run.'}
    return $validation
}

# A per-environment exclusive lock prevents simultaneous journal/state changes.
$lock=$null
try {
    $lock=[IO.File]::Open((Join-Path $work 'run.lock'),'OpenOrCreate','ReadWrite','None')
    # Read only after taking the lock: a waiting invocation must not overwrite a newer journal.
    $journal = if (Test-Path -LiteralPath $journalPath) { Read-LabJson $journalPath } else { @{status='new';subscription_id=$SubscriptionId.ToString();environment=$Environment;history=@()} }
    if ($journal.subscription_id -ne $SubscriptionId.ToString() -or $journal.environment -ne $Environment) { throw 'Journal identity differs from requested subscription/environment.' }
    Assert-LabStage $Stage $journal
    Write-LabJson $journal $journalPath
    switch ($Stage) {
        preflight { Test-Preflight }
        plan { Invoke-Tf $Stack 'apply' $(if($Stack -eq 'cutover'){@{active_site=$(if($journal.status -in @('cutover','accepted','retired')){'target'}else{'source'})}}else{@{}}) }
        provision {
            Test-Preflight
            foreach ($s in @('foundation','source','target','cutover')) {
                if ($PlanOnly -and $s -ne 'foundation' -and !(Test-Path -LiteralPath (Join-Path $manifestDir 'foundation.json'))) { Write-Host 'Dependent stacks require the foundation outputs. Foundation plan is ready for review.'; break }
                Invoke-Tf $s 'apply' $(if($s -eq 'cutover'){@{active_site='source'}}else{@{}})
                if ($PlanOnly -and !(Test-Path -LiteralPath (Join-Path $manifestDir "$s.json"))) { break }
            }
            if (!$PlanOnly) { Set-Status 'provisioned' }
        }
        seed {
            Invoke-Guest source bootstrap @{app_source_zip=(New-SourceArchive)} | Out-Null
            Invoke-Guest target bootstrap | Out-Null
            Set-Status 'seeded'
        }
        discover {
            $inventory=Invoke-Guest source discover
            Write-LabJson $inventory.inventory (Join-Path $work 'inventory.json')
            Set-Status 'discovered'
        }
        'assess-export' {
            ConvertTo-LabMigrateCsv (Read-LabJson (Join-Path $work 'inventory.json')) (Join-Path $evidence 'azure-migrate-inventory.csv')
            Write-Host "Import $evidence/azure-migrate-inventory.csv using the Azure Migrate assessment guide. CSV records support assessment, not replication."
        }
        rehearse {
            Invoke-Guest source freeze | Out-Null
            try {
                Invoke-Guest source transfer | Out-Null
                Invoke-Guest target deploy | Out-Null
                Invoke-Guest source validate | Out-Null
            } finally { Invoke-Guest source unfreeze | Out-Null }
            Set-Status 'rehearsed'
        }
        'reset-target' {
            Invoke-Tf cutover apply @{active_site='source'}
            Invoke-Guest source unfreeze | Out-Null
            Invoke-Tf target destroy
            Invoke-Tf target apply
            Invoke-Guest target bootstrap | Out-Null
            # Azure Files lives in foundation; delete only this synthetic lab's explicitly named subtree.
            Invoke-Guest source resetfiles | Out-Null
            $journal.Remove('validation_run'); $journal.Remove('migration_run')
            Set-Status 'reset'
        }
        migrate {
            Invoke-Guest source freeze | Out-Null
            $journal.migration_run=$run
            $journal.Remove('validation_run')
            Write-LabJson $journal $journalPath
            Invoke-Guest source transfer | Out-Null
            Invoke-Guest target deploy | Out-Null
            Set-Status 'migrated'
        }
        validate {
            Validate-CurrentMigration | Out-Null
            $journal.validation_run=$journal.migration_run
            if($journal.status -ne 'cutover'){Set-Status 'validated'}else{Write-LabJson $journal $journalPath}
        }
        cutover {
            Validate-CurrentMigration | Out-Null
            Invoke-Tf cutover apply @{active_site='target'}
            Invoke-Guest source dns @{expected_ip=(Read-Manifest target).private_ip} | Out-Null
            Set-Status 'cutover'
        }
        rollback {
            Invoke-Tf cutover apply @{active_site='source'}
            Invoke-Guest source dns @{expected_ip=(Read-Manifest source).private_ip} | Out-Null
            Invoke-Guest source unfreeze | Out-Null
            $journal.Remove('validation_run')
            Set-Status 'rolled-back'
        }
        accept {
            if($journal.status -ne 'accepted'){
                Validate-CurrentMigration | Out-Null
                Invoke-Guest source grantwrites | Out-Null
                # Commit the irreversible boundary before lifting the final target write fence.
                Set-Status 'accepted'
            }
            Invoke-Guest target accept | Out-Null
        }
        'retire-source' { Invoke-Guest target ready | Out-Null; Invoke-Tf source destroy; Set-Status 'retired' }
        destroy {
            if(Test-Path -LiteralPath (Join-Path $manifestDir 'foundation.json')) {
                $f=Read-Manifest foundation
                # Assessment is intentionally portal-created. Delete only the owned disposable RG.
                $exists=Invoke-LabNative az @('group','exists','--name',$f.assessment_rg,'--subscription',$SubscriptionId.ToString())
                if($exists.Trim() -eq 'true'){
                    $rg=Invoke-LabNative az @('group','show','--name',$f.assessment_rg,'--subscription',$SubscriptionId.ToString(),'-o','json') | ConvertFrom-Json -AsHashtable
                    if ($rg.tags['Environment'] -ne $Environment -and $rg.tags['environment'] -ne $Environment) { throw 'Assessment RG environment tag does not match; refusing cleanup.' }
                    Invoke-LabNative az @('group','delete','--name',$f.assessment_rg,'--subscription',$SubscriptionId.ToString(),'--yes') | Out-Null
                }
            }
            foreach ($s in @('cutover','target','source','foundation')) {
                # A failed apply may have resources in state before any output manifest exists.
                $started=$journal.ContainsKey('started_stacks') -and $s -in $journal.started_stacks
                if($started -or (Test-Path -LiteralPath (Join-Path $manifestDir "$s.json")) -or (Test-Path -LiteralPath (Join-Path $work "terraform/stacks/$s/runtime.auto.tfvars.json"))) { Invoke-Tf $s destroy }
            }
            if(Test-Path -LiteralPath (Join-Path $manifestDir 'foundation.json')) {
                $f=Read-Manifest foundation
                foreach($rgName in @($f.source_rg,$f.target_rg,$f.shared_rg,$f.assessment_rg)) {
                    $exists=Invoke-LabNative az @('group','exists','--name',$rgName,'--subscription',$SubscriptionId.ToString())
                    if($exists.Trim() -ne 'false'){throw "Residual resource group remains: $rgName"}
                }
            }
            Set-Status 'destroyed'
        }
    }
    Write-Host "Stage '$Stage' completed. Evidence: $evidence"
} catch {
    Write-LabJson @{stage=$Stage;run=$run;status='failed';error=$_.Exception.Message;utc=[DateTime]::UtcNow.ToString('o')} (Join-Path $evidence 'failure.json')
    # Keep the last successful state: a failure never invents successful migration evidence.
    throw
} finally { if($lock){$lock.Dispose()} }
