VyOS router runbook

Purpose
- Keep routing/NAT stable and restrict admin access.

Before changes
- Save a config backup and record the timestamp.
- Verify current routing and NAT behavior.

Safe steps
- Restrict SSH management to jump host IPs.
- Disable unused services (but keep SSH if needed).
- Keep existing routes and NAT mappings unless injected.

Verification
- Confirm routing between subnets still works.
- Re-check NISE after any change.

Rollback
- Restore the saved config if routing breaks.

Command sequence (run from repo root)
1) `bash scripts/probe/vyos_probe.sh --host <mgmt_ip>`
2) `bash scripts/firewalls/vyos_manage.sh --mode backup --host <mgmt_ip> --user vyos`
3) `bash scripts/firewalls/vyos_manage.sh --mode dry-run --host <mgmt_ip> --user vyos --restrict-ssh --mgmt-ips <mgmt_ip1,mgmt_ip2>`
4) `bash scripts/firewalls/vyos_manage.sh --mode apply --host <mgmt_ip> --user vyos --restrict-ssh --mgmt-ips <mgmt_ip1,mgmt_ip2>`
5) `bash scripts/probe/vyos_probe.sh --host <mgmt_ip>`

Restore (if needed)
- `bash scripts/firewalls/vyos_manage.sh --mode restore --host <mgmt_ip> --user vyos --restore-from <backup_file>`
