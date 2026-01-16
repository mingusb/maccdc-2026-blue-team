Palo Alto VM runbook

Purpose
- Control inbound traffic safely while keeping scoring green.

Before changes
- Export the running config and record the version/time.
- Verify management access from the Ubuntu workstation only.

Safe steps
- Restrict management access (web/SSH) to the jump host IPs.
- Build inbound allow-list rules for scored services on assigned public IPs.
- Keep ICMP allowed except the core port (per rules).
- Log denies on inbound public zones to aid detection.
- Use `templates/firewall/palo_alto_allowlist.md` as the rule checklist.

Rule guidance
- Place allow rules above deny rules.
- Do not change NAT mappings for scored services unless injected.
- Avoid aggressive IPS/Threat profiles early; test first.

Verification
- Use `tools/service_check.py` from a jump host.
- Confirm NISE stays green after each rule change.

Rollback
- Restore from the exported config if scoring breaks.

Command sequence (run from repo root)
1) `bash scripts/probe/palo_alto_probe.sh --summary --host <mgmt_ip> --pass '<password>'`
2) `bash scripts/firewalls/palo_alto_manage.sh --mode backup --host <mgmt_ip> --pass '<password>'`
3) `bash scripts/firewalls/palo_alto_manage.sh --mode dry-run --host <mgmt_ip> --pass '<password>' --mgmt-ips 172.20.242.0/24`
4) `bash scripts/firewalls/palo_alto_manage.sh --mode harden --host <mgmt_ip> --pass '<password>' --mgmt-ips 172.20.242.0/24`
5) `bash scripts/probe/palo_alto_probe.sh --summary --host <mgmt_ip> --pass '<password>'`

Restore (if needed)
- `bash scripts/firewalls/palo_alto_manage.sh --mode restore --host <mgmt_ip> --pass '<password>' --restore-from <backup_file>`
