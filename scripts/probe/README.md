Probe scripts

Linux
- `scripts/probe/maccdc_probe.sh` generic Linux probe (Ubuntu/Fedora/Oracle).
- `scripts/probe/linux_ecom.sh` checks web stack on Ubuntu Ecom.
- `scripts/probe/linux_webmail.sh` checks mail stack on Fedora Webmail.
- `scripts/probe/linux_splunk.sh` checks Splunk service on Oracle Linux.

Windows
- `scripts/probe/windows_common.ps1` generic Windows probe.
- `scripts/probe/windows_iis.ps1` IIS web probe.
- `scripts/probe/windows_ftp.ps1` FTP probe.
- `scripts/probe/windows_ad_dns.ps1` AD/DNS probe.
- `scripts/probe/windows_wks.ps1` workstation probe.

Firewalls and router (wrappers)
- `scripts/probe/palo_alto_probe.sh` wraps `scripts/firewalls/palo_alto_manage.sh --mode list`.
- `scripts/probe/palo_alto_probe.sh --summary` prints a one-screen summary.
- Harden via API: `scripts/firewalls/palo_alto_manage.sh --mode harden --host <ip> --pass <pass> --mgmt-ips <cidr>`
- `scripts/probe/cisco_ftd_probe.sh` wraps `scripts/firewalls/cisco_ftd_manage.sh --mode list`.
- `scripts/probe/cisco_ftd_probe.sh --pass <pass>` uses expect for password auth.
- `scripts/probe/vyos_probe.sh` wraps `scripts/firewalls/vyos_manage.sh --mode list`.

All probes are read-only. Use `--summary` on Linux probes for one-screen output.
