<#
FTP probe (read-only).
#>
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
