MACCDC 2026 Blue Team Repo

Purpose
- Central place for MACCDC 2026 docs, checklists, and safe tools.
- Designed to keep scoring services stable while hardening.

Quick start
1) Review the guardrails and topology docs so we do not break scoring.
2) Edit `config/services.json` to match NISE-scored services.
3) Run `python3 tools/service_check.py` from a jump host to validate services after changes.
4) Run baseline collection scripts on each host to capture a known-good snapshot.
5) Use hardening scripts in dry-run mode to plan safe changes.
6) Use post-change verification scripts after any major change.

What is here
- `docs/` quick references, topology, inventory, and checklists.
- `docs/runbooks/` safe hardening runbooks per system.
- `docs/splunk_forwarder.md` Splunk forwarder setup guide.
- `tools/` safe service checks and helper utilities.
- `scripts/` host hardening, firewall helpers, Splunk forwarder installers, and verification tooling.
- `templates/` inject response, incident report, change log, and firewall allow-list templates.

Operational notes
- Do not change public IP mappings, internal addressing, or hostnames unless an inject says so.
- Keep ICMP enabled except the Palo Alto core port per the rules.
- Store rotated credentials in `secrets/` and keep them out of Git.
