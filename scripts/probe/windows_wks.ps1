<#
Windows workstation probe (read-only).
#>
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
