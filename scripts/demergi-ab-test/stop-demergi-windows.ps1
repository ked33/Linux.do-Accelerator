param(
  [switch]$NoSystemProxy,
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

function Restore-ProxySettings {
  param([string]$BackupPath)

  if (-not (Test-Path -LiteralPath $BackupPath)) {
    Write-Host "No proxy settings backup found: $BackupPath"
    return
  }

  $backup = Get-Content -LiteralPath $BackupPath -Raw | ConvertFrom-Json
  $keyPath = $backup.KeyPath
  $values = $backup.Values

  foreach ($property in $values.PSObject.Properties) {
    $name = $property.Name
    $entry = $property.Value

    if ($entry.Exists) {
      if ($name -eq "ProxyEnable" -or $name -eq "AutoDetect") {
        New-ItemProperty -Path $keyPath -Name $name -Value ([int]$entry.Value) -PropertyType DWord -Force | Out-Null
      } else {
        New-ItemProperty -Path $keyPath -Name $name -Value ([string]$entry.Value) -PropertyType String -Force | Out-Null
      }
    } else {
      Remove-ItemProperty -Path $keyPath -Name $name -Force -ErrorAction SilentlyContinue
    }
  }

  Invoke-InternetSettingsRefresh
  Remove-Item -LiteralPath $BackupPath -Force -ErrorAction SilentlyContinue
  Write-Host "System proxy settings restored."
  Write-Host "Proxy settings backup cleared."
}

$stateDir = Get-StateDir
$pidPath = Join-Path $stateDir "demergi.pid"
$backupPath = Join-Path $stateDir "proxy-settings-backup.json"

if ($DryRun) {
  Write-Host "Dry run only."
  Write-Host "State: $stateDir"
  Write-Host "PID file: $pidPath"
  Write-Host "Backup: $backupPath"
  exit 0
}

if (Test-Path -LiteralPath $pidPath) {
  $pidText = Get-Content -LiteralPath $pidPath -ErrorAction SilentlyContinue | Select-Object -First 1
  $demergiPid = 0
  if ([int]::TryParse($pidText, [ref]$demergiPid)) {
    $process = Get-Process -Id $demergiPid -ErrorAction SilentlyContinue
    if ($process) {
      Stop-Process -Id $demergiPid -Force
      Write-Host "Stopped Demergi process PID $demergiPid."
    } else {
      Write-Host "Demergi PID $demergiPid is not running."
    }
  } else {
    Write-Host "PID file exists but does not contain a valid PID."
  }
  Remove-Item -LiteralPath $pidPath -Force -ErrorAction SilentlyContinue
} else {
  Write-Host "No Demergi PID file found."
}

if (-not $NoSystemProxy) {
  Restore-ProxySettings -BackupPath $backupPath
} else {
  Write-Host "System proxy settings were not changed."
}
