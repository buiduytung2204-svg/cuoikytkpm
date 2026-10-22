param(
  [Parameter(Mandatory = $true)]
  [string]$SourceDir,

  [Parameter(Mandatory = $true)]
  [string]$DeployDir
)

$ErrorActionPreference = 'Stop'

if (-not ('JenkinsProcessInspector' -as [type])) {
  Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class JenkinsProcessInspector {
  [StructLayout(LayoutKind.Sequential)]
  public struct PROCESS_BASIC_INFORMATION {
    public IntPtr Reserved1;
    public IntPtr PebBaseAddress;
    public IntPtr Reserved2_0;
    public IntPtr Reserved2_1;
    public IntPtr UniqueProcessId;
    public IntPtr InheritedFromUniqueProcessId;
  }
  [DllImport("kernel32.dll", SetLastError = true)]
  public static extern IntPtr OpenProcess(uint access, bool inherit, int processId);
  [DllImport("ntdll.dll")]
  public static extern int NtQueryInformationProcess(IntPtr process, int infoClass, out PROCESS_BASIC_INFORMATION info, int length, out int returned);
  [DllImport("kernel32.dll", SetLastError = true)]
  public static extern bool ReadProcessMemory(IntPtr process, IntPtr address, byte[] buffer, int size, out IntPtr read);
  [DllImport("kernel32.dll")]
  public static extern bool CloseHandle(IntPtr handle);
}
"@
}

function Get-ProcessWorkingDirectory([int]$ProcessId) {
  $processHandle = [JenkinsProcessInspector]::OpenProcess(0x1010, $false, $ProcessId)
  if ($processHandle -eq [IntPtr]::Zero) { return $null }
  try {
    $info = New-Object JenkinsProcessInspector+PROCESS_BASIC_INFORMATION
    $returned = 0
    $status = [JenkinsProcessInspector]::NtQueryInformationProcess(
      $processHandle,
      0,
      [ref]$info,
      [Runtime.InteropServices.Marshal]::SizeOf($info),
      [ref]$returned
    )
    if ($status -ne 0) { return $null }

    $pointerSize = [IntPtr]::Size
    $parametersOffset = if ($pointerSize -eq 8) { 0x20 } else { 0x10 }
    $currentDirectoryOffset = if ($pointerSize -eq 8) { 0x38 } else { 0x24 }
    $pointerOffset = if ($pointerSize -eq 8) { 8 } else { 4 }

    $bytesRead = [IntPtr]::Zero
    $pointerBytes = New-Object byte[] $pointerSize
    $pebParameters = [IntPtr]::Add($info.PebBaseAddress, $parametersOffset)
    if (-not [JenkinsProcessInspector]::ReadProcessMemory($processHandle, $pebParameters, $pointerBytes, $pointerSize, [ref]$bytesRead)) { return $null }
    if ($pointerSize -eq 8) {
      $parameters = [IntPtr]([BitConverter]::ToInt64($pointerBytes, 0))
    } else {
      $parameters = [IntPtr]([BitConverter]::ToInt32($pointerBytes, 0))
    }
    if ($parameters -eq [IntPtr]::Zero) { return $null }

    $descriptorSize = if ($pointerSize -eq 8) { 16 } else { 8 }
    $descriptor = New-Object byte[] $descriptorSize
    $descriptorAddress = [IntPtr]::Add($parameters, $currentDirectoryOffset)
    if (-not [JenkinsProcessInspector]::ReadProcessMemory($processHandle, $descriptorAddress, $descriptor, $descriptorSize, [ref]$bytesRead)) { return $null }
    $pathLength = [BitConverter]::ToUInt16($descriptor, 0)
    if ($pathLength -lt 2 -or $pathLength -gt 16384) { return $null }

    if ($pointerSize -eq 8) {
      $pathAddress = [IntPtr]([BitConverter]::ToInt64($descriptor, $pointerOffset))
    } else {
      $pathAddress = [IntPtr]([BitConverter]::ToInt32($descriptor, $pointerOffset))
    }
    if ($pathAddress -eq [IntPtr]::Zero) { return $null }

    $pathBytes = New-Object byte[] $pathLength
    if (-not [JenkinsProcessInspector]::ReadProcessMemory($processHandle, $pathAddress, $pathBytes, $pathLength, [ref]$bytesRead)) { return $null }
    return [Text.Encoding]::Unicode.GetString($pathBytes)
  } catch {
    return $null
  } finally {
    [void][JenkinsProcessInspector]::CloseHandle($processHandle)
  }
}

