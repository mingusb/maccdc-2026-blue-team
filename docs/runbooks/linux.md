Linux runbook (Ubuntu 24.04, Fedora 42, Oracle Linux 9)

Purpose
- Keep scored services stable while reducing risk.
- Prefer reversible changes and record everything.

Before changes
- Confirm scored services and ports in NISE.
- Back up key configs (sshd, web/mail, firewall, resolv, hosts).
- Record current listeners: `ss -tulpn`.

Access control (safe, reversible)
- Restrict SSH management to jump host IPs.
- Disable root SSH login if you have a tested admin account.
- If you must keep password auth for scoring, keep it but allow-list by IP.

Ubuntu 24.04 (AppArmor)
- Ensure AppArmor is enabled: `sudo systemctl enable --now apparmor`.
- Enforce only needed profiles (sshd, web, mail). Do not enforce unknown profiles.

Fedora 42 / Oracle Linux 9 (SELinux ladder)
- Enable targeted policy in permissive mode first, relabel, then enforce.
- Fix labels with `restorecon` before considering custom policy.

Host firewall
- Keep inbound rules aligned with scored ports only.
- Allow management ports only from jump host IPs.
- Do not block TCP/53 if DNS is scored.
- If enabling UFW/firewalld via `scripts/linux/harden_linux.sh`, pass `--allow-ports` for scored ports.

Patching
- Patch in small batches, one host at a time.
- Verify scoring after each patch cycle.

Logging
- Forward auth and system logs to Splunk (see `docs/splunk_forwarder.md`).
- Keep local logs intact for incident response.

Verification
- Run `python3 tools/service_check.py` from a jump host.
- Check `ss -tulpn` and service status after any change.

Rollback
- Keep config backups and a clear last-change record in `templates/change_log.md`.

Command sequences (run from repo root)

Ubuntu Ecom (172.20.242.30)
1) `sudo bash scripts/probe/linux_ecom.sh --summary`
2) `sudo bash scripts/linux/harden_linux.sh --mode dry-run --sshd-hardening --enable-ufw --allow-ports 22,80,443`
3) `sudo bash scripts/linux/harden_linux.sh --mode apply --sshd-hardening --enable-ufw --allow-ports 22,80,443`
4) `sudo bash scripts/probe/linux_ecom.sh --summary`
Notes: drop `443` if HTTPS is not scored.

Fedora Webmail (172.20.242.40)
1) `sudo bash scripts/probe/linux_webmail.sh --summary`
2) `sudo bash scripts/linux/harden_linux.sh --mode dry-run --sshd-hardening --enable-firewalld --allow-ports 22,25,110,143,587,993,995,80,443`
3) `sudo bash scripts/linux/harden_linux.sh --mode apply --sshd-hardening --enable-firewalld --allow-ports 22,25,110,143,587,993,995,80,443`
4) `sudo bash scripts/probe/linux_webmail.sh --summary`
Notes: keep only scored ports; drop 80/443 if webmail is not in use.

Oracle Linux Splunk (172.20.242.20)
1) `sudo bash scripts/probe/linux_splunk.sh --summary`
2) `sudo bash scripts/linux/harden_linux.sh --mode dry-run --sshd-hardening --enable-firewalld --allow-ports 22,8000,8089,9997`
3) `sudo bash scripts/linux/harden_linux.sh --mode apply --sshd-hardening --enable-firewalld --allow-ports 22,8000,8089,9997`
4) `sudo bash scripts/probe/linux_splunk.sh --summary`

Ubuntu workstation (jump host)
1) `sudo bash scripts/probe/maccdc_probe.sh --summary`
2) `sudo bash scripts/linux/harden_linux.sh --mode dry-run --sshd-hardening --enable-ufw --allow-ports 22`
3) `sudo bash scripts/linux/harden_linux.sh --mode apply --sshd-hardening --enable-ufw --allow-ports 22`
4) `sudo bash scripts/probe/maccdc_probe.sh --summary`
