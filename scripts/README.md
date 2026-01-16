Scripts

Linux baseline
- `scripts/linux/collect_baseline.sh` collects read-only host info.
- Run with sudo for full firewall and service visibility.

Linux hardening
- `scripts/linux/harden_linux.sh` supports list/dry-run/apply/backup/restore with probes and backups.

Linux post-change verify
- `scripts/linux/post_change_verify.sh` runs service checks and local health snapshots.
- Run with sudo for full firewall and service visibility.

Windows baseline
- `scripts/windows/collect_baseline.ps1` collects read-only host info.
- Run in an elevated PowerShell session for full results.

Windows hardening
- `scripts/windows/harden_windows.ps1` supports list/dry-run/apply/backup/restore with probes and backups.

Windows post-change verify
- `scripts/windows/post_change_verify.ps1` runs service checks (if python is available) and local health snapshots.
- Run in an elevated PowerShell session for full results.

Splunk forwarder
- `scripts/splunk/forwarder_linux.sh` installs/configures the forwarder on Linux.
- `scripts/splunk/forwarder_windows.ps1` installs/configures the forwarder on Windows.

Firewalls
- `scripts/firewalls/generate_allowlist_plan.py` builds allow-list plans from `config/services.json`.
- `scripts/firewalls/palo_alto_manage.sh` backs up/restores via API (dry-run first).
- `scripts/firewalls/cisco_ftd_manage.sh` backs up/restores via CLI (dry-run first).
- `scripts/firewalls/vyos_manage.sh` backs up/restores and can restrict SSH listen-address.

Probe
- `scripts/probe/` contains read-only probes for Linux, Windows, and firewall/router systems.

Tools
- `scripts/tools/rotate_credentials.py` rotates credentials into `secrets/credentials.md`.
- `scripts/tools/run_service_checks.sh` runs service checks in batches.

Output
- Baselines: `artifacts/baselines/<hostname>-<timestamp>/`.
- Post-change: `artifacts/post_change/<hostname>-<timestamp>/`.
- Backups and plans: `artifacts/backups/` and `artifacts/firewall_plans/`.
