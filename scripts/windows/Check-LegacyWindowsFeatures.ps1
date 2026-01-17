[CmdletBinding(SupportsShouldProcess=$true)]
param(
  [switch]$AuditOnly,
  [string]$LogPath = ".\LegacyServices_Hardening.log",
  [string]$CsvPath = ".\LegacyServices_Hardening_Report.csv"
)

# ---------------- Helpers ----------------
function Write-Log {
  param([string]$Message, [string]$Level = "INFO")
  $line = "{0} [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message
  Add-Content -Path $LogPath -Value $line
  Write-Host $line
}

function Ensure-RegistryValue {
  param(
    [Parameter(Mandatory)] [string]$Path,
    [Parameter(Mandatory)] [string]$Name,
    [Parameter(Mandatory)] [ValidateSet("DWord","String","ExpandString","QWord","MultiString","Binary")] [string]$Type,
    [Parameter(Mandatory)] $Value
  )

  if (-not (Test-Path $Path)) {
    New-Item -Path $Path -Force | Out-Null
  }

  $existing = $null
  try { $existing = (Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop).$Name } catch {}

  if ($existing -ne $Value) {
    if ($PSCmdlet.ShouldProcess("$Path\$Name", "Set to $Value")) {
      New-ItemProperty -Path $Path -Name $Name -PropertyType $Type -Value $Value -Force | Out-Null
      return @{ Changed = $true; OldValue = $existing; NewValue = $Value }
    }
  }
  return @{ Changed = $false; OldValue = $existing; NewValue = $existing }
}

function Get-RegistryValue {
  param([string]$Path, [string]$Name)
  try { return (Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop).$Name } catch { return $null }
}

$Results = New-Object System.Collections.Generic.List[object]
New-Item -Path $LogPath -Force | Out-Null
Write-Log "Starting legacy services hardening. AuditOnly=$AuditOnly"

# ---------------- 1) SMBv1 ----------------
try {
  $smb1Feature = Get-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -ErrorAction Stop
  $smb1State = $smb1Feature.State
} catch {
  $smb1State = "Unknown (Feature not queryable)"
}

Write-Log "SMB1Protocol feature state: $smb1State"
$Results.Add([pscustomobject]@{ Item="SMBv1 (SMB1Protocol Feature)"; Setting="WindowsOptionalFeature"; Current=$smb1State; Desired="Disabled"; Remediated=$false; Notes="" })

if (-not $AuditOnly) {
  if ($smb1State -eq "Enabled") {
    Write-Log "Disabling SMB1Protocol feature..." "WARN"
    if ($PSCmdlet.ShouldProcess("SMB1Protocol", "Disable-WindowsOptionalFeature")) {
      Disable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -NoRestart -ErrorAction SilentlyContinue | Out-Null
    }
  }

  # Also set SMB1 server/client keys (defense-in-depth)
  $srvRes = Ensure-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" -Name "SMB1" -Type DWord -Value 0
  $cliRes = Ensure-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Services\mrxsmb10" -Name "Start" -Type DWord -Value 4

  Write-Log ("SMB1 Server key SMB1=0 changed={0} old='{1}' new='{2}'" -f $srvRes.Changed, $srvRes.OldValue, $srvRes.NewValue)
  Write-Log ("SMB1 Client driver mrxsmb10 Start=4 changed={0} old='{1}' new='{2}'" -f $cliRes.Changed, $cliRes.OldValue, $cliRes.NewValue)
}

# ---------------- 2) LLMNR ----------------
# Disable LLMNR via policy: HKLM\Software\Policies\Microsoft\Windows NT\DNSClient\EnableMulticast = 0
$llmnrPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient"
$llmnrCurrent = Get-RegistryValue -Path $llmnrPath -Name "EnableMulticast"
Write-Log "LLMNR (EnableMulticast) current: $llmnrCurrent"
$Results.Add([pscustomobject]@{ Item="LLMNR"; Setting="$llmnrPath\EnableMulticast"; Current=$llmnrCurrent; Desired=0; Remediated=$false; Notes="0 disables LLMNR" })

if (-not $AuditOnly) {
  $llmnrRes = Ensure-RegistryValue -Path $llmnrPath -Name "EnableMulticast" -Type DWord -Value 0
  Write-Log ("LLMNR set changed={0} old='{1}' new='{2}'" -f $llmnrRes.Changed, $llmnrRes.OldValue, $llmnrRes.NewValue)
}

