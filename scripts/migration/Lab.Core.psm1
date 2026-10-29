Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-LabNative {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$File, [string[]]$Arguments = @(), [string]$LogPath)
    $output = @(& $File @Arguments 2>&1)
    $code = $LASTEXITCODE
    # Native output may contain credential-bearing URLs; redact before persistence.
    $clean = ($output | ForEach-Object { [string]$_ }) -join "`n"
    $clean = $clean -replace '(?i)(sig|token|password|access_token)=([^&\s]+)', '$1=<redacted>'
    $clean = $clean -replace '(?i)(Bearer\s+)[A-Za-z0-9._~-]+', '$1<redacted>'
    if ($LogPath) { [IO.File]::WriteAllText($LogPath, $clean) }
    if ($code -ne 0) { throw "$File failed (exit $code). $clean" }
    return $clean
}

function Read-LabJson {
    param([string]$Path)
    if (!(Test-Path -LiteralPath $Path)) { throw "Required file is missing: $Path" }
    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable
}

function Write-LabJson {
    param([Parameter(Mandatory)]$Value,[Parameter(Mandatory)][string]$Path)
    $parent = Split-Path -Parent $Path
    [IO.Directory]::CreateDirectory($parent) | Out-Null
    $temp = "$Path.tmp"
    [IO.File]::WriteAllText($temp, ($Value | ConvertTo-Json -Depth 30))
    Move-Item -LiteralPath $temp -Destination $Path -Force
}

function Assert-LabConfirmation {
    param([string]$Actual,[string]$Expected)
    if ($Actual -cne $Expected) { throw "This operation requires -ConfirmAction '$Expected'." }
}

function Get-LabBackendConfiguration {
    param([ValidateSet('local','azurerm')][string]$Type)
    return "terraform {`n  backend `"$Type`" {}`n}`n"
}

function Assert-LabStage {
    param([string]$Stage,[hashtable]$Journal)
    $status = $Journal.status
    $allowed = @{
        provision = @('new','provisioned','destroyed'); seed = @('provisioned','seeded'); discover = @('seeded','discovered','rehearsed','rolled-back','reset');
        'assess-export' = @('discovered','rehearsed','reset'); rehearse = @('discovered','reset');
        migrate = @('discovered','reset'); validate = @('migrated','validated','cutover');
        cutover = @('validated'); rollback = @('cutover','validated','migrated'); accept = @('cutover','accepted');
        'retire-source' = @('accepted'); 'reset-target' = @('seeded','discovered','rehearsed','rolled-back','migrated','validated','reset');
        destroy = @('new','provisioned','seeded','discovered','rehearsed','migrated','validated','cutover','rolled-back','accepted','retired','reset','failed')
    }
    if ($Stage -in @('preflight','plan')) { return }
    if (!$allowed.ContainsKey($Stage) -or $status -notin $allowed[$Stage]) {
        throw "Stage '$Stage' is not allowed from '$status'. Follow the workbook; use explicit reset-target after a rehearsal or rollback."
    }
    if ($Stage -in @('cutover','accept')) {
        if (!$Journal.ContainsKey('validation_run') -or $Journal.validation_run -ne $Journal.migration_run) { throw 'Current migration has no matching validation evidence.' }
    }
}

function ConvertTo-LabMigrateCsv {
    param([hashtable]$Inventory,[string]$Path)
    if (!$Inventory.name -or [int]$Inventory.cores -lt 1 -or [long]$Inventory.memory_mb -lt 1) { throw 'Inventory lacks required Azure Migrate fields.' }
    $row=[ordered]@{
        'Server name' = $Inventory.name; 'IP address' = $Inventory.ip; 'Cores' = $Inventory.cores;
        'Memory (In MB)' = $Inventory.memory_mb; 'OS name' = 'Windows Server 2022';
        'OS version' = $Inventory.os_version; 'OS architecture' = 'x64';
        'Number of disks' = $Inventory.disks.Count
    }
    $index=0
    foreach($disk in @($Inventory.disks)|Select-Object -First 20){
        $index++
        if($disk.ContainsKey('size_gb')){$row["Disk $index size (In GB)"]=$disk.size_gb}
    }
    [pscustomobject]$row | Export-Csv -LiteralPath $Path -NoTypeInformation -Encoding utf8
}

function Get-LabGuestResult {
    param([string]$Json)
    $response = $Json | ConvertFrom-Json -AsHashtable
    if (!$response.ContainsKey('value')) { throw 'Azure Run Command returned no execution result.' }
    $messages = @($response.value | ForEach-Object { $_.message }) -join "`n"
    $match = [regex]::Matches($messages, 'MIGRATION_RESULT:([A-Za-z0-9+/=]+)')
    if ($match.Count -ne 1) { throw 'Guest command did not produce exactly one success result. Inspect the VM Run Command execution; do not assume provisioning success means script success.' }
    $result = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($match[0].Groups[1].Value)) | ConvertFrom-Json -AsHashtable
    if (!$result.ok) { throw "Guest operation failed: $($result.error)" }
    return $result
}

Export-ModuleMember -Function *-Lab*
