<#
IIS web probe (read-only).
#>
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
