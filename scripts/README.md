Scripts

Linux baseline
- `scripts/linux/collect_baseline.sh` collects read-only host info.
- Run with sudo for full firewall and service visibility.

Linux post-change verify
- `scripts/linux/post_change_verify.sh` runs service checks and local health snapshots.
- Run with sudo for full firewall and service visibility.

Windows baseline
- `scripts/windows/collect_baseline.ps1` collects read-only host info.
- Run in an elevated PowerShell session for full results.

Windows post-change verify
- `scripts/windows/post_change_verify.ps1` runs service checks (if python is available) and local health snapshots.
- Run in an elevated PowerShell session for full results.

Output
- Baselines: `artifacts/baselines/<hostname>-<timestamp>/`.
- Post-change: `artifacts/post_change/<hostname>-<timestamp>/`.
