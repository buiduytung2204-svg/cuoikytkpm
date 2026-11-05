param(
  [Parameter(Mandatory = $true)]
  [string]$SourceDir,

  [Parameter(Mandatory = $true)]
  [string]$DeployDir
)

$ErrorActionPreference = 'Stop'
$expectedDeployDir = 'C:\Users\tungb\cuoikytkpm-git'
$SourceDir = [System.IO.Path]::GetFullPath($SourceDir)
$DeployDir = [System.IO.Path]::GetFullPath($DeployDir)
if (-not [string]::Equals($DeployDir.TrimEnd('\\'), $expectedDeployDir, [StringComparison]::OrdinalIgnoreCase)) {
  throw "Refusing to deploy outside the configured app directory: $DeployDir"
}

$docker = (Get-Command docker.exe -ErrorAction Stop).Source
$composeFile = Join-Path $DeployDir 'compose.yaml'
$envFile = Join-Path $DeployDir '.env.docker'
$containerName = 'cuoikytkpm-git-app-1'
$imageName = 'cuoikytkpm-git-app'
$relativeFiles = @('package.json', 'package-lock.json', 'server.js', 'giai-dau.html', 'Dockerfile')

foreach ($required in @($composeFile, $envFile)) {
  if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
    throw "Required local deployment config is missing: $required"
  }
}
foreach ($relative in $relativeFiles) {
  if (-not (Test-Path -LiteralPath (Join-Path $SourceDir $relative) -PathType Leaf)) {
    throw "Build source is missing: $relative"
  }
}

$composeProject = 'cuoikytkpm-git'
$composeArgs = @('compose', '-p', $composeProject, '-f', $composeFile)
$dockerInfo = & $docker info --format '{{.ServerVersion}}' 2>&1
if ($LASTEXITCODE -ne 0) { throw "Docker Desktop is unavailable: $dockerInfo" }

$oldImageId = (& $docker image inspect $imageName --format '{{.Id}}' 2>$null | Select-Object -First 1)
if ($LASTEXITCODE -ne 0 -or -not $oldImageId) {
  $oldImageId = (& $docker inspect $containerName --format '{{.Image}}' 2>$null | Select-Object -First 1)
}
if ($LASTEXITCODE -ne 0 -or -not $oldImageId) {
  throw "Could not find the currently running app image for rollback safety: $containerName"
}

$deployId = [Guid]::NewGuid().ToString('N')
$stageDir = Join-Path $DeployDir ".ci-deploy\$deployId\staging"
$backupDir = Join-Path $DeployDir ".ci-deploy\$deployId\backup"
New-Item -ItemType Directory -Path $stageDir, $backupDir -Force | Out-Null
$copied = @()
$deploymentStarted = $false
$rollbackTag = "${imageName}:rollback-$deployId"

try {
  foreach ($relative in $relativeFiles) {
    Copy-Item -LiteralPath (Join-Path $SourceDir $relative) -Destination (Join-Path $stageDir $relative) -Force
    if (Test-Path -LiteralPath (Join-Path $DeployDir $relative) -PathType Leaf) {
      Copy-Item -LiteralPath (Join-Path $DeployDir $relative) -Destination (Join-Path $backupDir $relative) -Force
    }
  }

  foreach ($relative in $relativeFiles) {
    Copy-Item -LiteralPath (Join-Path $stageDir $relative) -Destination (Join-Path $DeployDir $relative) -Force
    $copied += $relative
  }

  & $docker image tag $oldImageId $rollbackTag
  if ($LASTEXITCODE -ne 0) { throw 'Could not preserve the currently running app image for rollback.' }

  & $docker @composeArgs build app
  if ($LASTEXITCODE -ne 0) { throw 'Docker Compose failed to build the application image.' }

  & $docker @composeArgs up -d --no-deps app
  if ($LASTEXITCODE -ne 0) { throw 'Docker Compose failed to replace the application container.' }
  $deploymentStarted = $true

  $healthy = $false
  for ($attempt = 0; $attempt -lt 60; $attempt++) {
    Start-Sleep -Seconds 2
    $status = & $docker inspect $containerName --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' 2>$null
    if ($LASTEXITCODE -eq 0 -and $status.Trim() -eq 'healthy') {
      $healthy = $true
      break
    }
    $state = & $docker inspect $containerName --format '{{.State.Status}}' 2>$null
    if ($LASTEXITCODE -eq 0 -and $state.Trim() -eq 'exited') { break }
  }
  if (-not $healthy) {
    $tail = & $docker logs --tail 30 $containerName 2>&1
    throw "New app container failed its health check.`n$tail"
  }

  Write-Output "Deployment succeeded; $containerName is healthy. PostgreSQL container and volume were not changed."
} catch {
  $failure = $_
  if ($deploymentStarted) {
    & $docker image tag $rollbackTag $imageName 2>$null | Out-Null
    & $docker @composeArgs up -d --no-deps app 2>&1 | Out-Null
  }
  foreach ($relative in $copied) {
    $backup = Join-Path $backupDir $relative
    $target = Join-Path $DeployDir $relative
    if (Test-Path -LiteralPath $backup -PathType Leaf) {
      Copy-Item -LiteralPath $backup -Destination $target -Force
    }
  }
  throw $failure
} finally {
  & $docker image rm $rollbackTag 2>$null | Out-Null
  $workDir = Split-Path -Parent $stageDir
  if (Test-Path -LiteralPath $workDir) {
    Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue
  }
}
