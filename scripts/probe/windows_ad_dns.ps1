<#
AD/DNS probe (read-only).
#>
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
