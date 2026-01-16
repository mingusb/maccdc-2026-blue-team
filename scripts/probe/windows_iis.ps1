<#
IIS web probe (read-only).
#>
param(
  [switch]$Summary
)

function Get-PrimaryIPv4 {
  Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } |
    Select-Object -First 1
}

if ($Summary) {
  Write-Host "## iis summary"
  $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
  if ($os) {
    Write-Host "os: $($os.Caption) $($os.Version)"
  }
  Write-Host "host: $env:COMPUTERNAME"
  $ip = Get-PrimaryIPv4
  if ($ip) {
    Write-Host "ip: $($ip.IPAddress)/$($ip.PrefixLength)"
  }
  $svc = Get-Service W3SVC -ErrorAction SilentlyContinue
  if ($svc) {
    Write-Host "W3SVC: $($svc.Status)"
  } else {
    Write-Host "W3SVC: missing"
  }
  if (Get-Module -ListAvailable -Name WebAdministration) {
    Import-Module WebAdministration
    $sites = Get-Website
    Write-Host "sites: $($sites.Count)"
  } else {
    Write-Host "sites: module unavailable"
  }
  $listening = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Select-Object -ExpandProperty LocalPort
  $open = $listening | Where-Object { $_ -in 80,443 } | Sort-Object -Unique
  if ($open) {
    Write-Host "listeners: $($open -join ',')"
  } else {
    Write-Host "listeners: none"
  }
  return
}

Write-Host "## IIS services"
Get-Service W3SVC -ErrorAction SilentlyContinue | Format-Table -AutoSize

Write-Host "## IIS sites"
if (Get-Module -ListAvailable -Name WebAdministration) {
  Import-Module WebAdministration
  Get-Website | Format-Table -AutoSize
} else {
  Write-Host "WebAdministration module not available"
}

Write-Host "## listeners 80/443"
Get-NetTCPConnection -State Listen | Where-Object { $_.LocalPort -in 80,443 } | Format-Table -AutoSize
