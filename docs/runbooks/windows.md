Windows runbook (Server 2019/2022, Windows 11)

Purpose
- Keep scored services stable while reducing risk.
- Prefer reversible changes and record everything.

Before changes
- Confirm scored services and ports in NISE.
- Export key configs (GPO, firewall rules, IIS/FTP configs).
- Record current listeners and services.

Access control
- Restrict RDP/WinRM to jump hosts only.
- Reduce local admin membership (after verifying required accounts).
- Rotate privileged passwords and record them in `secrets/`.

Windows Defender and Firewall
- Ensure Defender is enabled and updated.
- Enable Windows Firewall (Domain/Private). Use inbound allow rules for scored ports only.
- Avoid aggressive ASR/WDAC policies unless in Audit mode first.

Server 2019 AD/DNS
- Validate AD and DNS health before hardening (do not break AD).
- Enable auditing for logons, account management, and GPO changes.

Server 2019 Web (IIS)
- Confirm site bindings and content match scoring expectations.
- Enable IIS logging and review for suspicious activity.

Server 2022 FTP
- Confirm passive mode range and align firewall/edge rules.
- Enable FTP logging.

Windows 11 workstation
- Treat as jump host only. Keep clean.
- Restrict browser access to management networks.

Patching
- Patch in small batches, one host at a time.
- Verify scoring after each patch cycle.

Verification
- Run `python3 tools/service_check.py` from a jump host.
- Use `scripts/windows/post_change_verify.ps1` for local checks.

Rollback
- Keep config exports and use the change log template.

Attack surface & triage focus
- Common: RDP/WinRM exposure, new local admins, services with writable paths, scheduled tasks, startup keys, SMB shares, portproxy rules.
- AD/DNS: new domain admins, new GPOs, replication errors, LDAP/Kerberos abuse.
- IIS: web root changes, web.config edits, new app pools/sites, suspicious modules.
- FTP: anonymous access changes, passive range mismatch, large file churn.
- Windows 11 jump host: browser abuse, new admin membership, proxy/route changes.

Manual triage sequences (built-in commands)

Quick snapshot
```
whoami /all
hostname
systeminfo | findstr /B /C:"OS Name" /C:"OS Version"
ipconfig /all
route print
```

Sessions and logons
```
query user
qwinsta
net session
```

Processes, services, startup, tasks
```
Get-Process | Sort-Object CPU -Descending | Select-Object -First 15
Get-Service | Where-Object { $_.Status -eq "Running" } | Sort-Object Name
Get-CimInstance Win32_StartupCommand | Select-Object Name, Command, Location
Get-ScheduledTask | Where-Object { $_.State -eq "Ready" } | Select-Object -First 20
```

Users and admins
```
net user
net localgroup administrators
Get-LocalUser | Select-Object Name, Enabled, LastLogon
```

Network listeners
```
Get-NetTCPConnection -State Listen | Sort-Object LocalPort
netstat -ano | findstr LISTENING
```

Pivot indicators
```
netsh interface portproxy show all
Get-NetTCPConnection -State Established | Select-Object -First 20
Get-SmbShare
Get-SmbSession
Get-CimInstance -Namespace root\subscription -ClassName __EventFilter
Get-CimInstance -Namespace root\subscription -ClassName CommandLineEventConsumer
```

Firewall rules and profiles
```
Get-NetFirewallProfile
Get-NetFirewallRule -Enabled True | Where-Object { $_.DisplayName -like "MACCDC*" }
```

Recent system and security logs
```
wevtutil qe Security /c:50 /rd:true /f:text
wevtutil qe System /c:50 /rd:true /f:text
```

AD/DNS specific
```
dcdiag /q
repadmin /replsummary
nltest /dclist:CCDCteam.com
Get-ADDomain
Get-ADGroupMember "Domain Admins"
Get-DnsServerZone
```

IIS web specific
```
Get-Website
Get-WebBinding
Get-WebConfigurationProperty -Filter /system.webServer/security/authentication/* -Name enabled
Get-ChildItem "C:\\inetpub\\logs\\LogFiles" -Recurse | Sort-Object LastWriteTime -Descending | Select-Object -First 5
```

FTP specific
```
Get-Service FTPSVC
Get-WebConfigurationProperty -Filter /system.ftpServer/security/authentication/* -Name enabled
Get-WebConfigurationProperty -Filter /system.ftpServer/firewallSupport -Name passivePortRange
```

Windows 11 jump host specific
```
Get-LocalGroupMember -Group Administrators
Get-ItemProperty "HKLM:\\Software\\Microsoft\\Windows\\CurrentVersion\\Run"
Get-ItemProperty "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Run"
```

Injection response scenarios (built-in commands)

Suspicious logons, privilege use, log clearing
```
Get-WinEvent -FilterHashtable @{LogName='Security';Id=4624,4625,4672,1102} -MaxEvents 50
Get-WinEvent -FilterHashtable @{LogName='System';Id=104} -MaxEvents 20
```

