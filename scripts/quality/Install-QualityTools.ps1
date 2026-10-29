[CmdletBinding()]
param([string]$Destination = (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'work/tools'))
$ErrorActionPreference = 'Stop'
if (-not ($IsWindows -or $IsLinux)) { throw 'This installer supports Windows and Linux x64.' }
New-Item -ItemType Directory -Path $Destination -Force | Out-Null
$osName = if ($IsWindows) { 'windows' } else { 'linux' }
$titleOs = if ($IsWindows) { 'Windows' } else { 'Linux' }
$suffix = if ($IsWindows) { 'zip' } else { 'tar.gz' }
$downloads = @(
    @{Repo='terraform-docs/terraform-docs'; Version='0.24.0'; Name="terraform-docs-v0.24.0-$osName-amd64.$suffix"; Sum='terraform-docs-v0.24.0.sha256sum'},
    @{Repo='terraform-linters/tflint'; Version='0.65.0'; Name="tflint_${osName}_amd64.zip"; Sum='checksums.txt'},
    @{Repo='gitleaks/gitleaks'; Version='8.30.1'; Name="gitleaks_8.30.1_${osName}_x64.$suffix"; Sum='gitleaks_8.30.1_checksums.txt'},
    @{Repo='open-policy-agent/conftest'; Version='0.71.1'; Name="conftest_0.71.1_${titleOs}_x86_64.$suffix"; Sum='checksums.txt'},
    @{Repo='rhysd/actionlint'; Version='1.7.12'; Name="actionlint_1.7.12_${osName}_amd64.$suffix"; Sum='actionlint_1.7.12_checksums.txt'},
    @{Repo='aquasecurity/trivy'; Version='0.76.1'; Name="trivy_0.76.1_${titleOs}-64bit.$suffix"; Sum='trivy_0.76.1_checksums.txt'}
)
foreach ($tool in $downloads) {
    $url = "https://github.com/$($tool.Repo)/releases/download/v$($tool.Version)"
    $archive = Join-Path $Destination $tool.Name
    $checksums = (Invoke-WebRequest "$url/$($tool.Sum)").Content
    if ($checksums -is [byte[]]) { $checksums = [Text.Encoding]::UTF8.GetString($checksums) }
    $line = @($checksums -split "`n" | Where-Object { $_ -match ('\s+\*?' + [regex]::Escape($tool.Name) + '\s*$') })
    if ($line.Count -ne 1) { throw "Missing unique checksum for $($tool.Name)" }
    $expected = ($line[0].Trim() -split '\s+')[0]
    if (-not (Test-Path $archive) -or (Get-FileHash $archive -Algorithm SHA256).Hash -ne $expected) {
        Invoke-WebRequest "$url/$($tool.Name)" -OutFile $archive
    }
    if ((Get-FileHash $archive -Algorithm SHA256).Hash -ne $expected) { throw "Checksum mismatch: $archive" }
    if ($archive.EndsWith('.zip')) { Expand-Archive -LiteralPath $archive -DestinationPath $Destination -Force }
    else { & tar -xzf $archive -C $Destination; if ($LASTEXITCODE -ne 0) { throw 'Archive extraction failed.' } }
    Write-Host "Verified $($tool.Repo) $($tool.Version)"
}
Write-Host "Add to PATH: $Destination"
if ($env:GITHUB_PATH) { $Destination | Add-Content -LiteralPath $env:GITHUB_PATH }
