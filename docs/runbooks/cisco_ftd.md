Cisco FTD VM runbook

Purpose
- Control inbound traffic safely while keeping scoring green.

Before changes
- Export the running config and record the version/time.
- Verify management access from the Windows 11 workstation only.

Safe steps
- Restrict management access (web/SSH) to the jump host IPs.
- Build inbound allow-list rules for scored services on assigned public IPs.
- Keep ICMP allowed per rules.
- Log denies on inbound public zones.
- Use `templates/firewall/cisco_ftd_allowlist.md` as the rule checklist.

Rule guidance
- Place allow rules above deny rules.
- Do not change NAT mappings for scored services unless injected.
- Avoid aggressive IPS policies early; test first.

Attack surface & triage focus
- Management plane exposure: FDM access, SSH enabled, allowed management IPs.
- Config drift: access-lists/NAT changes, inspection policies disabled, logging disabled.
- Admin accounts: new local users, password changes, weak auth.
- Logging gaps: syslog destinations removed, event logging off.

Manual checks (diagnostic CLI)
```
show version
show running-config
show interface ip brief
show route
show access-list
show nat
show logging
show service-policy
show conn count
```
Notes: if these fail, run `system support diagnostic-cli` first, then retry.

Injection response scenarios (diagnostic CLI)
```
# Admin and management exposure
show running-config username
show running-config aaa
show running-config ssh
show running-config http

# Policy and NAT drift
show access-list
show nat
show route

# Logging and inspection
show logging
show service-policy
```

Verification
- Use `tools/service_check.py` from a jump host.
- Confirm NISE stays green after each rule change.

Rollback
- Restore from the exported config if scoring breaks.

Command sequences by situation (run from repo root)

SSH works (password auth)
1) `sudo bash scripts/probe/cisco_ftd_probe.sh --host <mgmt_ip> --user admin --pass '<password>'`
2) `sudo bash scripts/firewalls/cisco_ftd_manage.sh --mode backup --host <mgmt_ip> --user admin --pass '<password>'`
3) `sudo bash scripts/firewalls/cisco_ftd_manage.sh --mode dry-run --host <mgmt_ip> --user admin --pass '<password>'`

SSH works (key auth)
1) `sudo bash scripts/probe/cisco_ftd_probe.sh --host <mgmt_ip> --user admin --ssh-key <path>`
2) `sudo bash scripts/firewalls/cisco_ftd_manage.sh --mode backup --host <mgmt_ip> --user admin --ssh-key <path>`
3) `sudo bash scripts/firewalls/cisco_ftd_manage.sh --mode dry-run --host <mgmt_ip> --user admin --ssh-key <path>`

Apply/restore a tested CLI command file
- `sudo bash scripts/firewalls/cisco_ftd_manage.sh --mode restore --host <mgmt_ip> --user admin --pass '<password>' --restore-from <command_file> --allow-unsafe`

SSH fails but console access works (diagnostic CLI)
1) `show version`
2) `show network`
3) `system support diagnostic-cli`
4) `show version`
5) `exit`
Next: enable SSH/management access in FDM, then use the SSH sequences above.
