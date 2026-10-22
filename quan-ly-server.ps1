$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$ProjectRoot = Split-Path -Parent $PSCommandPath
$ServerScript = Join-Path $ProjectRoot 'server.js'
$ClientData = Join-Path $ProjectRoot '.server-client'
$StateFile = Join-Path $ClientData 'processes.json'
$StdoutLog = Join-Path $ClientData 'server.out.log'
$StderrLog = Join-Path $ClientData 'server.err.log'
$NgrokPath = $null

function Find-Ngrok {
  $cmd = Get-Command ngrok.exe -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  $known = @(
    (Join-Path $env:LOCALAPPDATA 'Programs\ngrok\ngrok.exe'),
    (Join-Path $env:LOCALAPPDATA 'Temp\ngrok-install-stage\ngrok.exe')
  )
  foreach ($path in $known) { if (Test-Path -LiteralPath $path) { return $path } }
  return $null
}

function Get-ClientState {
  if (Test-Path -LiteralPath $StateFile) {
    try { return Get-Content -LiteralPath $StateFile -Raw | ConvertFrom-Json } catch { }
  }
  return [pscustomobject]@{ serverPid = 0; ngrokPid = 0 }
}

function Save-ClientState([int]$ServerPid, [int]$NgrokPid) {
  New-Item -ItemType Directory -Path $ClientData -Force | Out-Null
  [pscustomobject]@{ serverPid = $ServerPid; ngrokPid = $NgrokPid } |
    ConvertTo-Json | Set-Content -LiteralPath $StateFile -Encoding UTF8
}

function Get-ProcessInfo([int]$ProcessId) {
  if ($ProcessId -le 0) { return $null }
  return Get-CimInstance Win32_Process -Filter "ProcessId = $ProcessId" -ErrorAction SilentlyContinue
}

function Get-LocalServerPid {
  if (-not (Test-Server)) { return 0 }
  $listener = Get-NetTCPConnection -LocalPort 8000 -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $listener) { return 0 }
  $info = Get-ProcessInfo ([int]$listener.OwningProcess)
  if ($info -and $info.Name -eq 'node.exe' -and $info.CommandLine -match 'server\.js') { return [int]$listener.OwningProcess }
  return 0
}

function Get-LocalNgrokPid {
  if (-not (Get-TunnelUrl)) { return 0 }
  $listener = Get-NetTCPConnection -LocalPort 4040 -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $listener) { return 0 }
  $info = Get-ProcessInfo ([int]$listener.OwningProcess)
  if ($info -and $info.Name -eq 'ngrok.exe' -and $info.CommandLine -match '\bhttp\s+8000\b') { return [int]$listener.OwningProcess }
  return 0
}

function Test-Server([int]$TimeoutMs = 900) {
  try {
    $request = [System.Net.HttpWebRequest]::Create('http://127.0.0.1:8000/api/bootstrap-status')
    $request.Timeout = $TimeoutMs
    $request.Proxy = $null
    $response = $request.GetResponse()
    $ok = [int]$response.StatusCode -eq 200
    $response.Close()
    return $ok
  } catch { return $false }
}

function Get-TunnelUrl {
  try {
    $request = [System.Net.HttpWebRequest]::Create('http://127.0.0.1:4040/api/tunnels')
    $request.Timeout = 800
    $request.Proxy = $null
    $response = $request.GetResponse()
    $reader = New-Object System.IO.StreamReader($response.GetResponseStream())
    $data = $reader.ReadToEnd() | ConvertFrom-Json
    $reader.Close(); $response.Close()
    $tunnel = $data.tunnels | Where-Object { $_.proto -eq 'https' -and $_.config.addr -match ':8000$' } | Select-Object -First 1
    if ($tunnel) { return [string]$tunnel.public_url }
  } catch { }
  return ''
}

function Set-Status {
  if (Test-Server) { $serverValue.Text = 'Server: Đang chạy · http://127.0.0.1:8000' }
  else { $serverValue.Text = 'Server: Đang tắt' }
  $url = Get-TunnelUrl
  if ($url) { $tunnelValue.Text = "Ngrok: Đang chạy · $url"; $script:PublicUrl = $url }
  else { $tunnelValue.Text = 'Ngrok: Đang tắt'; $script:PublicUrl = '' }
  $openButton.Enabled = Test-Server
  $copyButton.Enabled = [bool]$script:PublicUrl
}

