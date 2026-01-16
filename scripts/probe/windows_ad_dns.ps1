<#
AD/DNS probe (read-only).
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

function Service-StatusLine {
  param([string]$Name)
  $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
  if ($null -eq $svc) {
    return "${Name}: missing"
  }
  return "${Name}: $($svc.Status)"
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
  Write-Host "## ad/dns summary"
  $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
  if ($os) {
    Write-Host "os: $($os.Caption) $($os.Version)"
  }
  Write-Host "host: $env:COMPUTERNAME"
  $ip = Get-PrimaryIPv4
  if ($ip) {
    Write-Host "ip: $($ip.IPAddress)/$($ip.PrefixLength)"
  }
  Write-Host (Service-StatusLine -Name "NTDS")
  Write-Host (Service-StatusLine -Name "DNS")

  if (Get-Module -ListAvailable -Name ActiveDirectory) {
    Import-Module ActiveDirectory
    $domain = Get-ADDomain -ErrorAction SilentlyContinue
    if ($domain) {
      Write-Host "domain: $($domain.Name)"
      Write-Host "forest: $($domain.Forest)"
    }
  } else {
    Write-Host "domain: module unavailable"
  }

  if (Get-Command Get-DnsServerZone -ErrorAction SilentlyContinue) {
    $zoneCount = (Get-DnsServerZone | Measure-Object).Count
    Write-Host "dns_zones: $zoneCount"
  } else {
    Write-Host "dns_zones: module unavailable"
  }

  $dnsListen = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Where-Object { $_.LocalPort -eq 53 }
  if ($dnsListen) {
    Write-Host "listeners: 53"
  } else {
    Write-Host "listeners: none"
  }
  Write-Host "firewall: $(Format-FirewallProfiles)"
  Write-SuspiciousProcessSummary
  return
}

Write-Host "## AD and DNS services"
Get-Service NTDS,DNS -ErrorAction SilentlyContinue | Format-Table -AutoSize

Write-Host "## AD domain"
if (Get-Module -ListAvailable -Name ActiveDirectory) {
  Import-Module ActiveDirectory
  Get-ADDomain | Format-List
} else {
  Write-Host "ActiveDirectory module not available"
}

Write-Host "## DNS zones (first 10)"
if (Get-Command Get-DnsServerZone -ErrorAction SilentlyContinue) {
  Get-DnsServerZone | Select-Object -First 10 | Format-Table -AutoSize
} else {
  Write-Host "DnsServer module not available"
}

Write-Host "## listeners 53"
Get-NetTCPConnection -State Listen | Where-Object { $_.LocalPort -eq 53 } | Format-Table -AutoSize
