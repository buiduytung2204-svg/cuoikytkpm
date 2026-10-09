$ErrorActionPreference = 'Stop'

$serviceName = 'postgresql-x64-18'
$dataDir = 'C:\Program Files\PostgreSQL\18\data'
$hbaPath = Join-Path $dataDir 'pg_hba.conf'
$psqlPath = 'C:\Program Files\PostgreSQL\18\bin\psql.exe'
$backupPath = Join-Path $env:TEMP ('pg_hba-' + [guid]::NewGuid().ToString('N') + '.conf')
$sqlPath = Join-Path $env:TEMP ('tkpm-pg-' + [guid]::NewGuid().ToString('N') + '.sql')

if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  throw 'Run this script from PowerShell opened with Run as administrator.'
}
if (-not (Test-Path -LiteralPath $hbaPath) -or -not (Test-Path -LiteralPath $psqlPath)) {
  throw 'PostgreSQL 18 was not found in the default installation folder.'
}

$rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
$appBytes = New-Object byte[] 32
$adminBytes = New-Object byte[] 32
$rng.GetBytes($appBytes)
$rng.GetBytes($adminBytes)
$appPassword = ([BitConverter]::ToString($appBytes) -replace '-', '').ToLowerInvariant()
$adminPassword = ([BitConverter]::ToString($adminBytes) -replace '-', '').ToLowerInvariant()

Copy-Item -LiteralPath $hbaPath -Destination $backupPath
try {
  $originalHba = Get-Content -LiteralPath $hbaPath -Raw
  $temporaryHba = $originalHba.Replace(
    'host    all             all             127.0.0.1/32            scram-sha-256',
    'host    all             all             127.0.0.1/32            trust'
  ).Replace(
    'host    all             all             ::1/128                 scram-sha-256',
    'host    all             all             ::1/128                 trust'
  )
  if ($temporaryHba -eq $originalHba) { throw 'Could not find expected localhost rules in pg_hba.conf.' }

  Set-Content -LiteralPath $hbaPath -Value $temporaryHba -Encoding ascii
  Restart-Service -Name $serviceName
  (Get-Service -Name $serviceName).WaitForStatus('Running', [TimeSpan]::FromSeconds(30))

  @"
ALTER ROLE postgres WITH PASSWORD '$adminPassword';
ALTER ROLE giai_dau_app WITH LOGIN PASSWORD '$appPassword';
"@ | Set-Content -LiteralPath $sqlPath -Encoding ascii
  & $psqlPath -h 127.0.0.1 -U postgres -d postgres -v ON_ERROR_STOP=1 -f $sqlPath
  if ($LASTEXITCODE -ne 0) { throw 'PostgreSQL could not update the application and admin passwords.' }
}
finally {
  Copy-Item -LiteralPath $backupPath -Destination $hbaPath -Force
  Restart-Service -Name $serviceName
  (Get-Service -Name $serviceName).WaitForStatus('Running', [TimeSpan]::FromSeconds(30))
  Remove-Item -LiteralPath $backupPath, $sqlPath -Force -ErrorAction SilentlyContinue
}

$workspace = Split-Path -Parent $MyInvocation.MyCommand.Path
$envContent = "DATABASE_URL=postgresql://giai_dau_app:$appPassword@127.0.0.1:5432/giai_dau`nHOST=127.0.0.1`nPORT=8000`nDB_POOL_MAX=20"
Set-Content -LiteralPath (Join-Path $workspace '.env') -Value $envContent -Encoding ascii
Set-Content -LiteralPath (Join-Path $workspace '.postgres-admin-password.txt') -Value "PostgreSQL admin password: $adminPassword" -Encoding ascii

Write-Host 'PostgreSQL credentials configured. Private .env and admin password file were saved in the project folder.'
