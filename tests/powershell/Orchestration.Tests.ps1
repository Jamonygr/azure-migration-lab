BeforeAll {
    $actualRepo=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $actualRepo 'scripts/migration/Lab.Core.psm1') -Force
    $tokens=$null;$errors=$null
    $hostAst=[System.Management.Automation.Language.Parser]::ParseFile((Join-Path $actualRepo 'scripts/Invoke-Lab.ps1'),[ref]$tokens,[ref]$errors)
    foreach($name in @('Invoke-Tf','Read-Manifest','Test-Preflight')){
        $fn=$hostAst.Find({param($node)$node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name},$true)
        . ([scriptblock]::Create($fn.Extent.Text))
    }
}

Describe 'Terraform host orchestration without Azure' {
    BeforeEach {
        $repo=$actualRepo
        $work=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $evidence=Join-Path $work 'evidence';$manifestDir=Join-Path $work 'manifests'
        New-Item -ItemType Directory -Path $evidence,$manifestDir -Force|Out-Null
        $journalPath=Join-Path $work 'journal.json'
        $Environment='cheap-lab';$Owner='Test Owner';$SubscriptionId=[guid]'11111111-1111-4111-8111-111111111111'
        $journal=@{status='new';subscription_id=$SubscriptionId.ToString();environment=$Environment;history=@()}
        $BackendStorageAccount=$null;$BackendResourceGroup=$null;$BackendContainer='tfstate';$PlanOnly=$false
        Mock Invoke-LabNative {
            param($File,$Arguments,$LogPath)
            if($Arguments -contains 'show'){return '{"resource_changes":[]}'}
            if($Arguments -contains 'output'){return '{"environment":"cheap-lab"}'}
            return ''
        }
    }
    It 'persists the started stack before a failed first apply can create an orphan' {
        Mock Invoke-LabNative {
            param($File,$Arguments,$LogPath)
            if($Arguments -contains 'show'){return '{"resource_changes":[]}'}
            if($Arguments -contains 'apply'){
                (Read-LabJson $journalPath).started_stacks|Should -Contain foundation
                throw 'Simulated partial provider failure'
            }
            return ''
        }
        {Invoke-Tf foundation apply}|Should -Throw '*partial provider failure*'
        (Read-LabJson $journalPath).started_stacks|Should -Contain foundation
        Test-Path -LiteralPath (Join-Path $manifestDir 'foundation.json')|Should -BeFalse
    }
    It 'can destroy foundation with no manifest after a partial first apply' {
        $journal.started_stacks=@('foundation')
        {Invoke-Tf foundation destroy}|Should -Not -Throw
        Should -Invoke Invoke-LabNative -Times 1 -ParameterFilter {$Arguments -contains '-destroy'}
        Should -Invoke Invoke-LabNative -Times 1 -ParameterFilter {$Arguments -contains 'state' -and $Arguments -contains 'list'}
    }
    It 'passes runtime owner/subscription variables after the profile file' {
        Invoke-Tf foundation apply
        Should -Invoke Invoke-LabNative -Times 1 -ParameterFilter {
            $Arguments -contains 'plan' -and $Arguments[3] -like '*environments*cheap-lab.tfvars' -and $Arguments[4] -like '*runtime.auto.tfvars.json'
        }
        $runtime=Read-LabJson (Join-Path $work 'terraform/stacks/foundation/runtime.auto.tfvars.json')
        $runtime.owner|Should -Be 'Test Owner'
        $runtime.subscription_id|Should -Be $SubscriptionId.ToString()
    }
    It 'does not mark a stack started or apply resources during plan-only execution' {
        $PlanOnly=$true
        Invoke-Tf foundation apply
        $journal.ContainsKey('started_stacks')|Should -BeFalse
        Should -Invoke Invoke-LabNative -Times 0 -ParameterFilter {$Arguments -contains 'apply'}
    }
    It 'fails teardown verification if resources remain in Terraform state' {
        Mock Invoke-LabNative {
            param($File,$Arguments,$LogPath)
            if($Arguments -contains 'show'){return '{"resource_changes":[]}'}
            if($Arguments -contains 'state'){return 'module.vm.azurerm_windows_virtual_machine.this'}
            return ''
        }
        {Invoke-Tf foundation destroy}|Should -Throw '*not empty*'
    }
}

Describe 'Preflight quota accounting without Azure' {
    BeforeEach {
        $repo=$actualRepo;$Environment='cheap-lab';$SubscriptionId=[guid]'11111111-1111-4111-8111-111111111111'
        $evidence=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $evidence|Out-Null
        Mock Get-Command {return [pscustomobject]@{Name='fake'}} -ParameterFilter {$Name -in @('az','terraform')}
        $script:existingVms=@()
        $script:providerState='Registered'
        Mock Invoke-LabNative {
            param($File,$Arguments,$LogPath)
            if($Arguments[0] -eq 'account'){return @{id=$SubscriptionId.ToString()}|ConvertTo-Json}
            if($Arguments[0] -eq 'provider'){
                return @('Microsoft.Compute','Microsoft.Network','Microsoft.Storage','Microsoft.KeyVault','Microsoft.Sql','Microsoft.OperationalInsights','Microsoft.Insights','Microsoft.ManagedIdentity','Microsoft.DevTestLab')|ForEach-Object {@{namespace=$_;state=$script:providerState}}|ConvertTo-Json -Depth 4
            }
            if($Arguments -contains 'list-skus'){
                return @('Standard_B2ms','Standard_B2s')|ForEach-Object {@{name=$_;family='standardBSFamily';restrictions=@();capabilities=@(@{name='vCPUs';value='2'})}}|ConvertTo-Json -Depth 5
            }
            if($Arguments -contains 'list-usage'){return @(@{name=@{value='standardBSFamily'};currentValue=4;limit=4},@{name=@{value='cores'};currentValue=4;limit=4})|ConvertTo-Json -Depth 5}
            if($Arguments -contains 'list'){return ConvertTo-Json -InputObject $script:existingVms -Depth 4}
            throw 'Unexpected mocked Azure command'
        }
    }
    It 'rejects a fresh deployment with insufficient additional quota' {
        {Test-Preflight}|Should -Throw '*Insufficient*'
    }
    It 'reports unregistered providers without registering them' {
        $script:providerState='NotRegistered'
        {Test-Preflight}|Should -Throw '*one-time owner setup*'
        Should -Invoke Invoke-LabNative -Times 0 -ParameterFilter {$Arguments -contains 'register'}
    }
    It 'credits already allocated lab VMs when retrying provision' {
        $script:existingVms=@(foreach($role in @('source','target')){
            @{id="/subscriptions/$SubscriptionId/resourceGroups/rg-azmig-cheap-lab-$role/providers/Microsoft.Compute/virtualMachines/vm-azmig-cheap-lab-$role";size='Standard_B2ms';location='westeurope'}
        })
        {Test-Preflight}|Should -Not -Throw
        (Read-LabJson (Join-Path $evidence 'preflight.json')).requested_cores.cores|Should -Be 0
    }
    It 'never credits unrelated VMs against the requested lab capacity' {
        $script:existingVms=@(@{id='/subscriptions/another/resourceGroups/other/providers/Microsoft.Compute/virtualMachines/unrelated';size='Standard_B2ms';location='westeurope'})
        {Test-Preflight}|Should -Throw '*Insufficient*'
    }
}
