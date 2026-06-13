param(
  [string]$ProxyAddress = "127.0.0.1:18080",
  [string]$DemergiPath = (Join-Path $PSScriptRoot "demergi.exe"),
  [string]$PacPath = (Join-Path $PSScriptRoot "linuxdo-demergi.pac"),
  [ValidateSet("plain", "doh", "dot")]
  [string]$DnsMode = "plain",
  [string]$DohUrl = "https://223.5.5.5/dns-query",
  [string]$DnsIpOverridesPath = (Join-Path $PSScriptRoot "linuxdo_dpi_overrides.json"),
  [int]$ClientHelloSize = 40,
  [ValidateSet("1.0", "1.1", "1.2", "1.3")]
  [string]$ClientHelloTLSv = "1.3",
  [ValidateSet("none", "error", "warn", "info", "debug")]
  [string]$LogLevel = "warn",
  [switch]$NoSystemProxy,
  [switch]$UseSystemProxy,
  [switch]$UseSystemPac,
  [switch]$Restart,
  [switch]$DryRun
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

function Invoke-InternetSettingsRefresh {
  try {
    $wininet = [Native.WinInet]
  } catch {
    $member = @"
[DllImport("wininet.dll", SetLastError = true)]
public static extern bool InternetSetOption(IntPtr hInternet, int dwOption, IntPtr lpBuffer, int dwBufferLength);
"@
    $wininet = Add-Type -MemberDefinition $member -Name WinInet -Namespace Native -PassThru
  }

  [void]$wininet::InternetSetOption([IntPtr]::Zero, 39, [IntPtr]::Zero, 0)
  [void]$wininet::InternetSetOption([IntPtr]::Zero, 37, [IntPtr]::Zero, 0)
}

function Save-ProxySettings {
  param(
    [string]$BackupPath,
    [string]$KeyPath
  )

  if (Test-Path -LiteralPath $BackupPath) {
    Write-Host "Existing proxy settings backup preserved: $BackupPath"
    return
  }

  $names = @("AutoConfigURL", "ProxyEnable", "ProxyServer", "ProxyOverride", "AutoDetect")
  $values = [ordered]@{}

  foreach ($name in $names) {
    try {
      $item = Get-ItemProperty -Path $KeyPath -Name $name -ErrorAction Stop
      $values[$name] = [ordered]@{
        Exists = $true
        Value = $item.$name
      }
    } catch {
      $values[$name] = [ordered]@{
        Exists = $false
        Value = $null
      }
    }
  }

  $backup = [ordered]@{
    CreatedAt = (Get-Date).ToUniversalTime().ToString("o")
    KeyPath = $KeyPath
    Values = $values
  }
  $backup | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $BackupPath -Encoding ASCII
}

function Set-DWordProperty {
  param(
    [string]$Path,
    [string]$Name,
    [int]$Value
  )

  New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType DWord -Force | Out-Null
}

function Set-StringProperty {
  param(
    [string]$Path,
    [string]$Name,
    [string]$Value
  )

  New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType String -Force | Out-Null
}

function Remove-PropertyIfExists {
  param(
    [string]$Path,
    [string]$Name
  )

  Remove-ItemProperty -Path $Path -Name $Name -Force -ErrorAction SilentlyContinue
}

function Test-DemergiPacUrl {
  param([string]$Value)

  if ([string]::IsNullOrWhiteSpace($Value)) {
    return $false
  }

  return $Value -match "(?i)(^file:///.*linuxdo-demergi\.pac$|linuxdo-demergi\.pac$)"
}

function Clear-DemergiPacIfPresent {
  param([string]$KeyPath)

  try {
    $item = Get-ItemProperty -Path $KeyPath -Name "AutoConfigURL" -ErrorAction Stop
  } catch {
    return $false
  }

  $autoConfigUrl = [string]$item.AutoConfigURL
  if (-not (Test-DemergiPacUrl -Value $autoConfigUrl)) {
    return $false
  }

  Remove-PropertyIfExists -Path $KeyPath -Name "AutoConfigURL"
  return $true
}

function Get-SystemProxyBypassList {
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

$stateDir = Get-StateDir
$pidPath = Join-Path $stateDir "demergi.pid"
$backupPath = Join-Path $stateDir "proxy-settings-backup.json"
$managedProxyFlagPath = Join-Path $stateDir "system-proxy-managed.flag"
$stdoutPath = Join-Path $stateDir "demergi.stdout.log"
$stderrPath = Join-Path $stateDir "demergi.stderr.log"
$settingsKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
$endpoint = Get-ProxyEndpoint -Address $ProxyAddress
$DnsIpOverridesPath = Resolve-DnsIpOverridesPath -Path $DnsIpOverridesPath

if ($DryRun) {
  Write-Host "Dry run only."
  Write-Host "Demergi: $DemergiPath"
  Write-Host "PAC: $PacPath"
  Write-Host "DNS mode: $DnsMode"
  Write-Host "DoH URL: $DohUrl"
  Write-Host "DNS IP overrides: $DnsIpOverridesPath"
  Write-Host "Proxy: $ProxyAddress"
  Write-Host "State: $stateDir"
  Write-Host "Manual system proxy: $([bool]$UseSystemProxy)"
  Write-Host "System PAC: $([bool]$UseSystemPac)"
  if (-not $UseSystemProxy -and -not $UseSystemPac) {
    Write-Host "Windows proxy mode: unchanged"
    Write-Host "Stale Demergi PAC cleanup: enabled"
  }
  if ($UseSystemProxy) {
    Write-Host "Manual proxy bypass: $((Get-SystemProxyBypassList) -join ';')"
  }
  exit 0
}

$systemModes = @($NoSystemProxy, $UseSystemProxy, $UseSystemPac) | Where-Object { $_ }
if ($systemModes.Count -gt 1) {
  throw "Use only one of -NoSystemProxy, -UseSystemProxy, or -UseSystemPac."
}

if (-not (Test-Path -LiteralPath $DemergiPath)) {
  throw "demergi.exe not found: $DemergiPath"
}
if ($UseSystemPac -and -not (Test-Path -LiteralPath $PacPath)) {
  throw "PAC file not found: $PacPath"
}
if (-not [string]::IsNullOrWhiteSpace($DnsIpOverridesPath) -and -not (Test-Path -LiteralPath $DnsIpOverridesPath)) {
  Write-Host "DNS IP overrides file not found, continuing without it: $DnsIpOverridesPath"
  $DnsIpOverridesPath = ""
}

New-Item -ItemType Directory -Force -Path $stateDir | Out-Null

if (Test-Path -LiteralPath $pidPath) {
  $oldPidText = Get-Content -LiteralPath $pidPath -ErrorAction SilentlyContinue | Select-Object -First 1
  $oldPid = 0
  if ([int]::TryParse($oldPidText, [ref]$oldPid)) {
    $oldProcess = Get-Process -Id $oldPid -ErrorAction SilentlyContinue
    if ($oldProcess) {
      if ($Restart) {
        Stop-Process -Id $oldPid -Force
        Wait-Process -Id $oldPid -Timeout 5 -ErrorAction SilentlyContinue
        Write-Host "Stopped existing Demergi process PID $oldPid."
      } else {
        throw "Demergi already appears to be running with PID $oldPid. Run stop-demergi-windows.ps1 first or pass -Restart."
      }
    }
  }
  Remove-Item -LiteralPath $pidPath -Force -ErrorAction SilentlyContinue
}

if (Test-TcpPort -HostName $endpoint.Host -Port $endpoint.Port -TimeoutMs 200) {
  throw "Port $ProxyAddress is already in use. Choose another ProxyAddress or stop the process using it."
}

$args = @(
  "--addrs", $ProxyAddress,
  "--dns-mode", $DnsMode,
  "--https-clienthello-size", [string]$ClientHelloSize,
  "--https-clienthello-tlsv", $ClientHelloTLSv,
  "--log-level", $LogLevel
)

if ($DnsMode -eq "doh") {
  $args += @("--doh-url", $DohUrl)
}
if (-not [string]::IsNullOrWhiteSpace($DnsIpOverridesPath)) {
  $args += @("--dns-ip-overrides", $DnsIpOverridesPath)
}

$process = Start-Process -FilePath $DemergiPath `
  -ArgumentList $args `
  -PassThru `
  -WindowStyle Hidden `
  -RedirectStandardOutput $stdoutPath `
  -RedirectStandardError $stderrPath

Set-Content -LiteralPath $pidPath -Value ([string]$process.Id) -Encoding ASCII

$ready = $false
for ($i = 0; $i -lt 30; $i++) {
  Start-Sleep -Milliseconds 250
  if (Test-TcpPort -HostName $endpoint.Host -Port $endpoint.Port -TimeoutMs 200) {
    $ready = $true
    break
  }
  if ($process.HasExited) {
    break
  }
}

if (-not $ready) {
  $exitText = if ($process.HasExited) { " Process exited with code $($process.ExitCode)." } else { "" }
  throw "Demergi did not start listening on $ProxyAddress.$exitText See $stderrPath"
}

if ($UseSystemProxy) {
  if ((-not (Test-Path -LiteralPath $managedProxyFlagPath)) -and (Test-Path -LiteralPath $backupPath)) {
    Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue
    Write-Host "Removed stale Demergi proxy settings backup."
  }
  Save-ProxySettings -BackupPath $backupPath -KeyPath $settingsKey
  Remove-PropertyIfExists -Path $settingsKey -Name "AutoConfigURL"
  Set-StringProperty -Path $settingsKey -Name "ProxyServer" -Value $ProxyAddress
  Set-StringProperty -Path $settingsKey -Name "ProxyOverride" -Value ((Get-SystemProxyBypassList) -join ";")
  Set-DWordProperty -Path $settingsKey -Name "ProxyEnable" -Value 1
  Set-DWordProperty -Path $settingsKey -Name "AutoDetect" -Value 0
  Invoke-InternetSettingsRefresh
  Set-Content -LiteralPath $managedProxyFlagPath -Value "manual" -Encoding ASCII
  Write-Host "System manual proxy enabled: $ProxyAddress"
  Write-Host "LAN/private IP ranges are bypassed, but non-linux.do web traffic may still use Demergi."
  Write-Host "For normal use, prefer PAC mode: .\start-demergi-windows.ps1 -UseSystemPac -Restart"
  Write-Host "Ordinary Chrome should now use Demergi. If it does not, restart Chrome."
} elseif ($UseSystemPac) {
  if ((-not (Test-Path -LiteralPath $managedProxyFlagPath)) -and (Test-Path -LiteralPath $backupPath)) {
    Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue
    Write-Host "Removed stale Demergi proxy settings backup."
  }
  Save-ProxySettings -BackupPath $backupPath -KeyPath $settingsKey
  $pacUri = ([System.Uri]((Resolve-Path -LiteralPath $PacPath).Path)).AbsoluteUri
  Remove-PropertyIfExists -Path $settingsKey -Name "ProxyServer"
  Remove-PropertyIfExists -Path $settingsKey -Name "ProxyOverride"
  Set-StringProperty -Path $settingsKey -Name "AutoConfigURL" -Value $pacUri
  Set-DWordProperty -Path $settingsKey -Name "ProxyEnable" -Value 0
  Set-DWordProperty -Path $settingsKey -Name "AutoDetect" -Value 0
  Invoke-InternetSettingsRefresh
  Set-Content -LiteralPath $managedProxyFlagPath -Value "pac" -Encoding ASCII
  Write-Host "System PAC enabled: $pacUri"
  Write-Host "Only linux.do/idcflare domains are routed to Demergi; other traffic stays DIRECT."
} else {
  $clearedPac = Clear-DemergiPacIfPresent -KeyPath $settingsKey
  Remove-Item -LiteralPath $managedProxyFlagPath -Force -ErrorAction SilentlyContinue
  if ($clearedPac) {
    Invoke-InternetSettingsRefresh
    Write-Host "Cleared stale Demergi PAC from Windows proxy settings."
  }
  Write-Host "Windows proxy target was not changed."
  Write-Host "Open linux.do with: .\open-demergi-chrome.ps1"
  Write-Host "For ordinary Chrome behind mihomo, route linux.do/idcflare domains to $ProxyAddress in mihomo."
}

Write-Host "Demergi started on $ProxyAddress with PID $($process.Id)."
Write-Host "State directory: $stateDir"
