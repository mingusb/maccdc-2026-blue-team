<#
Collects read-only baseline info for a Windows host.
Run in an elevated PowerShell session for full results.
#>
param(
  [string]$OutputDir = ""
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Resolve-Path (Join-Path $ScriptDir "..\..")
$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"

if ([string]::IsNullOrWhiteSpace($OutputDir)) {
  $OutputDir = Join-Path $RepoRoot "artifacts\baselines\$env:COMPUTERNAME-$Timestamp"
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

function Write-Section {
  param(
    [string]$Name,
    [scriptblock]$Block
  )
  $Path = Join-Path $OutputDir ("$Name.txt")
  "## $Name" | Out-File -FilePath $Path -Encoding UTF8
  try {
    & $Block | Out-String | Out-File -FilePath $Path -Append -Encoding UTF8
  } catch {
    "error: $($_.Exception.Message)" | Out-File -FilePath $Path -Append -Encoding UTF8
  }
}

Write-Section -Name "system" -Block { Get-ComputerInfo | Format-List * }
Write-Section -Name "os" -Block { Get-CimInstance Win32_OperatingSystem | Format-List * }
Write-Section -Name "network" -Block { Get-NetIPAddress -AddressFamily IPv4 | Format-Table -AutoSize }
Write-Section -Name "routes" -Block { Get-NetRoute -AddressFamily IPv4 | Format-Table -AutoSize }
Write-Section -Name "listening_ports" -Block { Get-NetTCPConnection -State Listen | Sort-Object LocalPort | Format-Table -AutoSize }
Write-Section -Name "firewall_profiles" -Block { Get-NetFirewallProfile | Format-List * }
Write-Section -Name "running_services" -Block { Get-Service | Where-Object { $_.Status -eq "Running" } | Sort-Object Name | Format-Table -AutoSize }
Write-Section -Name "local_users" -Block { Get-LocalUser | Select-Object Name, Enabled, LastLogon | Format-Table -AutoSize }
Write-Section -Name "local_admins" -Block { Get-LocalGroupMember -Group "Administrators" | Select-Object Name, ObjectClass | Format-Table -AutoSize }

if (Get-Command Get-WindowsFeature -ErrorAction SilentlyContinue) {
  Write-Section -Name "windows_features" -Block {
    Get-WindowsFeature | Where-Object { $_.Installed -eq $true } | Format-Table -AutoSize
  }
}

Write-Output "Baseline captured in: $OutputDir"
