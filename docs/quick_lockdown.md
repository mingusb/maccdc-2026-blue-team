Quick lockdown checklist (safe order)

Phase 1: Stabilize and control (first 15-30 minutes)
- Keep Team Portal/NISE open and refresh often.
- Rotate privileged credentials (admin/root/device admin). Avoid changing service accounts until verified.
- Restrict management paths to jump hosts only (SSH/RDP/GUI/Splunk admin).
- Back up configs before major changes (firewall exports, key configs, GPO exports).
- Edge firewalls first: allow-list inbound to only scored ports on assigned public IPs.

Do not do these in the first hour
- Do not change public IP mappings, internal addressing, or hostnames unless injected.
- Do not deploy aggressive IPS policies that can break scoring checks.
- Do not change web content unless you confirm scoring is not comparing content.

Phase 2: MAC (SELinux / AppArmor) with minimal scoring risk
Fedora 42 and Oracle Linux 9 (SELinux ladder)
```sh
sestatus
getenforce
sudo sed -i 's/^SELINUX=.*/SELINUX=permissive/' /etc/selinux/config
sudo sed -i 's/^SELINUXTYPE=.*/SELINUXTYPE=targeted/' /etc/selinux/config
sudo touch /.autorelabel
sudo reboot
# After reboot (still permissive)
sudo ausearch -m avc -ts recent
sudo restorecon -Rv /etc /var /opt
sudo setenforce 1
sudo sed -i 's/^SELINUX=.*/SELINUX=enforcing/' /etc/selinux/config
```

Ubuntu 24.04 (AppArmor quick enable)
```sh
sudo systemctl enable --now apparmor
sudo aa-status
sudo aa-enforce /etc/apparmor.d/usr.sbin.sshd 2>/dev/null
```

Phase 3: Shrink attack surface and improve detection
- Patch in small batches, one host at a time; re-check NISE after each change.
- Disable clearly unused services after verifying they are not scored.
- Harden SSH and RDP access (jump host only).
- Forward key logs to Splunk and confirm time sync.

Per-system quick actions (delegate in hour 1)
- Ubuntu Ecom: confirm web stack stability, restrict SSH to jump host, enforce AppArmor.
- Fedora Webmail: enable SELinux targeted, lock down mail ports, forward logs.
- Splunk: change Splunk admin, restrict UI access, set up basic alerts.
- Ubuntu Wks: treat as jump host, keep clean, use for Palo Alto management.
- Server 2019 AD/DNS: verify AD/DNS health, restrict RDP, enable auditing.
- Server 2019 Web: confirm IIS sites, restrict admin access, watch IIS logs.
- Server 2022 FTP: verify passive range and firewall alignment, enable logging.
- Windows 11 Wks: treat as jump host, lock down local admins, keep Defender healthy.
- Palo Alto: restrict management to jump host, build inbound allow list, export config.
- Cisco FTD: restrict management to Win11 jump host, allow list inbound, export config.
- VyOS: restrict admin access, confirm routing/NAT, back up config.

