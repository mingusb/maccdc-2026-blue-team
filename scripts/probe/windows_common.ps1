<#
Generic Windows probe (read-only).
#>
param(
  [switch]$Summary
)

function Get-PrimaryIPv4 {
  Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } |
    Select-Object -First 1
}

function Format-FirewallProfiles {
  $profiles = Get-NetFirewallProfile | Select-Object Name, Enabled
  if (-not $profiles) { return "unknown" }
  ($profiles | ForEach-Object { "$($_.Name)=$($_.Enabled)" }) -join " "
}

if ($Summary) {
  Write-Host "## windows summary"
  $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
  if ($os) {
    Write-Host "os: $($os.Caption) $($os.Version)"
  }
  Write-Host "host: $env:COMPUTERNAME"
  $ip = Get-PrimaryIPv4
  if ($ip) {
    Write-Host "ip: $($ip.IPAddress)/$($ip.PrefixLength)"
  }
  $route = Get-NetRoute -AddressFamily IPv4 -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($route) {
    Write-Host "route: $($route.NextHop)"
  }
  Write-Host "firewall: $(Format-FirewallProfiles)"
  if (Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue) {
    $mp = Get-MpComputerStatus
    Write-Host "defender: AM=$($mp.AMServiceEnabled) RTP=$($mp.RealTimeProtectionEnabled)"
  }
  $wanted = @(53,80,443,445,3389,5985,5986,389,636,88,135,139)
  $listening = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Select-Object -ExpandProperty LocalPort
  $open = $listening | Where-Object { $wanted -contains $_ } | Sort-Object -Unique
  if ($open) {
    Write-Host "listeners: $($open -join ',')"
  } else {
    Write-Host "listeners: none"
  }
  return
}

Write-Host "## system"
Get-ComputerInfo | Select-Object OsName, OsVersion, WindowsProductName, CsName | Format-List

Write-Host "## network"
Get-NetIPAddress -AddressFamily IPv4 | Format-Table -AutoSize
Get-NetRoute -AddressFamily IPv4 | Format-Table -AutoSize

Write-Host "## listening ports"
Get-NetTCPConnection -State Listen | Sort-Object LocalPort | Select-Object LocalAddress, LocalPort, OwningProcess | Format-Table -AutoSize

Write-Host "## firewall profiles"
Get-NetFirewallProfile | Format-List

Write-Host "## defender"
if (Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue) {
  Get-MpComputerStatus | Select-Object AMServiceEnabled, RealTimeProtectionEnabled | Format-Table -AutoSize
}
