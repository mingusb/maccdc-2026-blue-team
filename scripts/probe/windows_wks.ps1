<#
Windows workstation probe (read-only).
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

function Write-SuspiciousProcessSummary {
  $allowedPrefixes = @(
    'C:\Windows\',
    'C:\Program Files\',
    'C:\Program Files (x86)\'
  )
  $suspects = @()
  Get-Process -ErrorAction SilentlyContinue |
    Where-Object { $_.Path } |
    ForEach-Object {
      $path = $_.Path
      $allowed = $false
      foreach ($prefix in $allowedPrefixes) {
        if ($path.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
          $allowed = $true
          break
        }
      }
      if (-not $allowed) {
        $suspects += $_
      }
    }
  if ($suspects.Count -eq 0) {
    Write-Host "suspicious_procs: none"
    return
  }
  Write-Host "suspicious_procs: $($suspects.Count)"
  $suspects | Select-Object -First 3 | ForEach-Object {
    Write-Host "proc: $($_.Id) $($_.ProcessName) $($_.Path)"
  }
}

if ($Summary) {
  Write-Host "## workstation summary"
  $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
  if ($os) {
    Write-Host "os: $($os.Caption) $($os.Version)"
  }
  Write-Host "host: $env:COMPUTERNAME"
  $ip = Get-PrimaryIPv4
  if ($ip) {
    Write-Host "ip: $($ip.IPAddress)/$($ip.PrefixLength)"
  }
  if (Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue) {
    $mp = Get-MpComputerStatus
    Write-Host "defender: AM=$($mp.AMServiceEnabled) RTP=$($mp.RealTimeProtectionEnabled)"
  }
  $rdp = Get-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections -ErrorAction SilentlyContinue
  if ($rdp) {
    $state = if ($rdp.fDenyTSConnections -eq 0) { "enabled" } else { "disabled" }
    Write-Host "rdp: $state"
  }
  $proxy = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction SilentlyContinue
  if ($proxy) {
    $proxyState = if ($proxy.ProxyEnable -eq 1) { "enabled" } else { "disabled" }
    $proxyServer = if ($proxy.ProxyServer) { $proxy.ProxyServer } else { "none" }
    Write-Host "proxy: $proxyState ($proxyServer)"
  }
  Write-Host "firewall: $(Format-FirewallProfiles)"
  $wanted = @(3389,445,5985,5986)
  $listening = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Select-Object -ExpandProperty LocalPort
  $open = $listening | Where-Object { $wanted -contains $_ } | Sort-Object -Unique
  if ($open) {
    Write-Host "listeners: $($open -join ',')"
  } else {
    Write-Host "listeners: none"
  }
  Write-SuspiciousProcessSummary
  return
}

Write-Host "## system"
Get-ComputerInfo | Select-Object OsName, OsVersion, WindowsProductName, CsName | Format-List

Write-Host "## defender"
if (Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue) {
  Get-MpComputerStatus | Select-Object AMServiceEnabled, RealTimeProtectionEnabled | Format-Table -AutoSize
}

Write-Host "## browser proxies"
Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction SilentlyContinue | Select-Object ProxyEnable, ProxyServer | Format-Table -AutoSize

Write-Host "## listeners"
Get-NetTCPConnection -State Listen | Sort-Object LocalPort | Select-Object LocalAddress, LocalPort, OwningProcess | Format-Table -AutoSize
