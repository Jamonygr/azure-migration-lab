[CmdletBinding()]
param([string]$DotNet = 'dotnet')
$ErrorActionPreference = 'Stop'
$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$dll = Join-Path $repo 'app/MigrationLab/bin/Release/net10.0/MigrationLab.dll'
if (-not (Test-Path -LiteralPath $dll)) { throw 'Build the application in Release configuration first.' }
$testDir = Join-Path $repo "work/app-test/$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $testDir -Force | Out-Null
$marker = Join-Path $testDir 'readonly.flag'
function Assert-That([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "FAIL: $Message" }
    Write-Host "PASS: $Message"
}
function Start-TestHost([string]$HostEnvironment) {
    $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
    $listener.Start(); $port = $listener.LocalEndpoint.Port; $listener.Stop()
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = (Get-Command $DotNet).Source
    $info.ArgumentList.Add($dll)
    $info.WorkingDirectory = Join-Path $repo 'app/MigrationLab'
    $info.UseShellExecute = $false; $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true; $info.RedirectStandardError = $true
    $info.Environment['ASPNETCORE_URLS'] = "http://127.0.0.1:$port"
    $info.Environment['ASPNETCORE_ENVIRONMENT'] = $HostEnvironment
    $info.Environment['Lab__Site'] = 'target'
    $info.Environment['Lab__ReadOnlyMarker'] = $marker
    $info.Environment.Remove('ConnectionStrings__Lab') | Out-Null
    $proc = [Diagnostics.Process]::Start($info)
    $stdout = $proc.StandardOutput.ReadToEndAsync(); $stderr = $proc.StandardError.ReadToEndAsync()
    $base = "http://127.0.0.1:$port"
    for ($attempt = 0; $attempt -lt 60; $attempt++) {
        try {
            $null = Invoke-WebRequest "$base/health/live" -TimeoutSec 1
            return @{ Process = $proc; Base = $base; Stdout = $stdout; Stderr = $stderr }
        } catch { if ($proc.HasExited) { throw "App exited: $($stderr.Result)" }; Start-Sleep -Milliseconds 200 }
    }
    $proc.Kill($true); throw 'Application startup timeout.'
}
function Stop-TestHost($HostInfo) {
    if (-not $HostInfo.Process.HasExited) { $HostInfo.Process.Kill($true); $HostInfo.Process.WaitForExit() }
    $HostInfo.Stdout.Result | Set-Content (Join-Path $testDir 'stdout.log')
    $HostInfo.Stderr.Result | Set-Content (Join-Path $testDir 'stderr.log')
    $HostInfo.Process.Dispose()
}
$server = Start-TestHost 'Testing'
try {
    $base = $server.Base
    $status = Invoke-RestMethod "$base/api/status"
    Assert-That ($status.site -eq 'target' -and $status.store -eq 'test-memory') 'explicit test store and target identity'
    Assert-That ((Invoke-WebRequest "$base/health/ready").StatusCode -eq 200) 'database readiness responds'
    $create = Invoke-WebRequest "$base/api/catalog" -Method Post -ContentType 'application/json' -Body '{"name":"Synthetic migration record","quantity":7}'
    Assert-That ($create.StatusCode -eq 201) 'write succeeds before the freeze'
    $invalid = Invoke-WebRequest "$base/api/catalog" -Method Post -ContentType 'application/json' -Body '{"name":"","quantity":-1}' -SkipHttpErrorCheck
    Assert-That ($invalid.StatusCode -eq 400) 'invalid data is rejected'
    Set-Content -LiteralPath $marker -Value 'acceptance'
    $status = Invoke-RestMethod "$base/api/status"
    Assert-That $status.readOnly 'freeze is visible without restarting IIS'
    $blocked = Invoke-WebRequest "$base/api/catalog" -Method Post -ContentType 'application/json' -Body '{"name":"Must not persist","quantity":9}' -SkipHttpErrorCheck
    Assert-That ($blocked.StatusCode -eq 423) 'acceptance mode blocks writes'
    $rows = @(Invoke-RestMethod "$base/api/catalog")
    Assert-That ($rows.Count -eq 1 -and $rows[0].quantity -eq 7) 'read-only rejection preserves the existing data'
    Remove-Item -LiteralPath $marker
    $accepted = Invoke-WebRequest "$base/api/catalog" -Method Post -ContentType 'application/json' -Body '{"name":"Accepted","quantity":2}'
    Assert-That ($accepted.StatusCode -eq 201) 'acceptance enables writes without restarting'
    Assert-That ((Invoke-WebRequest "$base/").Content -match 'One application') 'dashboard is served'
} finally { Stop-TestHost $server }
$server = Start-TestHost 'Production'
try {
    $response = Invoke-WebRequest "$($server.Base)/health/ready" -SkipHttpErrorCheck
    Assert-That ($response.StatusCode -eq 503) 'production cannot silently use the test database'
    $body = if ($response.Content -is [byte[]]) { [Text.Encoding]::UTF8.GetString($response.Content) } else { [string]$response.Content }
    Assert-That ($body -notmatch 'ConnectionStrings|StackTrace|Password') 'readiness failure does not expose connection settings'
} finally { Stop-TestHost $server }
Write-Host 'Application integration checks passed. SQL/Azure integration requires live validation.'
