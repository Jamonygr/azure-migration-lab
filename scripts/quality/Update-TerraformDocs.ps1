[CmdletBinding()]
param([switch]$Check)
$ErrorActionPreference='Stop'
$repo=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$dirs=@(Get-ChildItem (Join-Path $repo 'modules'),(Join-Path $repo 'stacks') -Directory | Where-Object {Test-Path (Join-Path $_.FullName 'main.tf')})
foreach($dir in $dirs){
    $file=Join-Path $dir.FullName 'README.md'
    $content=(& terraform-docs markdown table --sort-by required $dir.FullName | Out-String).Replace("`r`n","`n").TrimEnd()+"`n"
    if($LASTEXITCODE -ne 0){throw "terraform-docs failed for $($dir.Name)"}
    if($Check){if(-not(Test-Path $file) -or [IO.File]::ReadAllText($file).Replace("`r`n","`n") -ne $content){throw "Generated documentation drift: $file"}}
    else{[IO.File]::WriteAllText($file,$content,[Text.UTF8Encoding]::new($false))}
}
Write-Host "Terraform references checked/generated for $($dirs.Count) directories."
