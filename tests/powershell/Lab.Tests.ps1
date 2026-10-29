BeforeAll {
    $repo=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $repo 'scripts/migration/Lab.Core.psm1') -Force
}

Describe 'Migration transition safety' {
    It 'requires validation from the same migration before cutover' {
        $journal=@{status='validated';migration_run='run-2';validation_run='run-1'}
        {Assert-LabStage cutover $journal}|Should -Throw '*matching validation*'
    }
    It 'rejects a migration directly after a rehearsal without resetting the destination' {
        {Assert-LabStage migrate @{status='rehearsed'}}|Should -Throw '*reset-target*'
    }
    It 'rejects rollback and target reset after writes have been accepted' {
        {Assert-LabStage rollback @{status='accepted'}}|Should -Throw
        {Assert-LabStage reset-target @{status='accepted'}}|Should -Throw
    }
    It 'rejects source retirement before acceptance' {
        {Assert-LabStage retire-source @{status='cutover'}}|Should -Throw
    }
    It 'allows the complete controlled lifecycle' {
        foreach($pair in @(@('seed','provisioned'),@('discover','seeded'),@('rehearse','discovered'),@('reset-target','rehearsed'),@('migrate','reset'),@('validate','migrated'),@('cutover','validated'),@('rollback','cutover'),@('accept','cutover'),@('retire-source','accepted'))){
            {Assert-LabStage $pair[0] @{status=$pair[1];migration_run='r';validation_run='r'}}|Should -Not -Throw
        }
    }
    It 'requires an exact environment-specific destructive phrase' {
        {Assert-LabConfirmation 'DESTROY prod' 'DESTROY cheap-lab'}|Should -Throw
        {Assert-LabConfirmation 'destroy cheap-lab' 'DESTROY cheap-lab'}|Should -Throw
        {Assert-LabConfirmation 'DESTROY cheap-lab' 'DESTROY cheap-lab'}|Should -Not -Throw
    }
}

Describe 'Guest execution evidence' {
    It 'does not mistake Azure provisioning success for a successful guest command' {
        {Get-LabGuestResult '{"value":[{"code":"ProvisioningState/succeeded","message":"Script completed with exit 1"}]}'}|Should -Throw '*success result*'
    }
    It 'accepts exactly one positive guest sentinel' {
        $encoded=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('{"ok":true,"action":"validate"}'))
        $json=@{value=@(@{message="MIGRATION_RESULT:$encoded"})}|ConvertTo-Json -Depth 4
        (Get-LabGuestResult $json).action|Should -Be validate
    }
    It 'fails when the guest reports an unsuccessful data check' {
        $encoded=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('{"ok":false,"error":"File hash mismatch"}'))
        $json=@{value=@(@{message="MIGRATION_RESULT:$encoded"})}|ConvertTo-Json -Depth 4
        {Get-LabGuestResult $json}|Should -Throw '*File hash mismatch*'
    }
    It 'rejects duplicate sentinels' {
        $encoded=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('{"ok":true}'))
        $json=@{value=@(@{message="MIGRATION_RESULT:$encoded MIGRATION_RESULT:$encoded"})}|ConvertTo-Json -Depth 4
        {Get-LabGuestResult $json}|Should -Throw
    }
}

