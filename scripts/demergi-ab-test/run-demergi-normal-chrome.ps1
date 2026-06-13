param(
  [string]$ProxyAddress = "127.0.0.1:18080",
  [ValidateSet("plain", "doh", "dot")]
  [string]$DnsMode = "plain",
  [string]$DohUrl = "https://223.5.5.5/dns-query",
  [string]$DnsIpOverridesPath = (Join-Path $PSScriptRoot "linuxdo_dpi_overrides.json"),
  [int]$ClientHelloSize = 40,
  [ValidateSet("1.0", "1.1", "1.2", "1.3")]
  [string]$ClientHelloTLSv = "1.3",
  [ValidateSet("none", "error", "warn", "info", "debug")]
  [string]$LogLevel = "warn",
  [switch]$DryRun
)

$ErrorActionPreference = "Stop"

function Resolve-DnsIpOverridesPath {
  param([string]$Path)

  if ([string]::IsNullOrWhiteSpace($Path)) {
    return ""
  }

  if (Test-Path -LiteralPath $Path) {
    return $Path
  }

  $sourceTreePath = Join-Path (Split-Path -Parent $PSScriptRoot) (Split-Path -Leaf $Path)
  if (Test-Path -LiteralPath $sourceTreePath) {
    return $sourceTreePath
  }

  return $Path
}

$startScript = Join-Path $PSScriptRoot "start-demergi-windows.ps1"
if (-not (Test-Path -LiteralPath $startScript)) {
  throw "start-demergi-windows.ps1 not found: $startScript"
}

$DnsIpOverridesPath = Resolve-DnsIpOverridesPath -Path $DnsIpOverridesPath

$startArgs = @{
  ProxyAddress = $ProxyAddress
  DnsMode = $DnsMode
  DohUrl = $DohUrl
  DnsIpOverridesPath = $DnsIpOverridesPath
  ClientHelloSize = $ClientHelloSize
  ClientHelloTLSv = $ClientHelloTLSv
  LogLevel = $LogLevel
  NoSystemProxy = $true
  Restart = $true
}

if ($DryRun) {
  Write-Host "Dry run only."
  Write-Host "Start script: $startScript"
  Write-Host "Proxy: $ProxyAddress"
  Write-Host "Windows proxy mode: unchanged"
  Write-Host "mihomo-compatible mode: route linux.do to $ProxyAddress in mihomo if ordinary Chrome should use Demergi."
  Write-Host "DNS mode: $DnsMode"
  Write-Host "DoH URL: $DohUrl"
  Write-Host "DNS IP overrides: $DnsIpOverridesPath"
  Write-Host "ClientHello size: $ClientHelloSize"
  Write-Host "ClientHello TLS version: $ClientHelloTLSv"
  Write-Host "Log level: $LogLevel"
  exit 0
}

& $startScript @startArgs
Write-Host "Demergi is running on $ProxyAddress."
Write-Host "Windows proxy settings were not changed."
Write-Host "For ordinary Chrome behind mihomo, route linux.do/idcflare domains to this local HTTP proxy in mihomo."