$SourceDir = [System.IO.Path]::GetFullPath($SourceDir)
$DeployDir = [System.IO.Path]::GetFullPath($DeployDir)
$sourceFiles = @(
  'package.json',
  'package-lock.json',
  'server.js',
  'giai-dau.html',
  'quan-ly-server.ps1',
  'Bat-dau-server.bat',
  'scripts/validate.js'
)

foreach ($relativePath in $sourceFiles) {
  $sourcePath = Join-Path $SourceDir $relativePath
  if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
    throw "Deployment source is missing: $relativePath"
  }
}

if (-not (Test-Path -LiteralPath (Join-Path $DeployDir '.env') -PathType Leaf)) {
  throw "The deployment directory must already contain its private .env file: $DeployDir"
}

$node = Get-Command node.exe -ErrorAction Stop
$npm = Get-Command npm.cmd -ErrorAction Stop
$clientDir = Join-Path $DeployDir '.server-client'
$stateFile = Join-Path $clientDir 'processes.json'
$stdoutLog = Join-Path $clientDir 'server.out.log'
$stderrLog = Join-Path $clientDir 'server.err.log'
$runId = [Guid]::NewGuid().ToString('N')
$workDir = Join-Path $clientDir "deploy-$runId"
$stagingDir = Join-Path $workDir 'staging'
$backupDir = Join-Path $workDir 'backup'
$appFiles = @(
  'package.json',
  'package-lock.json',
  'server.js',
  'giai-dau.html',
  'quan-ly-server.ps1',
  'Bat-dau-server.bat',
  'scripts/validate.js'
)

New-Item -ItemType Directory -Path $stagingDir, $backupDir -Force | Out-Null
$oldServerPid = 0
$oldNgrokPid = 0
$oldServerStopped = $false
$newServer = $null
$installedFiles = @()

