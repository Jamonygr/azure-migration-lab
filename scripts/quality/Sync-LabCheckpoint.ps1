[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Upload','Download')][string]$Direction,
    [Parameter(Mandatory)][ValidateSet('cheap-lab','dev','lab','prod')][string]$Environment,
    [Parameter(Mandatory)][string]$StorageAccount,
    [Parameter(Mandatory)][string]$Container
)
$ErrorActionPreference='Stop'
$repo=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$folder=Join-Path $repo "work/$Environment"
New-Item -ItemType Directory -Path $folder -Force | Out-Null
$zip=Join-Path $repo "work/$Environment-checkpoint.zip"
$blob="azure-migration-lab/$Environment/checkpoint.zip"
function Invoke-CheckpointAzure([string[]]$Arguments){
    $result=& az @Arguments --only-show-errors
    if($LASTEXITCODE -ne 0){throw "Checkpoint Azure operation failed ($LASTEXITCODE)"}
    return $result
}
if($Direction -eq 'Download'){
    $exists=Invoke-CheckpointAzure @('storage','blob','exists','--account-name',$StorageAccount,'--container-name',$Container,'--name',$blob,'--auth-mode','login','--query','exists','--output','tsv')
    if("$exists".Trim() -eq 'false'){Write-Host 'No prior checkpoint; first run.';return}
    if("$exists".Trim() -ne 'true'){throw 'Unexpected checkpoint existence response.'}
    $null=Invoke-CheckpointAzure @('storage','blob','download','--account-name',$StorageAccount,'--container-name',$Container,'--name',$blob,'--file',$zip,'--overwrite','true','--auth-mode','login')
    # The checkpoint is data, never executable content. Reject unexpected archive paths.
    $archive=[IO.Compression.ZipFile]::OpenRead($zip)
    try{
        foreach($entry in $archive.Entries){
            $name=$entry.FullName.Replace('\','/')
            if($name -notmatch '^(journal\.json|inventory\.json|manifests/(foundation|source|target|cutover)\.json)$'){throw "Unexpected checkpoint entry: $name"}
        }
    }finally{$archive.Dispose()}
    Expand-Archive -LiteralPath $zip -DestinationPath $folder -Force
}else{
    $files=@('journal.json','inventory.json','manifests/foundation.json','manifests/source.json','manifests/target.json','manifests/cutover.json') | Where-Object {Test-Path (Join-Path $folder $_)}
    if(-not $files){Write-Host 'No checkpoint data to upload.';return}
    if(Test-Path $zip){Remove-Item -LiteralPath $zip}
    $archive=[IO.Compression.ZipFile]::Open($zip,[IO.Compression.ZipArchiveMode]::Create)
    try{foreach($file in $files){$null=[IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive,(Join-Path $folder $file),$file)}}finally{$archive.Dispose()}
    $null=Invoke-CheckpointAzure @('storage','blob','upload','--account-name',$StorageAccount,'--container-name',$Container,'--name',$blob,'--file',$zip,'--overwrite','true','--auth-mode','login')
}
