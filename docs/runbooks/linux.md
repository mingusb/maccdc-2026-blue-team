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

Attack surface & triage focus
- SSH: brute force, new keys/users, sshd config drift.
- Web: new/changed files in web roots, unexpected vhosts, suspicious PHP/CGI.
- Mail: relay or auth changes, queue spikes, new mail users.
- DB: new users, remote bind, data exfil attempts.
- Persistence: new systemd units, timers, cron jobs, SUID binaries, shell rc edits.
- Pivoting: new listening ports, IP forwarding/NAT, reverse tunnels.

Triage sequences (built-in commands)
```
# SSH/auth
sudo grep -Ei "sshd|Failed password|Accepted|Invalid user" /var/log/auth.log /var/log/secure 2>/dev/null | tail -n 50
sudo ls -la /home/*/.ssh /root/.ssh 2>/dev/null
sudo grep -R "PermitRootLogin|PasswordAuthentication" /etc/ssh/sshd_config /etc/ssh/sshd_config.d 2>/dev/null

# Web root changes
sudo find /var/www /srv -type f -mtime -2 -ls | head -n 50
sudo apache2ctl -S 2>/dev/null || sudo nginx -T 2>/dev/null | head -n 80

# Mail queues (if applicable)
sudo postqueue -p 2>/dev/null | head -n 40
sudo dovecot -n 2>/dev/null | head -n 40

# Services and persistence
systemctl --type=service --state=running
systemctl list-unit-files --state=enabled
systemctl list-timers
crontab -l
sudo crontab -l
sudo ls -la /etc/cron.* /etc/cron.d

# Pivot indicators
ss -tulpn
sysctl net.ipv4.ip_forward
sudo iptables -t nat -S
sudo firewall-cmd --list-all 2>/dev/null || true
```

Verification
- Run `python3 tools/service_check.py` from a jump host.
- Check `ss -tulpn` and service status after any change.

Rollback
- Keep config backups and a clear last-change record in `templates/change_log.md`.

Manual triage sequences (built-in commands)

Quick snapshot
```
hostnamectl 2>/dev/null || cat /etc/os-release
date
who -a
last -n 10
```

Network and listeners
```
ip -brief addr
ip route
ss -tulpn
```

Processes and services
```
ps auxf | head -n 40
systemctl --type=service --state=running
systemctl list-timers
```

Persistence checks
```
crontab -l
sudo crontab -l
ls -la /etc/cron.* /etc/cron.d
systemctl list-unit-files --state=enabled
ls -la /etc/systemd/system /lib/systemd/system
```

Auth and system logs
```
sudo journalctl -p warning..alert -n 200
sudo journalctl -u ssh -n 200
sudo tail -n 200 /var/log/auth.log
sudo tail -n 200 /var/log/secure
```
Notes: use whichever log file exists for your distro.

File and binary review
```
sudo find /tmp /var/tmp /dev/shm -type f -printf '%TY-%Tm-%Td %TT %p\n' | sort | tail -n 50
sudo find /var/www /srv -type f -mtime -2 -ls | head -n 50
sudo find / -xdev -type f \( -perm -4000 -o -perm -2000 \) -ls 2>/dev/null | head -n 50
```

Package integrity spot check
```
sudo dpkg -V | head -n 50
sudo rpm -Va | head -n 50
```
Notes: use `dpkg -V` on Debian/Ubuntu and `rpm -Va` on Fedora/Oracle Linux.

Web stack (if applicable)
```
sudo apache2ctl -S 2>/dev/null || true
sudo nginx -T 2>/dev/null | head -n 200 || true
```

Mail stack (if applicable)
```
sudo postconf -n 2>/dev/null | head -n 40 || true
sudo dovecot -n 2>/dev/null | head -n 40 || true
```

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