# ---------------- 3) NTLMv1 ----------------
# Recommended: set LmCompatibilityLevel to 5 (Send NTLMv2 response only; refuse LM & NTLM)
$ntlmPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa"
$ntlmCurrent = Get-RegistryValue -Path $ntlmPath -Name "LmCompatibilityLevel"
Write-Log "NTLM (LmCompatibilityLevel) current: $ntlmCurrent"
$Results.Add([pscustomobject]@{ Item="NTLMv1"; Setting="$ntlmPath\LmCompatibilityLevel"; Current=$ntlmCurrent; Desired=5; Remediated=$false; Notes="5 = NTLMv2 only, refuse LM/NTLMv1" })

if (-not $AuditOnly) {
  $ntlmRes = Ensure-RegistryValue -Path $ntlmPath -Name "LmCompatibilityLevel" -Type DWord -Value 5
  Write-Log ("NTLM set changed={0} old='{1}' new='{2}'" -f $ntlmRes.Changed, $ntlmRes.OldValue, $ntlmRes.NewValue)
}

# ---------------- 4) NetBIOS ----------------
# Per NIC: Win32_NetworkAdapterConfiguration.TcpipNetbiosOptions
# 0=Use DHCP setting, 1=Enable, 2=Disable
try {
  $nics = Get-CimInstance Win32_NetworkAdapterConfiguration -Filter "IPEnabled = True" -ErrorAction Stop
  foreach ($nic in $nics) {
    $curr = $nic.TcpipNetbiosOptions
    $name = $nic.Description
    Write-Log "NetBIOS over TCP/IP for NIC '$name' current TcpipNetbiosOptions: $curr"
    $Results.Add([pscustomobject]@{ Item="NetBIOS"; Setting="NIC: $name (TcpipNetbiosOptions)"; Current=$curr; Desired=2; Remediated=$false; Notes="2 disables NetBIOS over TCP/IP" })

    if (-not $AuditOnly -and $curr -ne 2) {
      Write-Log "Disabling NetBIOS over TCP/IP on '$name'..." "WARN"
      if ($PSCmdlet.ShouldProcess($name, "SetTcpipNetbios(2)")) {
        Invoke-CimMethod -InputObject $nic -MethodName SetTcpipNetbios -Arguments @{ TcpipNetbiosOptions = 2 } | Out-Null
      }
    }
  }
} catch {
  Write-Log "Failed to query/modify NIC NetBIOS settings: $($_.Exception.Message)" "ERROR"
}

# ---------------- 5) AutoPlay ----------------
# Policy: HKLM\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer\NoDriveTypeAutoRun = 0xFF (255) to disable for all drives
$autoPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer"
$autoCurrent = Get-RegistryValue -Path $autoPath -Name "NoDriveTypeAutoRun"
Write-Log "AutoPlay (NoDriveTypeAutoRun) current: $autoCurrent"
$Results.Add([pscustomobject]@{ Item="AutoPlay/AutoRun"; Setting="$autoPath\NoDriveTypeAutoRun"; Current=$autoCurrent; Desired=255; Remediated=$false; Notes="255 disables AutoRun on all drive types" })

if (-not $AuditOnly) {
  $autoRes = Ensure-RegistryValue -Path $autoPath -Name "NoDriveTypeAutoRun" -Type DWord -Value 255
  Write-Log ("AutoPlay set changed={0} old='{1}' new='{2}'" -f $autoRes.Changed, $autoRes.OldValue, $autoRes.NewValue)
}

# ---------------- 6) Telnet ----------------
# Disable Telnet Client/Server Windows features (where available)
$telnetFeatures = @("TelnetClient","TelnetServer")
foreach ($tf in $telnetFeatures) {
  $state = "Unknown"
  try {
    $feat = Get-WindowsOptionalFeature -Online -FeatureName $tf -ErrorAction Stop
    $state = $feat.State
  } catch {}
  Write-Log "$tf feature state: $state"
  $Results.Add([pscustomobject]@{ Item="Telnet"; Setting="WindowsOptionalFeature: $tf"; Current=$state; Desired="Disabled"; Remediated=$false; Notes="" })

  if (-not $AuditOnly -and $state -eq "Enabled") {
    Write-Log "Disabling $tf..." "WARN"
    if ($PSCmdlet.ShouldProcess($tf, "Disable-WindowsOptionalFeature")) {
      Disable-WindowsOptionalFeature -Online -FeatureName $tf -NoRestart -ErrorAction SilentlyContinue | Out-Null
    }
  }
}

