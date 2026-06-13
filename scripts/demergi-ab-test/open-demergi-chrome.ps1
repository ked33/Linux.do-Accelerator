param(
  [string]$ProxyAddress = "127.0.0.1:18080",
  [string]$Url = "https://linux.do/",
  [string]$ProfilePath = (Join-Path $env:LOCALAPPDATA "linuxdo\demergi-ab-test\chrome-profile"),
  [string]$ChromePath,
  [switch]$DryRun
)

$ErrorActionPreference = "Stop"

function Resolve-ChromePath {
  param([string]$RequestedPath)

  if (-not [string]::IsNullOrWhiteSpace($RequestedPath)) {
    return $RequestedPath
  }

  $candidates = @(
    (Join-Path $env:ProgramFiles "Google\Chrome\Application\chrome.exe")
  )

  if (-not [string]::IsNullOrWhiteSpace(${env:ProgramFiles(x86)})) {
    $candidates += Join-Path ${env:ProgramFiles(x86)} "Google\Chrome\Application\chrome.exe"
  }

  foreach ($candidate in $candidates) {
    if (Test-Path -LiteralPath $candidate) {
      return $candidate
    }
  }

  throw "chrome.exe not found. Pass -ChromePath with the full path to chrome.exe."
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

function Test-TcpPort {
  param(
    [string]$HostName,
    [int]$Port,
    [int]$TimeoutMs = 300
  )

  $client = New-Object System.Net.Sockets.TcpClient
  try {
    $async = $client.BeginConnect($HostName, $Port, $null, $null)
    if (-not $async.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) {
      return $false
    }
    $client.EndConnect($async)
    return $true
  } catch {
    return $false
  } finally {
    $client.Close()
  }
}

function Get-ChromeProxyBypassList {
  $private172 = 16..31 | ForEach-Object { "172.$_.*" }
  @(
    "<local>",
    "localhost",
    "127.*",
    "[::1]",
    "10.*",
    $private172,
    "192.168.*",
    "169.254.*"
  ) | ForEach-Object { $_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
}

$chrome = Resolve-ChromePath -RequestedPath $ChromePath
$endpoint = Get-ProxyEndpoint -Address $ProxyAddress
$proxyBypassList = (Get-ChromeProxyBypassList) -join ";"

$args = @(
  "--user-data-dir=$ProfilePath",
  "--proxy-server=http://$ProxyAddress",
  "--proxy-bypass-list=$proxyBypassList",
  "--disable-quic",
  "--disable-background-networking",
  "--disable-sync",
  "--no-first-run",
  "--no-default-browser-check",
  "--new-window",
  $Url
)

if ($DryRun) {
  Write-Host "Dry run only."
  Write-Host "Chrome: $chrome"
  Write-Host "Profile: $ProfilePath"
  Write-Host "Proxy: $ProxyAddress"
  Write-Host "Proxy bypass list: $proxyBypassList"
  Write-Host "URL: $Url"
  Write-Host "Arguments:"
  $args | ForEach-Object { Write-Host "  $_" }
  exit 0
}

if (-not (Test-TcpPort -HostName $endpoint.Host -Port $endpoint.Port -TimeoutMs 500)) {
  throw "Demergi is not listening on $ProxyAddress. Run start-demergi-windows.ps1 first."
}

New-Item -ItemType Directory -Force -Path $ProfilePath | Out-Null

& $chrome @args
