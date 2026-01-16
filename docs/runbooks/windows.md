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