function Start-Server {
  if (Test-Server) { $script:ServerPid = Get-LocalServerPid; return }
  $listener = Get-NetTCPConnection -LocalPort 8000 -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($listener) { throw 'Cổng 8000 đang được một chương trình khác sử dụng.' }
  if (-not (Get-Command node.exe -ErrorAction SilentlyContinue)) { throw 'Không tìm thấy Node.js. Hãy cài Node.js rồi thử lại.' }
  if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot '.env'))) { throw 'Thiếu file .env trong thư mục dự án.' }
  if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot 'node_modules\pg'))) { throw 'Thiếu thư viện dự án. Hãy chạy npm install trong thư mục dự án.' }
  New-Item -ItemType Directory -Path $ClientData -Force | Out-Null
  $p = Start-Process -FilePath (Get-Command node.exe).Source -ArgumentList @('"' + $ServerScript + '"') -WorkingDirectory $ProjectRoot -WindowStyle Hidden -RedirectStandardOutput $StdoutLog -RedirectStandardError $StderrLog -PassThru
  $script:ServerPid = $p.Id
  Save-ClientState $script:ServerPid 0
  for ($i = 0; $i -lt 30; $i++) {
    Start-Sleep -Milliseconds 500
    if (Test-Server) { return }
    if ($p.HasExited) { break }
  }
  $detail = ''
  if (Test-Path -LiteralPath $StderrLog) { $detail = (Get-Content -LiteralPath $StderrLog -Tail 8) -join "`n" }
  try { if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force } } catch { }
  throw "Server không khởi động được. Kiểm tra PostgreSQL và file .env.`n$detail"
}

function Start-Tunnel {
  if (Get-TunnelUrl) { $script:NgrokPid = Get-LocalNgrokPid; return }
  if (-not $script:NgrokPath) { throw 'Không tìm thấy ngrok.exe.' }
  $p = Start-Process -FilePath $script:NgrokPath -ArgumentList @('http', '8000') -WorkingDirectory $ProjectRoot -WindowStyle Hidden -RedirectStandardOutput (Join-Path $ClientData 'ngrok.out.log') -RedirectStandardError (Join-Path $ClientData 'ngrok.err.log') -PassThru
  $script:NgrokPid = $p.Id
  for ($i = 0; $i -lt 24; $i++) {
    Start-Sleep -Milliseconds 500
    $url = Get-TunnelUrl
    if ($url) { $script:PublicUrl = $url; return }
    if ($p.HasExited) { break }
  }
  $detail = ''
  $ngrokLog = Join-Path $ClientData 'ngrok.err.log'
  if (Test-Path -LiteralPath $ngrokLog) { $detail = (Get-Content -LiteralPath $ngrokLog -Tail 8) -join "`n" }
  throw "Ngrok không mở được tunnel. Kiểm tra tài khoản ngrok và cấu hình authtoken.`n$detail"
}

