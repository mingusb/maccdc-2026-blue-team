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

Attack surface & triage focus
- Management plane: SSH listen-address, user accounts, allowed IPs.
- Config drift: NAT rules, firewall rules, route changes.
- Logging gaps: syslog targets removed, log levels reduced.

Manual checks (CLI)
```
show configuration
show configuration commands
show interfaces
show ip route
show nat source rules
show nat destination rules
show firewall
show service ssh
show log
```

Injection response scenarios (CLI)
```
# Users and SSH exposure
show configuration commands | match login
show configuration commands | match service ssh

# NAT/firewall drift
show nat source rules
show nat destination rules
show firewall

# VPN tunnels
show vpn ipsec sa
show vpn l2tp
```

Verification
- Confirm routing between subnets still works.
- Re-check NISE after any change.

Rollback
- Restore the saved config if routing breaks.

Command sequences by situation (run from repo root)

SSH works (key auth)
1) `bash scripts/probe/vyos_probe.sh --host <mgmt_ip>`
2) `bash scripts/firewalls/vyos_manage.sh --mode backup --host <mgmt_ip> --user vyos`
3) `bash scripts/firewalls/vyos_manage.sh --mode dry-run --host <mgmt_ip> --user vyos --restrict-ssh --mgmt-ips <mgmt_ip1,mgmt_ip2>`
4) `bash scripts/firewalls/vyos_manage.sh --mode apply --host <mgmt_ip> --user vyos --restrict-ssh --mgmt-ips <mgmt_ip1,mgmt_ip2>`
5) `bash scripts/probe/vyos_probe.sh --host <mgmt_ip>`

SSH works but you must replace existing listen-address
1) `bash scripts/firewalls/vyos_manage.sh --mode dry-run --host <mgmt_ip> --user vyos --restrict-ssh --replace-ssh --mgmt-ips <mgmt_ip1,mgmt_ip2>`
2) `bash scripts/firewalls/vyos_manage.sh --mode apply --host <mgmt_ip> --user vyos --restrict-ssh --replace-ssh --mgmt-ips <mgmt_ip1,mgmt_ip2>`

Console only (no SSH)
1) `show configuration commands`
2) `configure`
3) `delete service ssh listen-address`
4) `set service ssh listen-address <mgmt_ip1>`
5) `set service ssh listen-address <mgmt_ip2>`
6) `commit`
7) `save`
8) `exit`
Next: use the SSH sequences above for backups and future changes.

Restore (if needed)
- `bash scripts/firewalls/vyos_manage.sh --mode restore --host <mgmt_ip> --user vyos --restore-from <backup_file>`