Describe 'Inventory and evidence' {
    It 'generates valid local and Azure backend overrides' {
        foreach($kind in @('local','azurerm')){
            $dir=Join-Path $TestDrive $kind
            New-Item -ItemType Directory -Path $dir | Out-Null
            Set-Content -LiteralPath (Join-Path $dir 'backend.tf') -Value (Get-LabBackendConfiguration $kind)
            {Invoke-LabNative terraform @("-chdir=$dir",'init','-backend=false','-input=false')}|Should -Not -Throw
        }
    }
    It 'writes quoted CSV fields and rejects incomplete inventory' {
        $path=Join-Path $TestDrive 'inventory.csv'
        $inventory=@{name='Server, Alpha';ip='10.100.1.4';cores=2;memory_mb=8192;os_version='10.0';disks=@(@{name='C:'})}
        ConvertTo-LabMigrateCsv $inventory $path
        $row=Import-Csv -LiteralPath $path
        $row.'Server name'|Should -Be 'Server, Alpha'
        $row.'Memory (In MB)'|Should -Be 8192
        {ConvertTo-LabMigrateCsv @{name='bad';cores=0;memory_mb=1} $path}|Should -Throw
    }
    It 'atomically persists and reads the journal without temporary remnants' {
        $path=Join-Path $TestDrive 'nested/journal.json'
        Write-LabJson @{status='cutover';history=@(@{run='r'})} $path
        (Read-LabJson $path).status|Should -Be cutover
        Test-Path -LiteralPath "$path.tmp"|Should -BeFalse
    }
    It 'propagates native process failures' {
        {Invoke-LabNative pwsh @('-NoProfile','-Command','exit 7')}|Should -Throw '*exit 7*'
    }
    It 'redacts credential-bearing native output before logging' {
        $path=Join-Path $TestDrive 'native.log'
        Invoke-LabNative pwsh @('-NoProfile','-Command',"Write-Output 'https://example.test/?sig=FAKE_FOR_TEST&x=1'") $path | Out-Null
        Get-Content -LiteralPath $path -Raw|Should -Not -Match 'FAKE_FOR_TEST'
        Get-Content -LiteralPath $path -Raw|Should -Match '<redacted>'
    }
}

Describe 'Write-fence verification' {
    BeforeAll {
        $tokens=$null;$errors=$null
        $ast=[System.Management.Automation.Language.Parser]::ParseFile((Join-Path $repo 'scripts/guest/Invoke-Guest.ps1'),[ref]$tokens,[ref]$errors)
        $fn=$ast.Find({param($node)$node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Assert-Frozen'},$true)
        . ([scriptblock]::Create($fn.Extent.Text))
        function Scalar { return $true }
        function Get-SourceConnection { return 'test' }
        function Get-SmbShareAccess { return @([pscustomobject]@{AccountName='Everyone';AccessControlType='Deny'}) }
    }
    BeforeEach {
        $marker=Join-Path $TestDrive 'readonly.flag';Set-Content -LiteralPath $marker -Value frozen
        $shareFence=Join-Path $TestDrive 'smb-fence.json';Set-Content -LiteralPath $shareFence -Value '{}'
    }
    It 'rejects a writable database even if an app marker exists' {
        Mock Scalar {return $false}
        {Assert-Frozen}|Should -Throw '*database and application*'
    }
    It 'rejects missing SMB denial even if database and application are frozen' {
        Mock Get-SmbShareAccess {return @()}
        {Assert-Frozen}|Should -Throw '*SMB write fence*'
    }
    It 'accepts only the complete set of fences' {
        {Assert-Frozen}|Should -Not -Throw
    }
}

Describe 'Guest data comparison' {
    BeforeAll {
        $tokens=$null;$errors=$null
        $ast=[System.Management.Automation.Language.Parser]::ParseFile((Join-Path $repo 'scripts/guest/Invoke-Guest.ps1'),[ref]$tokens,[ref]$errors)
        foreach($name in @('Assert-SameSignature','Assert-Files')){
            $fn=$ast.Find({param($node)$node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name},$true)
            . ([scriptblock]::Create($fn.Extent.Text))
        }
    }
    It 'detects changed content even when row counts are identical' {
        {Assert-SameSignature @{rows=3;data_sha256='a';schema_sha256='s';identity=3} @{rows=3;data_sha256='b';schema_sha256='s';identity=3}}|Should -Throw '*data_sha256*'
    }
    It 'detects identity state divergence' {
        {Assert-SameSignature @{rows=3;data_sha256='a';schema_sha256='s';identity=10} @{rows=3;data_sha256='a';schema_sha256='s';identity=3}}|Should -Throw '*identity*'
    }
    It 'detects file loss and content changes' {
        $expected=@([pscustomobject]@{path='a.txt';length=3;sha256='abc';last_write_utc='2026-01-01T00:00:00Z'})
        {Assert-Files $expected @()}|Should -Throw '*count*'
        $actual=@([pscustomobject]@{path='a.txt';length=3;sha256='xyz';last_write_utc='2026-01-01T00:00:00Z'})
        {Assert-Files $expected $actual}|Should -Throw '*sha256*'
    }
}