function Start-All {
  try {
    $script:ServerPid = 0; $script:NgrokPid = 0
    New-Item -ItemType Directory -Path $ClientData -Force | Out-Null
    Start-Server
    Start-Tunnel
    Save-ClientState $script:ServerPid $script:NgrokPid
    Set-Status
    if ($script:PublicUrl) { [void][System.Windows.Forms.MessageBox]::Show("Server và ngrok đã chạy.`n$script:PublicUrl", 'Đã bật', 'OK', 'Information') }
  } catch { [void][System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Không bật được', 'OK', 'Error') }
}

function Stop-All {
  $state = Get-ClientState
  if ([int]$state.serverPid -le 0) { $state.serverPid = Get-LocalServerPid }
  if ([int]$state.ngrokPid -le 0) { $state.ngrokPid = Get-LocalNgrokPid }
  foreach ($entry in @(@{ pid = [int]$state.ngrokPid; kind = 'ngrok' }, @{ pid = [int]$state.serverPid; kind = 'server' })) {
    $info = Get-ProcessInfo $entry.pid
    if (-not $info) { continue }
    $expected = if ($entry.kind -eq 'server') {
      $portOwner = Get-NetTCPConnection -LocalPort 8000 -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
      $info.Name -eq 'node.exe' -and $info.CommandLine -match 'server\.js' -and $portOwner -and [int]$portOwner.OwningProcess -eq $entry.pid
    } else { $info.Name -eq 'ngrok.exe' -and $info.CommandLine -match '\bhttp\s+8000\b' }
    if ($expected) { Stop-Process -Id $entry.pid -Force -ErrorAction SilentlyContinue }
  }
  Remove-Item -LiteralPath $StateFile -Force -ErrorAction SilentlyContinue
  Start-Sleep -Milliseconds 400
  Set-Status
}

$script:PublicUrl = ''
$script:ServerPid = 0
$script:NgrokPid = 0
$script:NgrokPath = Find-Ngrok

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Quản lý server Giải đấu'
$form.StartPosition = 'CenterScreen'
$form.Size = New-Object System.Drawing.Size(560, 290)
$form.MinimumSize = New-Object System.Drawing.Size(560, 290)
$form.Font = New-Object System.Drawing.Font('Segoe UI', 10)
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false

$title = New-Object System.Windows.Forms.Label
$title.Text = 'Quản lý server giải đấu'
$title.Font = New-Object System.Drawing.Font('Segoe UI', 16, [System.Drawing.FontStyle]::Bold)
$title.Location = New-Object System.Drawing.Point(24, 20)
$title.AutoSize = $true
$form.Controls.Add($title)

$serverValue = New-Object System.Windows.Forms.Label
$serverValue.Location = New-Object System.Drawing.Point(28, 75)
$serverValue.Size = New-Object System.Drawing.Size(500, 25)
$form.Controls.Add($serverValue)

$tunnelValue = New-Object System.Windows.Forms.Label
$tunnelValue.Location = New-Object System.Drawing.Point(28, 105)
$tunnelValue.Size = New-Object System.Drawing.Size(500, 25)
$form.Controls.Add($tunnelValue)

$startButton = New-Object System.Windows.Forms.Button
$startButton.Text = 'Bật server + ngrok'
$startButton.Location = New-Object System.Drawing.Point(28, 155)
$startButton.Size = New-Object System.Drawing.Size(155, 40)
$startButton.Add_Click({ Start-All })
$form.Controls.Add($startButton)

$stopButton = New-Object System.Windows.Forms.Button
$stopButton.Text = 'Tắt tất cả'
$stopButton.Location = New-Object System.Drawing.Point(193, 155)
$stopButton.Size = New-Object System.Drawing.Size(115, 40)
$stopButton.Add_Click({ Stop-All })
$form.Controls.Add($stopButton)

$openButton = New-Object System.Windows.Forms.Button
$openButton.Text = 'Mở trang web'
$openButton.Location = New-Object System.Drawing.Point(318, 155)
$openButton.Size = New-Object System.Drawing.Size(115, 40)
$openButton.Add_Click({ if ($script:PublicUrl) { Start-Process $script:PublicUrl } else { Start-Process 'http://127.0.0.1:8000/giai-dau.html' } })
$form.Controls.Add($openButton)

$copyButton = New-Object System.Windows.Forms.Button
$copyButton.Text = 'Sao chép URL'
$copyButton.Location = New-Object System.Drawing.Point(443, 155)
$copyButton.Size = New-Object System.Drawing.Size(90, 40)
$copyButton.Add_Click({ if ($script:PublicUrl) { [System.Windows.Forms.Clipboard]::SetText($script:PublicUrl) } })
$form.Controls.Add($copyButton)

$note = New-Object System.Windows.Forms.Label
$note.Text = "Đóng cửa sổ này không tắt server. Dùng nút 'Tắt tất cả' để dừng server và tunnel."
$note.Location = New-Object System.Drawing.Point(28, 215)
$note.Size = New-Object System.Drawing.Size(500, 25)
$note.Font = New-Object System.Drawing.Font('Segoe UI', 8)
$form.Controls.Add($note)

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 2500
$timer.Add_Tick({ Set-Status })
$timer.Start()
$form.Add_Shown({ Set-Status })
$form.Add_FormClosed({ $timer.Stop(); $timer.Dispose() })
[void]$form.ShowDialog()
