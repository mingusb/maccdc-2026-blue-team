Firewall templates

Purpose
- Provide a safe inbound allow-list matrix that mirrors NISE-scored services.
- Use these as checklists, not as drop-in configs.

Files
- `palo_alto_allowlist.md`
- `cisco_ftd_allowlist.md`

Rules of thumb
- Build allow rules only for services shown as scored in NISE.
- Keep ICMP allowed per rules (except Palo Alto core port).
- Do not change NAT mappings unless injected.
- Log denies on inbound public zones.

