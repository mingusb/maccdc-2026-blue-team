Verification loop (after every change)

Checklist
- Refresh Team Portal/NISE for scoring status.
- Run local service checks from a jump host.
- If something breaks, roll back the last change first.

Service check tool
- Edit `config/services.json` (already present) to match NISE-scored services.
- Or copy `tools/service_check.example.json` to `config/services.json` if you want a clean reset.
- Run `python3 tools/service_check.py` from the jump host.
- Results are written to `artifacts/service_checks/` by default.

Post-change scripts
- Linux: `scripts/linux/post_change_verify.sh` (service checks + local health snapshot).
- Windows: `scripts/windows/post_change_verify.ps1` (service checks if python exists + local health snapshot).

Manual commands (fallback)
- HTTP/HTTPS: `curl -i http://<host>/` and `curl -k -i https://<host>/`
- DNS: `dig @<dns_ip> example.com` or `nslookup example.com <dns_ip>`
- SMTP: `nc -v <smtp_ip> 25`
- POP3: `nc -v <pop3_ip> 110`
- FTP: `nc -v <ftp_ip> 21`
