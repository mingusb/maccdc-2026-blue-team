<#
Generic Windows probe (read-only).
#>
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
