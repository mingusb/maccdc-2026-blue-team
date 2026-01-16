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

Verification
- Use `tools/service_check.py` from a jump host.
- Confirm NISE stays green after each rule change.

Rollback
- Restore from the exported config if scoring breaks.
