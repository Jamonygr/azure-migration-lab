# Executed by Azure Run Command as SYSTEM. The host injects a nonsensitive $Context.
# Compatible with Windows PowerShell 5.1 on Windows Server 2022.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$base = 'C:\MigrationLab'
$tools = Join-Path $base 'Tools'
$logs = Join-Path $base 'Logs'
foreach($p in @($base,$tools,$logs)){[IO.Directory]::CreateDirectory($p)|Out-Null}
$marker = Join-Path $base 'readonly.flag'
$shareFence = Join-Path $base 'smb-fence.json'
$result = @{ok=$false;action=$Context.action;role=$Context.role}

function Run([string]$Executable,[string[]]$ArgumentList,[string]$Label='native') {
    $log = Join-Path $logs "$($Context.run_id)-$Label.log"
    & $Executable @ArgumentList *> $log
    if($LASTEXITCODE -ne 0){throw "$Label failed with exit $LASTEXITCODE. See guest log $log (credentials are not echoed)."}
}
function Get-Token([string]$Resource) {
    $u='http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource='+[uri]::EscapeDataString($Resource)
    if($Context.role -eq 'source'){$u+='&client_id='+[uri]::EscapeDataString($Context.foundation.migration_identity_client_id)}
    return (Invoke-RestMethod -Uri $u -Headers @{Metadata='true'} -TimeoutSec 30).access_token
}
function Get-SourceConnection([string]$Database='MigrationLab') {
    return "Server=.\SQLEXPRESS;Database=$Database;Integrated Security=True;Encrypt=True;TrustServerCertificate=True;Connection Timeout=30"
}
function Get-TargetConnection {
    return "Server=tcp:$($Context.target.sql_fqdn),1433;Database=$($Context.target.database_name);Encrypt=True;TrustServerCertificate=False;Connection Timeout=30"
}
function Invoke-Sql([string]$Connection,[string]$Query,[switch]$Azure) {
    $c=New-Object System.Data.SqlClient.SqlConnection $Connection
    try {
        if($Azure){$c.AccessToken=Get-Token 'https://database.windows.net/'}
        # Retry only opening the connection. Never blindly replay a possibly committed SQL statement.
        for($attempt=0;$attempt -lt 12;$attempt++){
            try{$c.Open();break}catch{if(!$Azure -or $attempt -eq 11){throw};Start-Sleep -Seconds 10;$c.AccessToken=Get-Token 'https://database.windows.net/'}
        }
        $cmd=$c.CreateCommand(); $cmd.CommandText=$Query; $cmd.CommandTimeout=180
        $adapter=New-Object System.Data.SqlClient.SqlDataAdapter $cmd
        $table=New-Object System.Data.DataTable
        [void]$adapter.Fill($table)
        return ,$table
    } finally {$c.Dispose()}
}
function Scalar([string]$Connection,[string]$Query,[switch]$Azure) {
    $table=Invoke-Sql $Connection $Query -Azure:$Azure
    return $table.Rows[0][0]
}
function Hash-Text([string]$Text) {
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
}
function Table-Json($Table) {
    $rows=@(foreach($r in $Table.Rows){$o=[ordered]@{};foreach($c in $Table.Columns){$o[$c.ColumnName]=if($r[$c] -is [DBNull]){$null}else{$r[$c]}};[pscustomobject]$o})
    return ConvertTo-Json -InputObject $rows -Compress -Depth 8
}
function Catalog-Signature([string]$Connection,[switch]$Azure) {
    $schema=Invoke-Sql $Connection "SELECT c.column_id,c.name,t.name AS type,c.max_length,c.is_nullable,c.is_identity,c.is_computed,c.collation_name FROM sys.columns c JOIN sys.types t ON t.user_type_id=c.user_type_id WHERE c.object_id=OBJECT_ID('dbo.Catalog') ORDER BY c.column_id" -Azure:$Azure
    $data=Invoke-Sql $Connection 'SELECT Id,Name,Quantity FROM dbo.Catalog ORDER BY Id' -Azure:$Azure
    $identity=Scalar $Connection "SELECT CONVERT(bigint,ISNULL(IDENT_CURRENT('dbo.Catalog'),0))" -Azure:$Azure
    return @{schema_sha256=(Hash-Text (Table-Json $schema));data_sha256=(Hash-Text (Table-Json $data));rows=$data.Rows.Count;identity=[long]$identity}
}
function Assert-SameSignature($Expected,$Actual) {
    foreach($key in @('schema_sha256','data_sha256','rows','identity')){if($Expected[$key] -ne $Actual[$key]){throw "Database comparison failed: $key"}}
}
function File-Manifest([string]$Directory) {
    $root=(Resolve-Path -LiteralPath $Directory).Path.TrimEnd('\')
    return @(Get-ChildItem -LiteralPath $root -Recurse -File | Sort-Object FullName | ForEach-Object {
        [pscustomobject][ordered]@{path=$_.FullName.Substring($root.Length+1).Replace('\','/');length=$_.Length;sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant();last_write_utc=$_.LastWriteTimeUtc.ToString('o')}
    })
}
function Assert-Files($Expected,$Actual) {
    if($Expected.Count -ne $Actual.Count){throw 'File count mismatch.'}
    for($i=0;$i -lt $Expected.Count;$i++){
        foreach($k in @('path','length','sha256')){if($Expected[$i].$k -ne $Actual[$i].$k){throw "File verification failed ($k): $($Expected[$i].path)"}}
        $delta=([datetime]$Expected[$i].last_write_utc-[datetime]$Actual[$i].last_write_utc).Duration()
        if($delta.TotalSeconds -gt 2){throw "File timestamp verification failed: $($Expected[$i].path)"}
    }
}
function AzCopy([string[]]$ArgumentList) {
    $env:AZCOPY_AUTO_LOGIN_TYPE='MSI'
    if($Context.role -eq 'source'){$env:AZCOPY_MSI_CLIENT_ID=$Context.foundation.migration_identity_client_id}else{Remove-Item Env:AZCOPY_MSI_CLIENT_ID -ErrorAction SilentlyContinue}
    for($attempt=0;$attempt -lt 6;$attempt++){
        try{Run (Join-Path $tools 'azcopy/azcopy.exe') $ArgumentList 'azcopy';return}catch{if($attempt -eq 5){throw};Start-Sleep -Seconds 20}
    }
}
function Blob-Url([string]$Name) { return "https://$($Context.foundation.storage_account_name).blob.core.windows.net/$($Context.foundation.staging_container_name)/$Name" }
function File-Url { return "https://$($Context.foundation.storage_account_name).file.core.windows.net/$($Context.foundation.file_share_name)/sample" }
function Download([string]$Url,[string]$Path,[switch]$Signed) {
    for($attempt=0;$attempt -lt 3;$attempt++){
        try {Invoke-WebRequest -Uri $Url -OutFile $Path -UseBasicParsing -TimeoutSec 600;break}catch{if($attempt -eq 2){throw};Start-Sleep -Seconds 10}
    }
    if($Signed){$sig=Get-AuthenticodeSignature -FilePath $Path;if($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'Microsoft'){throw "Microsoft signature validation failed for $Path"}}
}
function Install-Tools {
    if(!(Test-Path -LiteralPath (Join-Path $tools 'azcopy/azcopy.exe'))){
        $zip=Join-Path $tools 'azcopy.zip'; Download 'https://aka.ms/downloadazcopy-v10-windows' $zip
        $expand=Join-Path $tools 'azcopy-download'; Expand-Archive -LiteralPath $zip -DestinationPath $expand -Force
        $binary=Get-ChildItem -LiteralPath $expand -Filter azcopy.exe -Recurse | Select-Object -First 1
        if(!$binary){throw 'AzCopy archive contains no executable.'}
        [IO.Directory]::CreateDirectory((Join-Path $tools 'azcopy'))|Out-Null
        Copy-Item -LiteralPath $binary.FullName -Destination (Join-Path $tools 'azcopy/azcopy.exe') -Force
    }
    if(!(Test-Path -LiteralPath (Join-Path $tools 'sqlpackage/sqlpackage.exe'))){
        $zip=Join-Path $tools 'sqlpackage.zip'; Download 'https://aka.ms/sqlpackage-windows' $zip
        Expand-Archive -LiteralPath $zip -DestinationPath (Join-Path $tools 'sqlpackage') -Force
    }
}
function Install-IisDotnet {
    Install-WindowsFeature Web-Server,Web-Mgmt-Tools | Out-Null
    $release=Invoke-RestMethod -Uri 'https://builds.dotnet.microsoft.com/dotnet/release-metadata/10.0/releases.json' -TimeoutSec 60
    $current=@($release.releases | Where-Object {$_.'release-version' -eq $release.'latest-release'})[0]
    $bundle=@($current.'aspnetcore-runtime'.files | Where-Object {$_.name -match 'hosting.*\.exe$'}) | Select-Object -First 1
    if(!$bundle){throw 'Official .NET 10 metadata contains no Windows Hosting Bundle.'}
    $installer=Join-Path $tools 'hosting.exe'; Download $bundle.url $installer -Signed
    if((Get-FileHash -LiteralPath $installer -Algorithm SHA512).Hash -ine $bundle.hash){throw 'Hosting Bundle checksum mismatch.'}
    $process=Start-Process -FilePath $installer -ArgumentList @('/install','/quiet','/norestart') -Wait -PassThru -WindowStyle Hidden
    if($process.ExitCode -notin @(0,3010)){throw "Hosting Bundle installer failed: $($process.ExitCode)"}
    Restart-Service W3SVC
    Import-Module WebAdministration
    if(!(Test-Path 'IIS:\AppPools\MigrationLab')){New-WebAppPool -Name MigrationLab | Out-Null}
    Set-ItemProperty 'IIS:\AppPools\MigrationLab' -Name managedRuntimeVersion -Value ''
    [IO.Directory]::CreateDirectory((Join-Path $base 'App'))|Out-Null
    if(Test-Path 'IIS:\Sites\Default Web Site'){Stop-Website 'Default Web Site'}
    if(!(Test-Path 'IIS:\Sites\MigrationLab')){New-Website -Name MigrationLab -PhysicalPath (Join-Path $base 'App') -Port 80 -ApplicationPool MigrationLab | Out-Null}
    # Windows Firewall only admits HTTP from the two private lab networks.
    if(!(Get-NetFirewallRule -DisplayName 'MigrationLab HTTP' -ErrorAction SilentlyContinue)){New-NetFirewallRule -DisplayName 'MigrationLab HTTP' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 80 -RemoteAddress 'LocalSubnet',$Context.source.private_ip,$Context.target.private_ip | Out-Null}
}
function Set-AppConfig([string]$Site) {
    $connection=if($Site -eq 'source'){Get-SourceConnection}else{(Get-TargetConnection)+';Authentication=Active Directory Managed Identity'}
    $settings=@{ConnectionStrings=@{Lab=$connection};Lab=@{Site=$Site;ReadOnlyMarker=$marker};Logging=@{LogLevel=@{Default='Information';'Microsoft.AspNetCore'='Warning'}}}
    [IO.File]::WriteAllText((Join-Path $base 'App/appsettings.Production.json'),($settings|ConvertTo-Json -Depth 6))
    # App pool gets read/execute only; marker is outside deployable application content.
    Run 'icacls.exe' @((Join-Path $base 'App'),'/grant','IIS AppPool\MigrationLab:(OI)(CI)(RX)','/T','/Q') 'app-acl'
    Run 'icacls.exe' @($base,'/grant','IIS AppPool\MigrationLab:(RX)','/Q') 'marker-acl'
    if((Get-WebAppPoolState -Name MigrationLab).Value -eq 'Started'){Restart-WebAppPool MigrationLab}else{Start-WebAppPool MigrationLab}
}
function Wait-Ready([string]$Ip='localhost') {
    for($i=0;$i -lt 30;$i++){
        try{$r=Invoke-WebRequest -UseBasicParsing -Uri "http://$Ip/health/ready" -TimeoutSec 10;if($r.StatusCode -eq 200){return}}catch{}
        Start-Sleep -Seconds 10
    }
    throw "Application did not become ready at $Ip."
}
function Install-SqlSource {
    if(!(Get-Service 'MSSQL$SQLEXPRESS' -ErrorAction SilentlyContinue)){
        $bootstrap=Join-Path $tools 'SQL2022-SSEI-Expr.exe'
        Download 'https://go.microsoft.com/fwlink/?linkid=2215160' $bootstrap -Signed
        $media=Join-Path $tools 'sqlmedia';[IO.Directory]::CreateDirectory($media)|Out-Null
        $proc=Start-Process -FilePath $bootstrap -ArgumentList @('/ACTION=Download','/QUIET','/MEDIATYPE=Core',"/MEDIAPATH=$media") -Wait -PassThru -WindowStyle Hidden
        if($proc.ExitCode -ne 0){throw "SQL media download failed: $($proc.ExitCode)"}
        $package=Get-ChildItem -LiteralPath $media -Filter 'SQLEXPR*x64*.exe' | Select-Object -First 1
        if(!$package){throw 'SQL Server Express 2022 media was not downloaded.'}
        $sig=Get-AuthenticodeSignature $package.FullName;if($sig.Status -ne 'Valid'){throw 'SQL media signature invalid.'}
        $extract=Join-Path $tools 'sqlsetup'
        $proc=Start-Process -FilePath $package.FullName -ArgumentList @('/Q',"/x:$extract") -Wait -PassThru -WindowStyle Hidden
        if($proc.ExitCode -ne 0){throw 'SQL media extraction failed.'}
        $args=@('/Q','/ACTION=Install','/FEATURES=SQLENGINE','/INSTANCENAME=SQLEXPRESS','/SQLSVCACCOUNT="NT AUTHORITY\NETWORK SERVICE"','/SQLSYSADMINACCOUNTS="NT AUTHORITY\SYSTEM"','/IACCEPTSQLSERVERLICENSETERMS','/TCPENABLED=0','/NPENABLED=0','/UPDATEENABLED=False')
        $proc=Start-Process -FilePath (Join-Path $extract 'setup.exe') -ArgumentList $args -Wait -PassThru -WindowStyle Hidden
        if($proc.ExitCode -notin @(0,3010)){throw "SQL installation failed: $($proc.ExitCode)"}
    }
    if([int](Scalar (Get-SourceConnection master) "SELECT CONVERT(int,SERVERPROPERTY('ProductMajorVersion'))") -ne 16){throw 'Source must be SQL Server 2022 (major version 16).'}
    Invoke-Sql (Get-SourceConnection master) "IF DB_ID('MigrationLab') IS NULL CREATE DATABASE MigrationLab" | Out-Null
    $seed=@"
IF OBJECT_ID('dbo.Catalog') IS NULL
BEGIN
 CREATE TABLE dbo.Catalog(Id int IDENTITY(1,1) NOT NULL PRIMARY KEY,Name nvarchar(100) NOT NULL,Quantity int NOT NULL);
 INSERT dbo.Catalog(Name,Quantity) VALUES(N'Azure migration workbook',10),(N'Windows application server',2),(N'Quarterly archive',25);
END;
"@
    Invoke-Sql (Get-SourceConnection) $seed | Out-Null
    Invoke-Sql (Get-SourceConnection master) "IF SUSER_ID(N'IIS APPPOOL\MigrationLab') IS NULL CREATE LOGIN [IIS APPPOOL\MigrationLab] FROM WINDOWS" | Out-Null
    Invoke-Sql (Get-SourceConnection) "IF USER_ID(N'IIS APPPOOL\MigrationLab') IS NULL CREATE USER [IIS APPPOOL\MigrationLab] FOR LOGIN [IIS APPPOOL\MigrationLab]; ALTER ROLE db_datareader ADD MEMBER [IIS APPPOOL\MigrationLab]; ALTER ROLE db_datawriter ADD MEMBER [IIS APPPOOL\MigrationLab];" | Out-Null
}
function Assert-SampleSchema {
    $conn=Get-SourceConnection
    $objects=Invoke-Sql $conn "SELECT type,name FROM sys.objects WHERE is_ms_shipped=0 AND type NOT IN ('PK','U')"
    $tables=Invoke-Sql $conn "SELECT SCHEMA_NAME(schema_id) AS schema_name,name FROM sys.tables WHERE is_ms_shipped=0"
    if($objects.Rows.Count -gt 0 -or $tables.Rows.Count -ne 1 -or $tables.Rows[0].name -ne 'Catalog' -or $tables.Rows[0].schema_name -ne 'dbo'){throw 'This sample exporter only supports dbo.Catalog. Additional objects require a separate migration design.'}
    $cols=Invoke-Sql $conn "SELECT name,TYPE_NAME(user_type_id) AS type,max_length,is_nullable,is_identity,is_computed FROM sys.columns WHERE object_id=OBJECT_ID('dbo.Catalog') ORDER BY column_id"
    if($cols.Rows.Count -ne 3 -or $cols.Rows[0].name -ne 'Id' -or $cols.Rows[0].type -ne 'int' -or !$cols.Rows[0].is_identity -or $cols.Rows[1].name -ne 'Name' -or $cols.Rows[1].type -ne 'nvarchar' -or $cols.Rows[1].max_length -ne 200 -or $cols.Rows[2].name -ne 'Quantity' -or $cols.Rows[2].type -ne 'int' -or @($cols.Rows | Where-Object {$_.is_nullable -or $_.is_computed}).Count){throw 'dbo.Catalog columns differ from the supported sample schema.'}
    $pk=Invoke-Sql $conn "SELECT c.name FROM sys.indexes i JOIN sys.index_columns ic ON i.object_id=ic.object_id AND i.index_id=ic.index_id JOIN sys.columns c ON c.object_id=ic.object_id AND c.column_id=ic.column_id WHERE i.object_id=OBJECT_ID('dbo.Catalog') AND i.is_primary_key=1"
    if($pk.Rows.Count -ne 1 -or $pk.Rows[0].name -ne 'Id'){throw 'dbo.Catalog primary key differs from the sample schema.'}
    if([int](Scalar $conn "SELECT COUNT(*) FROM sys.indexes WHERE object_id=OBJECT_ID('dbo.Catalog') AND (is_primary_key=0 OR type<>1)") -ne 0){throw 'Additional/nonclustered indexes are outside the sample exporter contract.'}
    if([int](Scalar $conn "SELECT COUNT(*) FROM sys.identity_columns WHERE object_id=OBJECT_ID('dbo.Catalog') AND (CONVERT(bigint,seed_value)<>1 OR CONVERT(bigint,increment_value)<>1)") -ne 0){throw 'The sample exporter requires IDENTITY(1,1).'}
}
function Freeze {
    [IO.File]::WriteAllText($marker,'source writes frozen for migration')
    Invoke-Sql (Get-SourceConnection master) 'ALTER DATABASE MigrationLab SET READ_ONLY WITH ROLLBACK IMMEDIATE' | Out-Null
    if(!(Test-Path -LiteralPath $shareFence)){
        $before=@(Get-SmbShareAccess -Name MigrationLab | Select-Object AccountName,AccessControlType,AccessRight)
        $existingDeny=@($before|Where-Object {$_.AccountName -eq 'Everyone' -and [string]$_.AccessControlType -eq 'Deny'}).Count -gt 0
        @{previous=$before;added_everyone_deny=(!$existingDeny)}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $shareFence -Encoding UTF8
    }
    $currentDeny=@(Get-SmbShareAccess -Name MigrationLab|Where-Object {$_.AccountName -eq 'Everyone' -and [string]$_.AccessControlType -eq 'Deny'})
    if(!$currentDeny.Count){Block-SmbShareAccess -Name MigrationLab -AccountName Everyone -Force|Out-Null}
    $fileRoot=(Join-Path $base 'Files').TrimEnd('\')+'\'
    Get-SmbOpenFile|Where-Object {$_.Path.StartsWith($fileRoot,[StringComparison]::OrdinalIgnoreCase)}|ForEach-Object {Close-SmbOpenFile -FileId $_.FileId -Force}
}
function Unfreeze {
    if(Test-Path -LiteralPath $shareFence){
        $saved=Get-Content -LiteralPath $shareFence -Raw|ConvertFrom-Json
        if($saved.added_everyone_deny){Unblock-SmbShareAccess -Name MigrationLab -AccountName Everyone -Force|Out-Null}
        $actual=@(Get-SmbShareAccess -Name MigrationLab|Select-Object AccountName,AccessControlType,AccessRight|Sort-Object AccountName,AccessControlType)
        $expected=@($saved.previous|Sort-Object AccountName,AccessControlType)
        if(($actual|ConvertTo-Json -Compress) -ne ($expected|ConvertTo-Json -Compress)){throw 'SMB permissions changed during migration. Review the saved smb-fence.json before resuming writes.'}
        Remove-Item -LiteralPath $shareFence -Force
    }
    Invoke-Sql (Get-SourceConnection master) 'ALTER DATABASE MigrationLab SET READ_WRITE WITH ROLLBACK IMMEDIATE' | Out-Null
    if(Test-Path -LiteralPath $marker){Remove-Item -LiteralPath $marker -Force}
}
function Assert-Frozen {
    if(!(Test-Path -LiteralPath $marker) -or !(Scalar (Get-SourceConnection master) "SELECT is_read_only FROM sys.databases WHERE name='MigrationLab'")){throw 'Source database and application must both be write-frozen.'}
    $deny=@(Get-SmbShareAccess -Name MigrationLab|Where-Object {$_.AccountName -eq 'Everyone' -and [string]$_.AccessControlType -eq 'Deny'})
    if(!(Test-Path -LiteralPath $shareFence) -or !$deny.Count){throw 'Source SMB write fence is missing.'}
}
function Transfer {
    Assert-Frozen
    Assert-SampleSchema
    $targetConn=Get-TargetConnection
    if([int](Scalar $targetConn 'SELECT COUNT(*) FROM sys.objects WHERE is_ms_shipped=0' -Azure) -ne 0){throw 'Destination database contains user objects. Use the explicit reset-target stage; imports never overwrite existing databases.'}
    Import-Module WebAdministration
    $bindings=@(Get-WebBinding -Name MigrationLab)
    if($bindings.Count -ne 1 -or $bindings[0].protocol -ne 'http' -or $bindings[0].bindingInformation -ne '*:80:'){throw 'The runnable sample supports one HTTP :80 IIS binding. Assess custom TLS/host bindings before extending this migration.'}
    $pool=Get-Item 'IIS:\AppPools\MigrationLab'
    $iis=@{site='MigrationLab';binding='*:80:';protocol='http';pool='MigrationLab';managedRuntimeVersion=[string]$pool.managedRuntimeVersion;managedPipelineMode=[string]$pool.managedPipelineMode;startMode=[string]$pool.startMode}
    $iis|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $base 'iis-config.json') -Encoding UTF8
    AzCopy @('copy',(Join-Path $base 'iis-config.json'),(Blob-Url 'iis-config.json'),'--overwrite=true')
    # Capture current deployed content, including learner changes, rather than the original seed ZIP.
    $packageRoot=Join-Path $base "Package-$($Context.run_id)";[IO.Directory]::CreateDirectory($packageRoot)|Out-Null
    Get-ChildItem -LiteralPath (Join-Path $base 'App')|Copy-Item -Destination $packageRoot -Recurse -Force
    $siteConfig=Join-Path $packageRoot 'appsettings.Production.json'
    if(Test-Path -LiteralPath $siteConfig){Remove-Item -LiteralPath $siteConfig -Force}
    Compress-Archive -Path (Join-Path $packageRoot '*') -DestinationPath (Join-Path $base 'application.zip') -Force
    AzCopy @('copy',(Join-Path $base 'application.zip'),(Blob-Url 'application.zip'),'--overwrite=true')
    $sig=Catalog-Signature (Get-SourceConnection)
    $copy='MigrationLabExport_'+($Context.run_id -replace '[^a-zA-Z0-9]','')
    $bacpac=Join-Path $base "$copy.bacpac"
    try {
        Invoke-Sql (Get-SourceConnection master) "CREATE DATABASE [$copy]" | Out-Null
        Invoke-Sql (Get-SourceConnection $copy) "CREATE TABLE dbo.Catalog(Id int IDENTITY(1,1) NOT NULL PRIMARY KEY,Name nvarchar(100) NOT NULL,Quantity int NOT NULL); SET IDENTITY_INSERT dbo.Catalog ON; INSERT dbo.Catalog(Id,Name,Quantity) SELECT Id,Name,Quantity FROM MigrationLab.dbo.Catalog; SET IDENTITY_INSERT dbo.Catalog OFF; DBCC CHECKIDENT('dbo.Catalog',RESEED,$($sig.identity)) WITH NO_INFOMSGS;" | Out-Null
        Assert-SameSignature $sig (Catalog-Signature (Get-SourceConnection $copy))
        Invoke-Sql (Get-SourceConnection master) "ALTER DATABASE [$copy] SET READ_ONLY WITH ROLLBACK IMMEDIATE" | Out-Null
        Run (Join-Path $tools 'sqlpackage/sqlpackage.exe') @('/Action:Export',"/SourceConnectionString:$(Get-SourceConnection $copy)","/TargetFile:$bacpac",'/OverwriteFiles:False','/Quiet:True') 'sql-export'
        $token=Get-Token 'https://database.windows.net/'
        Run (Join-Path $tools 'sqlpackage/sqlpackage.exe') @('/Action:Import',"/TargetConnectionString:$targetConn","/AccessToken:$token","/SourceFile:$bacpac",'/Quiet:True') 'sql-import'
        $token=$null
        Invoke-Sql $targetConn "DBCC CHECKIDENT('dbo.Catalog',RESEED,$($sig.identity)) WITH NO_INFOMSGS" -Azure | Out-Null
        Assert-SameSignature $sig (Catalog-Signature $targetConn -Azure)
        $sid='0x'+([BitConverter]::ToString(([guid]$Context.target.identity_principal_id).ToByteArray())).Replace('-','')
        Invoke-Sql $targetConn "CREATE USER [migration-app] WITH SID=$sid, TYPE=E; ALTER ROLE db_datareader ADD MEMBER [migration-app];" -Azure | Out-Null
        AzCopy @('copy',(Join-Path $base 'Files/*'),(File-Url),'--recursive=true','--preserve-info=true','--preserve-permissions=false','--overwrite=true','--backup')
        $download=Join-Path $base "Verify-$($Context.run_id)";[IO.Directory]::CreateDirectory($download)|Out-Null
        AzCopy @('copy',((File-Url)+'/*'),$download,'--recursive=true','--preserve-info=true','--backup')
        $files=File-Manifest (Join-Path $base 'Files')
        Assert-Files $files (File-Manifest $download)
        $manifest=@{run_id=$Context.run_id;database=$sig;files=$files;application_sha256=(Get-FileHash -LiteralPath (Join-Path $base 'application.zip') -Algorithm SHA256).Hash.ToLowerInvariant();iis_sha256=(Get-FileHash -LiteralPath (Join-Path $base 'iis-config.json') -Algorithm SHA256).Hash.ToLowerInvariant()}
        $manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $base 'migration-manifest.json') -Encoding UTF8
        AzCopy @('copy',(Join-Path $base 'migration-manifest.json'),(Blob-Url 'migration-manifest.json'),'--overwrite=true')
        $result.database=$sig;$result.file_count=$files.Count;$result.file_verification='sha256+length+path+timestamp';$result.run_id=$Context.run_id
    } finally {
        if(Scalar (Get-SourceConnection master) "SELECT COUNT(*) FROM sys.databases WHERE name='$copy'") {Invoke-Sql (Get-SourceConnection master) "ALTER DATABASE [$copy] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$copy]" | Out-Null}
    }
}
function Validate-Migration {
    Assert-Frozen
    $m=Get-Content -LiteralPath (Join-Path $base 'migration-manifest.json') -Raw | ConvertFrom-Json
    $source=Catalog-Signature (Get-SourceConnection);$target=Catalog-Signature (Get-TargetConnection) -Azure
    $expected=@{};foreach($p in $m.database.PSObject.Properties){$expected[$p.Name]=$p.Value}
    Assert-SameSignature $expected $source;Assert-SameSignature $expected $target
    Wait-Ready $Context.target.private_ip
    $status=Invoke-RestMethod -Uri "http://$($Context.target.private_ip)/api/status" -TimeoutSec 30
    if(!$status.readOnly -or $status.site -ne 'target'){throw 'Target application is not fenced in target mode.'}
    $sourceFiles=File-Manifest (Join-Path $base 'Files')
    Assert-Files @($m.files) $sourceFiles
    $download=Join-Path $base "Validate-$($Context.run_id)";[IO.Directory]::CreateDirectory($download)|Out-Null
    AzCopy @('copy',((File-Url)+'/*'),$download,'--recursive=true','--preserve-info=true','--backup')
    Assert-Files $sourceFiles (File-Manifest $download)
    $result.database=$target;$result.file_count=$sourceFiles.Count;$result.target_read_only=$true;$result.migration_run=$m.run_id
}

try {
    switch($Context.action){
        bootstrap {
            Install-Tools;Install-IisDotnet
            if($Context.role -eq 'source'){
                Install-SqlSource
                $files=Join-Path $base 'Files';[IO.Directory]::CreateDirectory($files)|Out-Null
                for($i=1;$i -le 12;$i++){$file=Join-Path $files ("document-{0:D3}.txt" -f $i);if(!(Test-Path -LiteralPath $file)){[IO.File]::WriteAllText($file,"Synthetic migration document $i`r`nNo customer data.`r`n");(Get-Item -LiteralPath $file).LastWriteTimeUtc=[datetime]'2026-01-01T00:00:00Z'}}
                if(!(Get-SmbShare -Name MigrationLab -ErrorAction SilentlyContinue)){New-SmbShare -Name MigrationLab -Path $files -FullAccess 'BUILTIN\Administrators' | Out-Null}
                $appSource=Join-Path $base 'app-source.zip';[IO.File]::WriteAllBytes($appSource,[Convert]::FromBase64String($Context.app_source_zip))
                $appBuild=Join-Path $base 'Build';Expand-Archive -LiteralPath $appSource -DestinationPath $appBuild -Force
                $install=Join-Path $tools 'dotnet-install.ps1';Download 'https://dot.net/v1/dotnet-install.ps1' $install
                & $install -Channel '10.0' -InstallDir (Join-Path $tools 'dotnet') -NoPath *> (Join-Path $logs 'dotnet-install.log')
                if(!(Test-Path -LiteralPath (Join-Path $tools 'dotnet/dotnet.exe'))){throw 'SDK installation failed.'}
                Run (Join-Path $tools 'dotnet/dotnet.exe') @('publish',(Join-Path $appBuild 'MigrationLab.csproj'),'-c','Release','-o',(Join-Path $base 'Publish'),'--nologo','-p:RestoreSources=https://api.nuget.org/v3/index.json','-p:RestoreLockedMode=true') 'dotnet-publish'
                Compress-Archive -Path (Join-Path $base 'Publish/*') -DestinationPath (Join-Path $base 'application.zip') -Force
                AzCopy @('copy',(Join-Path $base 'application.zip'),(Blob-Url 'application.zip'),'--overwrite=true')
                Expand-Archive -LiteralPath (Join-Path $base 'application.zip') -DestinationPath (Join-Path $base 'App') -Force
                Set-AppConfig source;Wait-Ready
            }else{[IO.File]::WriteAllText($marker,'target writes disabled until acceptance')}
            $result.installed=$true
        }
        discover {
            $os=Get-CimInstance Win32_OperatingSystem;$cpu=Get-CimInstance Win32_ComputerSystem
            $disks=@(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | ForEach-Object {@{name=$_.DeviceID;size_gb=[math]::Round($_.Size/1GB,2);free_gb=[math]::Round($_.FreeSpace/1GB,2)}})
            Import-Module WebAdministration
            $result.inventory=@{name=$env:COMPUTERNAME;ip=$Context.source.private_ip;cores=$cpu.NumberOfLogicalProcessors;memory_mb=[math]::Round($cpu.TotalPhysicalMemory/1MB);os_name=$os.Caption;os_version=$os.Version;disks=$disks;iis_sites=@(Get-Website|ForEach-Object {@{name=$_.name;state=[string]$_.state;physical_path=$_.physicalPath}});sql_version=[string](Scalar (Get-SourceConnection master) "SELECT CONVERT(nvarchar(128),SERVERPROPERTY('ProductVersion'))");sql_database='MigrationLab';shares=@(Get-SmbShare|Where-Object {$_.Name -eq 'MigrationLab'}|Select-Object -ExpandProperty Name);dependencies=@('IIS -> local SQL Express','application private DNS -> IIS','file clients -> source SMB share')}
        }
        freeze {Freeze;$result.frozen=$true}
        unfreeze {Unfreeze;$result.frozen=$false}
        transfer {Transfer}
        deploy {
            [IO.File]::WriteAllText($marker,'target writes disabled until acceptance')
            AzCopy @('copy',(Blob-Url 'application.zip'),(Join-Path $base 'application.zip'),'--overwrite=true')
            AzCopy @('copy',(Blob-Url 'migration-manifest.json'),(Join-Path $base 'migration-manifest.json'),'--overwrite=true')
            AzCopy @('copy',(Blob-Url 'iis-config.json'),(Join-Path $base 'iis-config.json'),'--overwrite=true')
            $m=Get-Content -LiteralPath (Join-Path $base 'migration-manifest.json') -Raw|ConvertFrom-Json
            if((Get-FileHash -LiteralPath (Join-Path $base 'application.zip') -Algorithm SHA256).Hash -ine $m.application_sha256){throw 'Application artifact checksum mismatch.'}
            if((Get-FileHash -LiteralPath (Join-Path $base 'iis-config.json') -Algorithm SHA256).Hash -ine $m.iis_sha256){throw 'IIS configuration checksum mismatch.'}
            Import-Module WebAdministration;Stop-WebAppPool MigrationLab
            $iis=Get-Content -LiteralPath (Join-Path $base 'iis-config.json') -Raw | ConvertFrom-Json
            if($iis.site -ne 'MigrationLab' -or $iis.binding -ne '*:80:'){throw 'IIS configuration is outside the portable sample contract.'}
            foreach($property in @('managedRuntimeVersion','managedPipelineMode','startMode')){Set-ItemProperty 'IIS:\AppPools\MigrationLab' -Name $property -Value $iis.$property}
            Expand-Archive -LiteralPath (Join-Path $base 'application.zip') -DestinationPath (Join-Path $base 'App') -Force
            Set-AppConfig target;Wait-Ready
            $result.deployed=$true;$result.read_only=$true
        }
        validate {Validate-Migration}
        grantwrites {Invoke-Sql (Get-TargetConnection) 'ALTER ROLE db_datawriter ADD MEMBER [migration-app]' -Azure | Out-Null;$result.granted=$true}
        accept {if(Test-Path -LiteralPath $marker){Remove-Item -LiteralPath $marker -Force};Wait-Ready;$s=Invoke-RestMethod 'http://localhost/api/status';if($s.readOnly){throw 'Target remained read-only.'};$result.accepted=$true}
        ready {Wait-Ready;$s=Invoke-RestMethod 'http://localhost/api/status';if($s.site -ne 'target' -or $s.readOnly){throw 'Target must be accepted and writable before source retirement.'};$result.ready=$true}
        dns {
            $name='app.'+$Context.foundation.private_dns_zone_name
            $ok=$false
            for($i=0;$i -lt 18;$i++){Clear-DnsClientCache;$ips=@(Resolve-DnsName $name -Type A -ErrorAction SilentlyContinue | Where-Object {$_.Type -eq 'A'} | Select-Object -ExpandProperty IPAddress);if($Context.expected_ip -in $ips){$ok=$true;break};Start-Sleep -Seconds 10}
            if(!$ok){throw "DNS did not converge to $($Context.expected_ip) for $name"};$result.name=$name;$result.ip=$Context.expected_ip
        }
        resetfiles {
            $exists=$true
            try{Invoke-WebRequest -UseBasicParsing -Uri ((File-Url)+'?restype=directory') -Method Head -Headers @{Authorization=('Bearer '+(Get-Token 'https://storage.azure.com/'));'x-ms-version'='2022-11-02';'x-ms-date'=[DateTime]::UtcNow.ToString('R',[Globalization.CultureInfo]::InvariantCulture);'x-ms-file-request-intent'='backup'}|Out-Null}
            catch{if($_.Exception.Response.StatusCode.value__ -eq 404){$exists=$false}else{throw}}
            if($exists){AzCopy @('remove',(File-Url),'--recursive=true')};$result.reset=$true
        }
        default {throw "Unknown guest action: $($Context.action)"}
    }
    $result.ok=$true
} catch {
    $result.ok=$false;$result.error=$_.Exception.Message
    # Never print tokens, complete connection strings, or native command arguments.
    $result.error=$result.error -replace '(?i)(sig|token|password|access_token)=([^&\s]+)','$1=<redacted>'
}
$encoded=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($result|ConvertTo-Json -Depth 12 -Compress)))
Write-Output "MIGRATION_RESULT:$encoded"
if(!$result.ok){exit 1}
