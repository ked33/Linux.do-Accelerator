param(
  [string]$ProxyAddress = "127.0.0.1:18080",
  [int]$SampleSeconds = 0
)

$ErrorActionPreference = "Stop"

function Get-StateDir {
  $base = $env:LOCALAPPDATA
  if ([string]::IsNullOrWhiteSpace($base)) {
    $base = Join-Path $HOME "AppData\Local"
  }
  Join-Path $base "linuxdo\demergi-ab-test"
}

function Get-ProxyEndpoint {
  param([string]$Address)

  if ($Address -notmatch "^(?<host>[^:]+):(?<port>\d+)$") {
    throw "ProxyAddress must use host:port format, for example 127.0.0.1:18080"
  }

  [pscustomobject]@{
    Host = $Matches.host
    Port = [int]$Matches.port
  }
}

$stateDir = Get-StateDir
$pidPath = Join-Path $stateDir "demergi.pid"
$stdoutPath = Join-Path $stateDir "demergi.stdout.log"
$stderrPath = Join-Path $stateDir "demergi.stderr.log"
$managedProxyFlagPath = Join-Path $stateDir "system-proxy-managed.flag"
$endpoint = Get-ProxyEndpoint -Address $ProxyAddress

Write-Host "State directory: $stateDir"
Write-Host "PID file: $pidPath"
Write-Host "Managed proxy marker: $managedProxyFlagPath"

$demergiPid = $null
if (Test-Path -LiteralPath $pidPath) {
  $pidText = Get-Content -LiteralPath $pidPath -ErrorAction SilentlyContinue | Select-Object -First 1
  $parsedPid = 0
  if ([int]::TryParse($pidText, [ref]$parsedPid)) {
    $demergiPid = $parsedPid
  }
}

if ($demergiPid) {
  $process = Get-Process -Id $demergiPid -ErrorAction SilentlyContinue
  if ($process) {
    $row = [ordered]@{
      Id = $process.Id
      ProcessName = $process.ProcessName
      CPU = $process.CPU
      StartTime = $process.StartTime
    }

    if ($SampleSeconds -gt 0) {
      $cores = (Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors
      $cpuStart = $process.CPU
      Start-Sleep -Seconds $SampleSeconds
      $processAfter = Get-Process -Id $demergiPid -ErrorAction SilentlyContinue
      if ($processAfter) {
        $row["CpuPercent"] = [math]::Round((($processAfter.CPU - $cpuStart) / $SampleSeconds / $cores * 100), 2)
      }
    }

    [pscustomobject]$row | Format-List
  } else {
    Write-Host "Demergi PID $demergiPid is not running."
  }
} else {
  Write-Host "No valid Demergi PID was found."
}

Write-Host ""
Write-Host "Listener:"
Get-NetTCPConnection -LocalAddress $endpoint.Host -LocalPort $endpoint.Port -ErrorAction SilentlyContinue |
  Select-Object LocalAddress,LocalPort,State,OwningProcess |
  Format-Table -AutoSize

Write-Host ""
Write-Host "Windows user proxy settings:"
$settingsKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
$proxySettings = Get-ItemProperty -Path $settingsKey -Name AutoConfigURL,ProxyEnable,ProxyServer,ProxyOverride,AutoDetect -ErrorAction SilentlyContinue
$proxySettings |
  Select-Object AutoConfigURL,ProxyEnable,ProxyServer,ProxyOverride,AutoDetect |
  Format-List

if ($proxySettings) {
  $autoConfigUrl = [string]$proxySettings.AutoConfigURL
  $proxyServer = [string]$proxySettings.ProxyServer
  if ($autoConfigUrl -match "(?i)linuxdo-demergi\.pac" -and $proxyServer -and $proxyServer -ne $ProxyAddress) {
    Write-Host "Warning: Demergi PAC is present while Windows manual proxy points to $proxyServer."
    Write-Host "Ordinary Chrome may still follow the manual proxy. Use mihomo rules to route linux.do to $ProxyAddress, or clear the stale PAC by running start-demergi-windows.ps1 without -UseSystemPac."
  }
}

if (Test-Path -LiteralPath $managedProxyFlagPath) {
  Write-Host ""
  Write-Host "Demergi-managed Windows proxy mode:"
  Get-Content -LiteralPath $managedProxyFlagPath -ErrorAction SilentlyContinue | Select-Object -First 1
}

Write-Host ""
Write-Host "Logs:"
$logRows = foreach ($path in @($stdoutPath, $stderrPath)) {
  if (Test-Path -LiteralPath $path) {
    $item = Get-Item -LiteralPath $path
    [pscustomobject]@{
      Name = $item.Name
      Length = $item.Length
      LastWriteTime = $item.LastWriteTime
      Path = $item.FullName
    }
  } else {
    [pscustomobject]@{
      Name = Split-Path -Leaf $path
      Length = $null
      LastWriteTime = $null
      Path = $path
    }
  }
}
$logRows | Format-Table -AutoSize

if (Test-Path -LiteralPath $stderrPath) {
  Write-Host ""
  Write-Host "Recent stderr:"
  Get-Content -LiteralPath $stderrPath -Tail 20
}
