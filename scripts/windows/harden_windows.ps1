<#
Safe Windows hardening helper with list/dry-run/apply/backup/restore modes.
Run in elevated PowerShell for apply/backup/restore.
#>
param(
  [ValidateSet("list", "dry-run", "apply", "backup", "restore")]
  [string]$Mode = "list",
  [string[]]$MgmtIps = @(),
  [switch]$RestrictRdp,
  [switch]$BlockRdp,
  [switch]$RestrictWinrm,
  [switch]$BlockWinrm,
  [switch]$EnableFirewall,
  [switch]$EnableFirewallAll,
  [switch]$EnableDefender,
  [switch]$EnableAuditing,
  [int[]]$AllowPorts = @(),
  [string]$BackupDir = "",
  [string]$RestoreFrom = "",
  [switch]$AllowUnsafe
)

function Write-Log {
  param([string]$Message)
  $ts = Get-Date -Format "HH:mm:ss"
  Write-Host "[$ts] $Message"
}

function Test-Admin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = New-Object Security.Principal.WindowsPrincipal($id)
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-DefaultBackupDir {
  $ts = Get-Date -Format "yyyyMMdd-HHmmss"
  $root = Resolve-Path (Join-Path $PSScriptRoot "..\..")
  return Join-Path $root "artifacts\backups\$env:COMPUTERNAME-$ts\windows"
}

function Probe-System {
  Write-Log "Probes: system status"
  if (Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue) {
    Get-MpComputerStatus | Select-Object AMServiceEnabled, RealTimeProtectionEnabled | Format-Table -AutoSize
  }
  Get-NetFirewallProfile | Format-Table -AutoSize
  $rdp = Get-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections -ErrorAction SilentlyContinue
  if ($rdp) {
    Write-Log "RDP fDenyTSConnections = $($rdp.fDenyTSConnections)"
  }
  if (Get-Command auditpol.exe -ErrorAction SilentlyContinue) {
    auditpol /get /category:* | Select-Object -First 5 | Out-Host
  }
}

function List-Configs {
  Write-Log "Listing key configs"
  Get-NetFirewallRule -DisplayName 'MACCDC-*' -ErrorAction SilentlyContinue | Select-Object DisplayName, Enabled, Direction, Action | Format-Table -AutoSize
  if (Get-Command winrm -ErrorAction SilentlyContinue) {
    winrm enumerate winrm/config/listener | Out-Host
  }
}

function Ensure-SafeMgmtIp {
  if ($AllowUnsafe) { return }
  if (-not $RestrictRdp -and -not $RestrictWinrm) { return }
  if ($MgmtIps.Count -eq 0) { throw "-MgmtIps is required for restriction." }
  $active = Get-NetTCPConnection -LocalPort 3389 -State Established -ErrorAction SilentlyContinue | Select-Object -ExpandProperty RemoteAddress
  if ($active) {
    foreach ($addr in $active) {
      if ($addr -and ($MgmtIps -notcontains $addr)) {
        throw "Active RDP connection from $addr is not in -MgmtIps; use -AllowUnsafe to override."
      }
    }
  }
}

function Plan-Changes {
  Write-Log "Planned changes"
  if ($EnableFirewall) { Write-Host "- Would enable Windows Firewall (Domain/Private)" }
  if ($EnableFirewallAll) { Write-Host "- Would enable Windows Firewall for all profiles" }
  if ($EnableDefender) { Write-Host "- Would enable Microsoft Defender and real-time protection" }
  if ($EnableAuditing) { Write-Host "- Would enable key audit policies" }
  if ($AllowPorts.Count -gt 0) { Write-Host "- Would allow inbound ports: $($AllowPorts -join ', ')" }
  if ($RestrictRdp) { Write-Host "- Would restrict RDP to mgmt IPs" }
  if ($BlockRdp) { Write-Host "- Would block RDP from non-mgmt IPs" }
  if ($RestrictWinrm) { Write-Host "- Would restrict WinRM to mgmt IPs" }
  if ($BlockWinrm) { Write-Host "- Would block WinRM from non-mgmt IPs" }
}