New services and scheduled tasks
```
Get-WinEvent -FilterHashtable @{LogName='System';Id=7045} -MaxEvents 30
Get-WinEvent -FilterHashtable @{LogName='Security';Id=4697,4698} -MaxEvents 30
Get-ScheduledTask | Sort-Object Date -Descending | Select-Object -First 20
```

PowerShell abuse (if logging enabled)
```
Get-WinEvent -LogName 'Microsoft-Windows-PowerShell/Operational' -MaxEvents 50 | Select-Object -First 20
```

SMB pivot and share access
```
Get-WinEvent -FilterHashtable @{LogName='Security';Id=5140,5145} -MaxEvents 50
Get-SmbShare
Get-SmbSession
```

IIS webshell and site tampering
```
Get-ChildItem "C:\\inetpub\\wwwroot" -Recurse -File | Sort-Object LastWriteTime -Descending | Select-Object -First 20
Get-ChildItem "C:\\inetpub\\wwwroot" -Recurse -Include *.aspx,*.ashx,*.cshtml | Sort-Object LastWriteTime -Descending | Select-Object -First 20
```

FTP abuse
```
Get-ChildItem "C:\\inetpub\\logs\\LogFiles" -Recurse -File | Sort-Object LastWriteTime -Descending | Select-Object -First 20
```

AD abuse (run on DC)
```
Get-WinEvent -FilterHashtable @{LogName='Security';Id=4720,4722,4724,4725,4726,4728,4732,4756,4769,4771,5136} -MaxEvents 50
Get-ADGroupMember "Domain Admins"
Get-ADUser -Filter * -Properties whenCreated | Sort-Object whenCreated -Descending | Select-Object -First 20 Name, whenCreated
```

Command sequences (run in elevated PowerShell from repo root)

Common prep
- `git pull`
- `Set-ExecutionPolicy -Scope Process Bypass -Force`

Windows 11 workstation (jump host)
1) `.\scripts\probe\windows_wks.ps1 -Summary`
2) `.\scripts\windows\harden_windows.ps1 -Mode dry-run -EnableFirewallAll -EnableDefender -EnableAuditing -AllowPorts 3389 -RestrictRdp -MgmtIps 172.20.240.0/24`
3) `.\scripts\windows\harden_windows.ps1 -Mode apply -EnableFirewallAll -EnableDefender -EnableAuditing -AllowPorts 3389 -RestrictRdp -MgmtIps 172.20.240.0/24`
4) `.\scripts\probe\windows_wks.ps1 -Summary`
Notes: add `445` to `-AllowPorts` only if SMB is required on the jump host.

Server 2019 Web (IIS)
1) `.\scripts\probe\windows_iis.ps1 -Summary`
2) `.\scripts\windows\harden_windows.ps1 -Mode dry-run -EnableFirewallAll -EnableDefender -EnableAuditing -AllowPorts 80,3389 -RestrictRdp -MgmtIps 172.20.240.0/24`
3) `.\scripts\windows\harden_windows.ps1 -Mode apply -EnableFirewallAll -EnableDefender -EnableAuditing -AllowPorts 80,3389 -RestrictRdp -MgmtIps 172.20.240.0/24`
4) `.\scripts\probe\windows_iis.ps1 -Summary`
Notes: add `443` to `-AllowPorts` if HTTPS is scored.

Server 2022 FTP
1) `.\scripts\probe\windows_ftp.ps1 -Summary`
2) `.\scripts\windows\harden_windows.ps1 -Mode dry-run -EnableFirewallAll -EnableDefender -EnableAuditing -AllowPorts 21,3389 -RestrictRdp -MgmtIps 172.20.240.0/24`
3) `.\scripts\windows\harden_windows.ps1 -Mode apply -EnableFirewallAll -EnableDefender -EnableAuditing -AllowPorts 21,3389 -RestrictRdp -MgmtIps 172.20.240.0/24`
4) `.\scripts\probe\windows_common.ps1 -Summary`
Notes: add passive FTP ports to `-AllowPorts` if a range is configured.

Server 2019 AD/DNS
1) `.\scripts\probe\windows_ad_dns.ps1 -Summary`
2) `.\scripts\windows\harden_windows.ps1 -Mode dry-run -EnableFirewallAll -EnableDefender -EnableAuditing -AllowPorts 53,88,135,139,389,445,464,636,3268,3269,3389 -AllowUdpPorts 53,88,123,389,464 -RestrictRdp -MgmtIps 172.20.240.0/24`
3) `.\scripts\windows\harden_windows.ps1 -Mode apply -EnableFirewallAll -EnableDefender -EnableAuditing -AllowPorts 53,88,135,139,389,445,464,636,3268,3269,3389 -AllowUdpPorts 53,88,123,389,464 -RestrictRdp -MgmtIps 172.20.240.0/24`
4) `.\scripts\probe\windows_ad_dns.ps1 -Summary`
Notes: add `-RestrictWinrm -MgmtIps 172.20.240.0/24` if WinRM is in use.
