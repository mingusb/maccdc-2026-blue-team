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