function Backup-Configs {
  $dir = if ([string]::IsNullOrWhiteSpace($BackupDir)) { Get-DefaultBackupDir } else { $BackupDir }
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  $fw = Join-Path $dir "firewall.wfw"
  $sec = Join-Path $dir "security-policy.cfg"
  $audit = Join-Path $dir "auditpol.txt"
  $rdp = Join-Path $dir "rdp.txt"
  netsh advfirewall export $fw | Out-Null
  secedit /export /cfg $sec | Out-Null
  auditpol /get /category:* | Out-File -FilePath $audit -Encoding UTF8
  Get-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections | Out-File -FilePath $rdp -Encoding UTF8
  Write-Log "Backup created in: $dir"
}

function Restore-Configs {
  if ([string]::IsNullOrWhiteSpace($RestoreFrom)) { throw "-RestoreFrom is required." }
  if (-not (Test-Path $RestoreFrom)) { throw "Restore path not found: $RestoreFrom" }
  $fw = Join-Path $RestoreFrom "firewall.wfw"
  $sec = Join-Path $RestoreFrom "security-policy.cfg"
  if (Test-Path $fw) { netsh advfirewall import $fw | Out-Null }
  if (Test-Path $sec) { secedit /configure /db secedit.sdb /cfg $sec /areas SECURITYPOLICY | Out-Null }
  Write-Log "Restore applied from: $RestoreFrom"
}

function Apply-Changes {
  Ensure-SafeMgmtIp

  if ($EnableFirewallAll) {
    Set-NetFirewallProfile -Profile Domain,Private,Public -Enabled True
  } elseif ($EnableFirewall) {
    Set-NetFirewallProfile -Profile Domain,Private -Enabled True
  }

  if ($EnableDefender -and (Get-Command Set-MpPreference -ErrorAction SilentlyContinue)) {
    Set-MpPreference -DisableRealtimeMonitoring $false
    Start-Service -Name WinDefend -ErrorAction SilentlyContinue
  }

  if ($EnableAuditing) {
    auditpol /set /category:"Logon/Logoff" /success:enable /failure:enable | Out-Null
    auditpol /set /category:"Account Logon" /success:enable /failure:enable | Out-Null
    auditpol /set /category:"Account Management" /success:enable /failure:enable | Out-Null
    auditpol /set /category:"Policy Change" /success:enable /failure:enable | Out-Null
    auditpol /set /category:"Privilege Use" /success:enable /failure:enable | Out-Null
  }

  foreach ($p in $AllowPorts) {
    New-NetFirewallRule -DisplayName "MACCDC-Allow-$p" -Direction Inbound -Action Allow -Protocol TCP -LocalPort $p -Profile Any -ErrorAction SilentlyContinue | Out-Null
  }

  if ($RestrictRdp) {
    if ($MgmtIps.Count -eq 0) { throw "-MgmtIps is required for -RestrictRdp" }
    New-NetFirewallRule -DisplayName "MACCDC-Allow-RDP" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 3389 -RemoteAddress $MgmtIps -Profile Any -ErrorAction SilentlyContinue | Out-Null
  }
  if ($BlockRdp) {
    New-NetFirewallRule -DisplayName "MACCDC-Block-RDP" -Direction Inbound -Action Block -Protocol TCP -LocalPort 3389 -Profile Any -ErrorAction SilentlyContinue | Out-Null
  }

  if ($RestrictWinrm) {
    if ($MgmtIps.Count -eq 0) { throw "-MgmtIps is required for -RestrictWinrm" }
    New-NetFirewallRule -DisplayName "MACCDC-Allow-WinRM" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 5985,5986 -RemoteAddress $MgmtIps -Profile Any -ErrorAction SilentlyContinue | Out-Null
  }
  if ($BlockWinrm) {
    New-NetFirewallRule -DisplayName "MACCDC-Block-WinRM" -Direction Inbound -Action Block -Protocol TCP -LocalPort 5985,5986 -Profile Any -ErrorAction SilentlyContinue | Out-Null
  }
}

try {
  switch ($Mode) {
    "list" {
      Probe-System
      List-Configs
    }
    "dry-run" {
      Probe-System
      Plan-Changes
    }
    "backup" {
      if (-not (Test-Admin)) { throw "This mode requires admin." }
      Backup-Configs
    }
    "restore" {
      if (-not (Test-Admin)) { throw "This mode requires admin." }
      Restore-Configs
    }
    "apply" {
      if (-not (Test-Admin)) { throw "This mode requires admin." }
      Probe-System
      Plan-Changes
      Backup-Configs
      Apply-Changes
    }
    default { throw "Unknown mode: $Mode" }
  }
} catch {
  Write-Error $_.Exception.Message
  exit 1
}