try {
  foreach ($relativePath in $appFiles) {
    $stagedPath = Join-Path $stagingDir $relativePath
    $stagedParent = Split-Path -Parent $stagedPath
    New-Item -ItemType Directory -Path $stagedParent -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $SourceDir $relativePath) -Destination $stagedPath -Force
  }

  $npmInstall = Start-Process -FilePath $npm.Source `
    -ArgumentList @('ci', '--omit=dev') `
    -WorkingDirectory $stagingDir `
    -Wait -PassThru -NoNewWindow `
    -RedirectStandardOutput (Join-Path $workDir 'npm.out.log') `
    -RedirectStandardError (Join-Path $workDir 'npm.err.log')
  if ($npmInstall.ExitCode -ne 0) {
    $details = if (Test-Path -LiteralPath (Join-Path $workDir 'npm.err.log')) {
      (Get-Content -LiteralPath (Join-Path $workDir 'npm.err.log') -Tail 20) -join "`n"
    } else { '' }
    throw "Dependency installation failed with exit code $($npmInstall.ExitCode).`n$details"
  }

  $oldState = $null
  if (Test-Path -LiteralPath $stateFile) {
    try { $oldState = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json } catch { }
  }
  $oldNgrokPid = if ($oldState) { [int]$oldState.ngrokPid } else { 0 }
  $listener = Get-NetTCPConnection -LocalPort 8000 -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($listener) {
    $ownerPid = [int]$listener.OwningProcess
    $owner = Get-CimInstance Win32_Process -Filter "ProcessId = $ownerPid" -ErrorAction SilentlyContinue
    $serverPattern = [regex]::Escape((Join-Path $DeployDir 'server.js'))
    $ownerMatchesScript = $owner -and $owner.Name -eq 'node.exe' -and $owner.CommandLine -match $serverPattern
    if (-not $ownerMatchesScript -and $owner -and $owner.Name -eq 'node.exe' -and $owner.CommandLine -match '(?i)\bserver\.js(?:\s|$)') {
      $workingDirectory = Get-ProcessWorkingDirectory -ProcessId $ownerPid
      if ($workingDirectory) {
        $ownerPath = [System.IO.Path]::GetFullPath($workingDirectory).TrimEnd([char[]]@('\', '/'))
        $targetPath = [System.IO.Path]::GetFullPath($DeployDir).TrimEnd([char[]]@('\', '/'))
        $ownerMatchesScript = [string]::Equals($ownerPath, $targetPath, [StringComparison]::OrdinalIgnoreCase)
      }
    }
    if (-not $ownerMatchesScript) {
      throw 'Port 8000 is occupied by a process outside the configured deployment directory; it was left untouched.'
    }
    $oldServerPid = $ownerPid
  }

  if ($oldServerPid -gt 0) {
    Stop-Process -Id $oldServerPid -Force
    for ($attempt = 0; $attempt -lt 20; $attempt++) {
      Start-Sleep -Milliseconds 250
      $stillRunning = Get-Process -Id $oldServerPid -ErrorAction SilentlyContinue
      if (-not $stillRunning) { break }
    }
    if (Get-Process -Id $oldServerPid -ErrorAction SilentlyContinue) {
      throw 'The current application process did not stop; deployment was cancelled.'
    }
    $oldServerStopped = $true
  }

  $hadNodeModules = Test-Path -LiteralPath (Join-Path $DeployDir 'node_modules')
  if ($hadNodeModules) {
    Move-Item -LiteralPath (Join-Path $DeployDir 'node_modules') -Destination (Join-Path $backupDir 'node_modules')
  }

  $installedFiles = @()
  foreach ($relativePath in $appFiles) {
    $targetPath = Join-Path $DeployDir $relativePath
    $backupPath = Join-Path $backupDir $relativePath
    $targetParent = Split-Path -Parent $targetPath
    $backupParent = Split-Path -Parent $backupPath
    New-Item -ItemType Directory -Path $targetParent, $backupParent -Force | Out-Null

    if (Test-Path -LiteralPath $targetPath -PathType Leaf) {
      Move-Item -LiteralPath $targetPath -Destination $backupPath
    }
    $installedFiles += $relativePath
    Copy-Item -LiteralPath (Join-Path $stagingDir $relativePath) -Destination $targetPath -Force
  }

  Move-Item -LiteralPath (Join-Path $stagingDir 'node_modules') -Destination (Join-Path $DeployDir 'node_modules')

  New-Item -ItemType Directory -Path $clientDir -Force | Out-Null
  $serverPath = Join-Path $DeployDir 'server.js'
  $newServer = Start-Process -FilePath $node.Source `
    -ArgumentList @('"' + $serverPath + '"') `
    -WorkingDirectory $DeployDir `
    -WindowStyle Hidden -PassThru `
    -RedirectStandardOutput $stdoutLog `
    -RedirectStandardError $stderrLog

  $healthy = $false
  for ($attempt = 0; $attempt -lt 40; $attempt++) {
    Start-Sleep -Milliseconds 500
    if ($newServer.HasExited) { break }
    try {
      $request = [System.Net.HttpWebRequest]::Create('http://127.0.0.1:8000/api/bootstrap-status')
      $request.Timeout = 1000
      $request.Proxy = $null
      $response = $request.GetResponse()
      $healthy = [int]$response.StatusCode -eq 200
      $response.Close()
      if ($healthy) { break }
    } catch { }
  }

  if (-not $healthy) {
    $details = if (Test-Path -LiteralPath $stderrLog) {
      (Get-Content -LiteralPath $stderrLog -Tail 20) -join "`n"
    } else { '' }
    throw "The deployed server did not pass its local health check.`n$details"
  }

  [pscustomobject]@{
    serverPid = $newServer.Id
    ngrokPid = $oldNgrokPid
  } | ConvertTo-Json | Set-Content -LiteralPath $stateFile -Encoding UTF8

  $deploymentCommitted = $true
  Write-Output "Deployment succeeded. Server PID: $($newServer.Id). Existing .env and ngrok process were preserved."
} catch {
  if ($newServer -and -not $newServer.HasExited) {
    Stop-Process -Id $newServer.Id -Force -ErrorAction SilentlyContinue
  }

  foreach ($relativePath in $installedFiles) {
    $targetPath = Join-Path $DeployDir $relativePath
    $backupPath = Join-Path $backupDir $relativePath
    if (Test-Path -LiteralPath $backupPath -PathType Leaf) {
      Copy-Item -LiteralPath $backupPath -Destination $targetPath -Force
    } else {
      Remove-Item -LiteralPath $targetPath -Force -ErrorAction SilentlyContinue
    }
  }

  $oldModules = Join-Path $backupDir 'node_modules'
  $currentModules = Join-Path $DeployDir 'node_modules'
  if (Test-Path -LiteralPath $oldModules) {
    if (Test-Path -LiteralPath $currentModules) {
      Remove-Item -LiteralPath $currentModules -Recurse -Force
    }
    Move-Item -LiteralPath $oldModules -Destination $currentModules
  }

  if ($oldServerStopped) {
    try {
      $recoveredServer = Start-Process -FilePath $node.Source `
        -ArgumentList @('"' + (Join-Path $DeployDir 'server.js') + '"') `
        -WorkingDirectory $DeployDir `
        -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput $stdoutLog `
        -RedirectStandardError $stderrLog
      [pscustomobject]@{ serverPid = $recoveredServer.Id; ngrokPid = $oldNgrokPid } |
        ConvertTo-Json | Set-Content -LiteralPath $stateFile -Encoding UTF8
    } catch { }
  }

  throw
} finally {
  if (Test-Path -LiteralPath $workDir) {
    Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue
  }
}
