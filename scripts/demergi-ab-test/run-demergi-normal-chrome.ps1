param(
  [string]$ProxyAddress = "127.0.0.1:18080",
  [ValidateSet("plain", "doh", "dot")]
  [string]$DnsMode = "doh",
  [string]$DohUrl = "https://1.0.0.1/dns-query",
  [int]$ClientHelloSize = 40,
  [ValidateSet("1.0", "1.1", "1.2", "1.3")]
  [string]$ClientHelloTLSv = "1.3",
  [ValidateSet("none", "error", "warn", "info", "debug")]
  [string]$LogLevel = "warn",
  [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$startScript = Join-Path $PSScriptRoot "start-demergi-windows.ps1"
if (-not (Test-Path -LiteralPath $startScript)) {
  throw "start-demergi-windows.ps1 not found: $startScript"
}

$startArgs = @{
  ProxyAddress = $ProxyAddress
  DnsMode = $DnsMode
  DohUrl = $DohUrl
  ClientHelloSize = $ClientHelloSize
  ClientHelloTLSv = $ClientHelloTLSv
  LogLevel = $LogLevel
  UseSystemProxy = $true
  Restart = $true
}

if ($DryRun) {
  Write-Host "Dry run only."
  Write-Host "Start script: $startScript"
  Write-Host "Proxy: $ProxyAddress"
  Write-Host "DNS mode: $DnsMode"
  Write-Host "DoH URL: $DohUrl"
  Write-Host "ClientHello size: $ClientHelloSize"
  Write-Host "ClientHello TLS version: $ClientHelloTLSv"
  Write-Host "Log level: $LogLevel"
  exit 0
}

& $startScript @startArgs
Write-Host "Windows manual proxy is enabled for the current user."
Write-Host "Open https://linux.do/ manually in ordinary Chrome. Restart Chrome if it still uses the old proxy state."
