<#
Post-change verification: service checks + local health snapshots.
#>
param(
  [string]$OutputDir = "",
  [string]$ConfigPath = "",
  [string]$Tag = ""
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Resolve-Path (Join-Path $ScriptDir "..\..")
$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"

if ([string]::IsNullOrWhiteSpace($OutputDir)) {
  $OutputDir = Join-Path $RepoRoot "artifacts\post_change\$env:COMPUTERNAME-$Timestamp"
}

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
  $ConfigPath = Join-Path $RepoRoot "config\services.json"
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

if (-not [string]::IsNullOrWhiteSpace($Tag)) {
  $TagPath = Join-Path $OutputDir "tag.txt"
  "tag: $Tag" | Out-File -FilePath $TagPath -Encoding UTF8
}

$PythonCmd = (Get-Command python -ErrorAction SilentlyContinue)
if (-not $PythonCmd) {
  $PythonCmd = (Get-Command python3 -ErrorAction SilentlyContinue)
}

$ServiceOut = Join-Path $OutputDir "service_check.json"
if ($PythonCmd -and (Test-Path $ConfigPath)) {
  & $PythonCmd.Path (Join-Path $RepoRoot "tools\service_check.py") --config $ConfigPath --output $ServiceOut | Out-Null
} else {
  "service_check skipped (missing python or config)" | Out-File -FilePath (Join-Path $OutputDir "service_check.txt") -Encoding UTF8
}

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

Write-Section -Name "systeminfo" -Block { systeminfo }
Write-Section -Name "network" -Block { Get-NetIPAddress -AddressFamily IPv4 | Format-Table -AutoSize }
Write-Section -Name "routes" -Block { Get-NetRoute -AddressFamily IPv4 | Format-Table -AutoSize }
Write-Section -Name "listening_ports" -Block { Get-NetTCPConnection -State Listen | Sort-Object LocalPort | Format-Table -AutoSize }
Write-Section -Name "firewall_profiles" -Block { Get-NetFirewallProfile | Format-List * }
Write-Section -Name "running_services" -Block { Get-Service | Where-Object { $_.Status -eq "Running" } | Sort-Object Name | Format-Table -AutoSize }
Write-Section -Name "local_admins" -Block { Get-LocalGroupMember -Group "Administrators" | Select-Object Name, ObjectClass | Format-Table -AutoSize }

Write-Output "Post-change verification captured in: $OutputDir"
