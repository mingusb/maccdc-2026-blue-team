Splunk server runbook (Oracle Linux 9 / Splunk 10)

Purpose
- Central visibility for auth, service, and firewall events.

Before changes
- Confirm Splunk is running and accessible.
- Back up `etc/` (configs) before major changes.

Access control
- Rotate the Splunk admin password.
- Restrict the Web UI to jump host IPs only.

Enable receiving (for forwarders)
- Enable the receiving port (default 9997).
- CLI example:
  - `/opt/splunk/bin/splunk enable listen 9997 -auth admin:<password>`
- See `docs/splunk_forwarder.md` for forwarder setup steps.

Indexes (optional)
- Create a dedicated index like `maccdc` for team logs.
- Keep default index if you prefer less complexity.

Minimum dashboards and searches
- Failed logons (Windows): `index=* EventCode=4625`
- New users (Windows): `index=* EventCode=4720`
- Group changes (Windows): `index=* EventCode=4728 OR EventCode=4732`
- Linux auth failures: `index=* ("Failed password" OR "authentication failure")`
- sudo activity: `index=* ("sudo:" AND "COMMAND=")`
- Firewall denies: `index=* ("DENY" OR "BLOCK")`

Verification
- Confirm forwarders are sending data.
- Run a quick search to verify new events appear after a test login.

Rollback
- Restore from the backed-up `etc/` directory if a change breaks inputs.

Command sequence (run from repo root on Splunk host)
1) `sudo bash scripts/probe/linux_splunk.sh --summary`
2) `sudo bash scripts/linux/harden_linux.sh --mode dry-run --sshd-hardening --enable-firewalld --allow-ports 22,8000,8089,9997`
3) `sudo bash scripts/linux/harden_linux.sh --mode apply --sshd-hardening --enable-firewalld --allow-ports 22,8000,8089,9997`
4) `sudo bash scripts/probe/linux_splunk.sh --summary`

Enable receiving (optional)
- `/opt/splunk/bin/splunk enable listen 9997 -auth admin:<password>`
