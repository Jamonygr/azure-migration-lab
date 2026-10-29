BeforeAll {
    $repo=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $source=Join-Path $repo 'scripts/quality/Sync-LabCheckpoint.ps1'
    $ast=[Management.Automation.Language.Parser]::ParseFile($source,[ref]$null,[ref]$null)
    $function=$ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Invoke-CheckpointAzure'},$true)
    . ([scriptblock]::Create($function.Extent.Text))
    # Declare the native boundary in this test's scope so CI needs no Azure CLI login.
    function az { param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments) }
}
Describe 'CI checkpoint native command boundary' {
    It 'invokes Azure CLI once rather than recursively invoking its wrapper' {
        Mock az { $global:LASTEXITCODE=0; 'false' }
        $result=Invoke-CheckpointAzure @('storage','blob','exists')
        $result | Should -Be 'false'
        Should -Invoke az -Times 1 -Exactly
    }
    It 'stops on failed checkpoint access instead of treating it as a first run' {
        Mock az { $global:LASTEXITCODE=1; 'Authentication failed' }
        { Invoke-CheckpointAzure @('storage','blob','exists') } | Should -Throw '*Checkpoint Azure operation failed*'
        Should -Invoke az -Times 1 -Exactly
    }
}