# ---------------- 7) MSDT ----------------
# Mitigation: remove/disable msdt.exe protocol handlers (commonly done via URL protocol keys).
# We disable common MSDT URL protocol handlers by setting "URL Protocol" and command to a benign value / or deleting.
# Safer: set the handler to point to a non-existent command (breaks msdt protocol abuse) without deleting keys.
$msdtKeys = @(
  "HKCR:\ms-msdt",
  "HKCR:\msdt"
)

foreach ($k in $msdtKeys) {
  $exists = Test-Path $k
  Write-Log "MSDT protocol key exists: $k = $exists"
  $Results.Add([pscustomobject]@{ Item="MSDT"; Setting="$k (protocol handler)"; Current=$exists; Desired="Hardened"; Remediated=$false; Notes="Blocks msdt protocol-based invocation" })

  if (-not $AuditOnly -and $exists) {
    # Disable by setting shell\open\command\(Default) to a harmless command
    $cmdPath = Join-Path $k "shell\open\command"
    $currentCmd = Get-RegistryValue -Path $cmdPath -Name "(default)"
    Write-Log "MSDT handler current command at $cmdPath : $currentCmd"

    if ($PSCmdlet.ShouldProcess($cmdPath, "Set default command to 'cmd.exe /c exit'")) {
      if (-not (Test-Path $cmdPath)) { New-Item -Path $cmdPath -Force | Out-Null }
      # Set the (Default) value:
      Set-ItemProperty -Path $cmdPath -Name "(default)" -Value "cmd.exe /c exit" -Force
      Write-Log "MSDT handler hardened at $cmdPath"
    }
  }
}

# ---------------- Post Audit (Re-check key items) ----------------
Write-Log "Generating final report..."

# Mark remediated heuristically: compare after-values for registry items and features
function Add-CheckResult($itemName, $setting, $current, $desired, $notes="") {
  $Results.Add([pscustomobject]@{
    Item=$itemName; Setting=$setting; Current=$current; Desired=$desired;
    Remediated = ($current -eq $desired);
    Notes=$notes
  })
}

# Re-check registry items
Add-CheckResult "LLMNR" "$llmnrPath\EnableMulticast" (Get-RegistryValue $llmnrPath "EnableMulticast") 0 "0 disables LLMNR"
Add-CheckResult "NTLMv1" "$ntlmPath\LmCompatibilityLevel" (Get-RegistryValue $ntlmPath "LmCompatibilityLevel") 5 "5 = NTLMv2 only"
Add-CheckResult "AutoPlay/AutoRun" "$autoPath\NoDriveTypeAutoRun" (Get-RegistryValue $autoPath "NoDriveTypeAutoRun") 255 "255 disables AutoRun"

# Re-check SMBv1 feature (best effort)
try {
  $smb1After = (Get-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -ErrorAction Stop).State
  Add-CheckResult "SMBv1 (SMB1Protocol Feature)" "WindowsOptionalFeature" $smb1After "Disabled" "May require reboot"
} catch {}

# Re-check telnet features
foreach ($tf in $telnetFeatures) {
  try {
    $st = (Get-WindowsOptionalFeature -Online -FeatureName $tf -ErrorAction Stop).State
    Add-CheckResult "Telnet" "WindowsOptionalFeature: $tf" $st "Disabled" ""
  } catch {}
}

# Re-check NetBIOS per NIC
try {
  $nicsAfter = Get-CimInstance Win32_NetworkAdapterConfiguration -Filter "IPEnabled = True" -ErrorAction Stop
  foreach ($nic in $nicsAfter) {
    Add-CheckResult "NetBIOS" ("NIC: {0} (TcpipNetbiosOptions)" -f $nic.Description) $nic.TcpipNetbiosOptions 2 "2 disables NetBIOS over TCP/IP"
  }
} catch {}

# Re-check MSDT handler command (best effort)
foreach ($k in $msdtKeys) {
  if (Test-Path $k) {
    $cmdPath = Join-Path $k "shell\open\command"
    $cmd = Get-RegistryValue -Path $cmdPath -Name "(default)"
    $desired = "cmd.exe /c exit"
    $Results.Add([pscustomobject]@{ Item="MSDT"; Setting="$cmdPath\(Default)"; Current=$cmd; Desired=$desired; Remediated=($cmd -eq $desired); Notes="Hardened protocol handler" })
  }
}

# Export results
$Results | Export-Csv -Path $CsvPath -NoTypeInformation -Force
Write-Log "Report written to: $CsvPath"
Write-Log "Done. Some changes may require reboot."

# Console summary (most recent state entries)
$Results |
  Sort-Object Item, Setting |
  Select-Object Item, Setting, Current, Desired, Remediated |
  Format-Table -AutoSize
