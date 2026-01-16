<#
FTP probe (read-only).
#>
param(
  [switch]$Summary
)

function Get-PrimaryIPv4 {
  Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } |
    Select-Object -First 1
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
  Write-Host "## ftp summary"
  $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
  if ($os) {
    Write-Host "os: $($os.Caption) $($os.Version)"
  }
  Write-Host "host: $env:COMPUTERNAME"
  $ip = Get-PrimaryIPv4
  if ($ip) {
    Write-Host "ip: $($ip.IPAddress)/$($ip.PrefixLength)"
  }
  $svc = Get-Service FTPSVC -ErrorAction SilentlyContinue
  if ($svc) {
    Write-Host "FTPSVC: $($svc.Status)"
  } else {
    Write-Host "FTPSVC: missing"
  }
  if (Get-Module -ListAvailable -Name WebAdministration) {
    Import-Module WebAdministration
    $sites = Get-Website
    $ftpSites = $sites | Where-Object { $_.Bindings.Collection.bindingInformation -match ":21:" }
    Write-Host "ftp_sites: $($ftpSites.Count)"
  } else {
    Write-Host "ftp_sites: module unavailable"
  }
  $listening = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Select-Object -ExpandProperty LocalPort
  if ($listening -contains 21) {
    Write-Host "listeners: 21"
  } else {
    Write-Host "listeners: none"
  }
  Write-SuspiciousProcessSummary
  return
}

Write-Host "## FTP services"
Get-Service FTPSVC -ErrorAction SilentlyContinue | Format-Table -AutoSize

Write-Host "## IIS FTP config"
if (Get-Module -ListAvailable -Name WebAdministration) {
  Import-Module WebAdministration
  Get-WebConfigurationProperty -Filter "system.applicationHost/sites" -Name . | Out-String | Select-Object -First 20
} else {
  Write-Host "WebAdministration module not available"
}

Write-Host "## listeners 21"
Get-NetTCPConnection -State Listen | Where-Object { $_.LocalPort -eq 21 } | Format-Table -AutoSize
